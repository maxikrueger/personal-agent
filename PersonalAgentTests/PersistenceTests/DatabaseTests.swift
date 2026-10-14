import XCTest
@testable import PersonalAgent

final class DatabaseTests: XCTestCase {
    private var latestSchemaVersion: Int {
        SchemaMigrations.all.map(\.version).max() ?? 0
    }

    func testMigrationSetsSchemaVersion() async throws {
        let database = try await makeTestDatabase()
        let version = try await database.schemaVersion()
        XCTAssertEqual(version, latestSchemaVersion)
    }

    func testMigrationIsIdempotent() async throws {
        let database = try await makeTestDatabase()
        try await database.migrate(SchemaMigrations.all)
        let version = try await database.schemaVersion()
        XCTAssertEqual(version, latestSchemaVersion)
    }

    func testMigrationCreatesTables() async throws {
        let database = try await makeTestDatabase()
        let rows = try await database.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
        )
        let names = rows.compactMap { SQLiteMapping.text($0[0]) }
        XCTAssertTrue(names.contains("tasks"))
        XCTAssertTrue(names.contains("task_events"))
        XCTAssertTrue(names.contains("recommendations"))
        XCTAssertTrue(names.contains("recommendation_outcomes"))
    }

    func testStepwiseUpgradeFromV1PreservesData() async throws {
        let database = SQLiteDatabase()
        try await database.open(at: ":memory:")
        let v1 = SchemaMigrations.all.filter { $0.version == 1 }
        try await database.migrate(v1)
        let repository = TaskRepository(database: database)
        let task = makeTask(title: "Alt")
        try await repository.upsert(task, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))

        try await database.migrate(SchemaMigrations.all)

        let version = try await database.schemaVersion()
        XCTAssertEqual(version, latestSchemaVersion)
        let fetched = try await repository.task(withID: task.id)
        XCTAssertEqual(fetched, task)
    }

    func testBindingRoundtripPreservesValues() async throws {
        let database = try await makeTestDatabase()
        try await database.execute(
            """
            INSERT INTO tasks (id, external_id, title, notes, due_date, is_completed, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
            """,
            bindings: [
                .text("id-1"),
                .text("ext-1"),
                .text("Über die Brücke gehen"),
                .null,
                .real(1234.5),
                .integer(1),
                .real(1_800_000_000),
            ]
        )
        let rows = try await database.query(
            "SELECT title, notes, due_date, is_completed FROM tasks WHERE id = ?1",
            bindings: [.text("id-1")]
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0][0], .text("Über die Brücke gehen"))
        XCTAssertEqual(rows[0][1], .null)
        XCTAssertEqual(rows[0][2], .real(1234.5))
        XCTAssertEqual(rows[0][3], .integer(1))
    }

    func testQueryOnUnopenedDatabaseThrows() async {
        let database = SQLiteDatabase()
        do {
            _ = try await database.query("SELECT 1")
            XCTFail("Expected DatabaseError")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }

    func testInvalidSQLThrows() async throws {
        let database = try await makeTestDatabase()
        do {
            try await database.execute("NOT VALID SQL")
            XCTFail("Expected DatabaseError")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }
}
