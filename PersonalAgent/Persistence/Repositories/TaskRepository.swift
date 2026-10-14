import Foundation

struct TaskRepository: Sendable {
    let database: SQLiteDatabase

    func upsert(_ task: Task, updatedAt: Date) async throws {
        try await database.execute(
            """
            INSERT INTO tasks (
                id, external_id, title, notes, due_date, creation_date,
                completion_date, is_completed, list_name, updated_at
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
            ON CONFLICT(id) DO UPDATE SET
                external_id = excluded.external_id,
                title = excluded.title,
                notes = excluded.notes,
                due_date = excluded.due_date,
                creation_date = excluded.creation_date,
                completion_date = excluded.completion_date,
                is_completed = excluded.is_completed,
                list_name = excluded.list_name,
                updated_at = excluded.updated_at
            """,
            bindings: [
                .text(task.id.uuidString),
                .text(task.externalID),
                .text(task.title),
                SQLiteMapping.optionalText(task.notes),
                SQLiteMapping.optionalDate(task.dueDate),
                SQLiteMapping.optionalDate(task.creationDate),
                SQLiteMapping.optionalDate(task.completionDate),
                .integer(task.isCompleted ? 1 : 0),
                SQLiteMapping.optionalText(task.listName),
                .real(updatedAt.timeIntervalSince1970),
            ]
        )
    }

    func allTasks() async throws -> [Task] {
        let rows = try await database.query(
            """
            SELECT id, external_id, title, notes, due_date, creation_date,
                   completion_date, is_completed, list_name
            FROM tasks
            ORDER BY external_id
            """
        )
        return try rows.map(Self.task(fromRow:))
    }

    func tasksByExternalID() async throws -> [String: Task] {
        Dictionary(uniqueKeysWithValues: try await allTasks().map { ($0.externalID, $0) })
    }

    func task(withID id: UUID) async throws -> Task? {
        let rows = try await database.query(
            """
            SELECT id, external_id, title, notes, due_date, creation_date,
                   completion_date, is_completed, list_name
            FROM tasks
            WHERE id = ?1
            LIMIT 1
            """,
            bindings: [.text(id.uuidString)]
        )
        return try rows.first.map(Self.task(fromRow:))
    }

    static func task(fromRow row: [SQLiteValue]) throws -> Task {
        guard row.count >= 9,
              case .text(let idString) = row[0],
              let id = UUID(uuidString: idString),
              case .text(let externalID) = row[1],
              case .text(let title) = row[2],
              case .integer(let completedFlag) = row[7] else {
            throw DatabaseError(message: "unexpected tasks row shape")
        }
        return Task(
            id: id,
            externalID: externalID,
            title: title,
            notes: SQLiteMapping.text(row[3]),
            dueDate: SQLiteMapping.date(row[4]),
            creationDate: SQLiteMapping.date(row[5]),
            completionDate: SQLiteMapping.date(row[6]),
            isCompleted: completedFlag != 0,
            listName: SQLiteMapping.text(row[8])
        )
    }
}
