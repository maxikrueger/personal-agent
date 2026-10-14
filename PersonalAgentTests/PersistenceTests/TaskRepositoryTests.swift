import XCTest
@testable import PersonalAgent

final class TaskRepositoryTests: XCTestCase {
    func testUpsertAndFetchRoundtrip() async throws {
        let repository = TaskRepository(database: try await makeTestDatabase())
        let task = makeTask(
            externalID: "ext-1",
            title: "Steuerunterlagen sortieren",
            notes: "Ordner im Regal",
            dueDate: Date(timeIntervalSince1970: 1_800_100_000),
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            completionDate: nil,
            isCompleted: false,
            listName: "Privat"
        )

        try await repository.upsert(task, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let fetched = try await repository.task(withID: task.id)

        XCTAssertEqual(fetched, task)
    }

    func testUpsertWithNilOptionalsRoundtrips() async throws {
        let repository = TaskRepository(database: try await makeTestDatabase())
        let task = makeTask(externalID: "ext-1", title: "Nur Titel")

        try await repository.upsert(task, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let fetched = try await repository.task(withID: task.id)

        XCTAssertEqual(fetched, task)
    }

    func testUpsertUpdatesExistingRow() async throws {
        let repository = TaskRepository(database: try await makeTestDatabase())
        let original = makeTask(externalID: "ext-1", title: "Alt")
        let updated = makeTask(
            id: original.id,
            externalID: "ext-1",
            title: "Neu",
            completionDate: Date(timeIntervalSince1970: 1_800_050_000),
            isCompleted: true
        )

        try await repository.upsert(original, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try await repository.upsert(updated, updatedAt: Date(timeIntervalSince1970: 1_800_100_000))

        let all = try await repository.allTasks()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0], updated)
    }

    func testTasksByExternalIDKeysByExternalID() async throws {
        let repository = TaskRepository(database: try await makeTestDatabase())
        let first = makeTask(externalID: "ext-a", title: "A")
        let second = makeTask(externalID: "ext-b", title: "B")
        try await repository.upsert(first, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try await repository.upsert(second, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let byExternalID = try await repository.tasksByExternalID()

        XCTAssertEqual(byExternalID.count, 2)
        XCTAssertEqual(byExternalID["ext-a"], first)
        XCTAssertEqual(byExternalID["ext-b"], second)
    }

    func testTaskWithUnknownIDReturnsNil() async throws {
        let repository = TaskRepository(database: try await makeTestDatabase())
        let fetched = try await repository.task(withID: UUID())
        XCTAssertNil(fetched)
    }
}
