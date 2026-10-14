import Foundation

struct TaskEventRepository: Sendable {
    let database: SQLiteDatabase

    func insert(_ event: TaskEvent) async throws {
        try await database.execute(
            """
            INSERT INTO task_events (id, task_id, event_type, timestamp, metadata_json)
            VALUES (?1, ?2, ?3, ?4, ?5)
            """,
            bindings: [
                .text(event.id.uuidString),
                .text(event.taskID.uuidString),
                .text(event.type.rawValue),
                .real(event.timestamp.timeIntervalSince1970),
                .text(Self.encodeMetadata(event.metadata)),
            ]
        )
    }

    func events(forTaskID taskID: UUID) async throws -> [TaskEvent] {
        let rows = try await database.query(
            """
            SELECT id, task_id, event_type, timestamp, metadata_json
            FROM task_events
            WHERE task_id = ?1
            ORDER BY timestamp ASC, rowid ASC
            """,
            bindings: [.text(taskID.uuidString)]
        )
        return try rows.map(Self.event(fromRow:))
    }

    func allEvents() async throws -> [TaskEvent] {
        let rows = try await database.query(
            """
            SELECT id, task_id, event_type, timestamp, metadata_json
            FROM task_events
            ORDER BY timestamp ASC, rowid ASC
            """
        )
        return try rows.map(Self.event(fromRow:))
    }

    static func event(fromRow row: [SQLiteValue]) throws -> TaskEvent {
        guard row.count >= 5,
              case .text(let idString) = row[0],
              let id = UUID(uuidString: idString),
              case .text(let taskIDString) = row[1],
              let taskID = UUID(uuidString: taskIDString),
              case .text(let typeString) = row[2],
              let type = TaskEventType(rawValue: typeString),
              case .real(let timestamp) = row[3],
              case .text(let metadataJSON) = row[4] else {
            throw DatabaseError(message: "unexpected task_events row shape")
        }
        return TaskEvent(
            taskID: taskID,
            type: type,
            timestamp: Date(timeIntervalSince1970: timestamp),
            metadata: decodeMetadata(metadataJSON),
            id: id
        )
    }

    static func encodeMetadata(_ metadata: [String: String]) -> String {
        guard !metadata.isEmpty else { return "{}" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(metadata) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decodeMetadata(_ json: String) -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(json.utf8))) ?? [:]
    }
}
