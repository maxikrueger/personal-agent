import Foundation

struct RecommendationRepository: Sendable {
    let database: SQLiteDatabase

    func insert(_ recommendation: StoredRecommendation) async throws {
        try await database.execute(
            """
            INSERT INTO recommendations (
                id, task_id, recommended_time, confidence, reason_codes_json, created_at
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            """,
            bindings: [
                .text(recommendation.id.uuidString),
                .text(recommendation.taskID.uuidString),
                .real(recommendation.recommendedTime.timeIntervalSince1970),
                .real(recommendation.confidence),
                .text(Self.encodeReasonCodes(recommendation.reasonCodes)),
                .real(recommendation.createdAt.timeIntervalSince1970),
            ]
        )
    }

    func recommendations(forTaskID taskID: UUID) async throws -> [StoredRecommendation] {
        let rows = try await database.query(
            """
            SELECT id, task_id, recommended_time, confidence, reason_codes_json, created_at
            FROM recommendations
            WHERE task_id = ?1
            ORDER BY created_at DESC, rowid DESC
            """,
            bindings: [.text(taskID.uuidString)]
        )
        return try rows.map(Self.recommendation(fromRow:))
    }

    func allRecommendations() async throws -> [StoredRecommendation] {
        let rows = try await database.query(
            """
            SELECT id, task_id, recommended_time, confidence, reason_codes_json, created_at
            FROM recommendations
            ORDER BY created_at ASC, rowid ASC
            """
        )
        return try rows.map(Self.recommendation(fromRow:))
    }

    /// Most recent recommendation for a task created at or after `since`.
    func latest(forTaskID taskID: UUID, since: Date) async throws -> StoredRecommendation? {
        let rows = try await database.query(
            """
            SELECT id, task_id, recommended_time, confidence, reason_codes_json, created_at
            FROM recommendations
            WHERE task_id = ?1 AND created_at >= ?2
            ORDER BY created_at DESC, rowid DESC
            LIMIT 1
            """,
            bindings: [.text(taskID.uuidString), .real(since.timeIntervalSince1970)]
        )
        return try rows.first.map(Self.recommendation(fromRow:))
    }

    static func recommendation(fromRow row: [SQLiteValue]) throws -> StoredRecommendation {
        guard row.count >= 6,
              case .text(let idString) = row[0],
              let id = UUID(uuidString: idString),
              case .text(let taskIDString) = row[1],
              let taskID = UUID(uuidString: taskIDString),
              case .real(let recommendedTime) = row[2],
              case .real(let confidence) = row[3],
              case .text(let reasonCodesJSON) = row[4],
              case .real(let createdAt) = row[5] else {
            throw DatabaseError(message: "unexpected recommendations row shape")
        }
        return StoredRecommendation(
            id: id,
            taskID: taskID,
            recommendedTime: Date(timeIntervalSince1970: recommendedTime),
            confidence: confidence,
            reasonCodes: decodeReasonCodes(reasonCodesJSON),
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    static func encodeReasonCodes(_ codes: [RecommendationReason]) -> String {
        guard let data = try? JSONEncoder().encode(codes.map(\.rawValue)) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decodeReasonCodes(_ json: String) -> [RecommendationReason] {
        let raw = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
        return raw.compactMap(RecommendationReason.init(rawValue:))
    }
}
