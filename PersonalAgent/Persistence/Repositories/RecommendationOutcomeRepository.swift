import Foundation

struct RecommendationOutcomeRepository: Sendable {
    let database: SQLiteDatabase

    /// Throws on a duplicate (recommendation, type) pair — callers check the
    /// existing outcomes first; the UNIQUE constraint is the safety net.
    func insert(_ outcome: RecommendationOutcome) async throws {
        try await database.execute(
            """
            INSERT INTO recommendation_outcomes (id, recommendation_id, outcome_type, timestamp)
            VALUES (?1, ?2, ?3, ?4)
            """,
            bindings: [
                .text(outcome.id.uuidString),
                .text(outcome.recommendationID.uuidString),
                .text(outcome.outcome.rawValue),
                .real(outcome.timestamp.timeIntervalSince1970),
            ]
        )
    }

    func outcomes(forRecommendationID recommendationID: UUID) async throws -> [RecommendationOutcome] {
        let rows = try await database.query(
            """
            SELECT id, recommendation_id, outcome_type, timestamp
            FROM recommendation_outcomes
            WHERE recommendation_id = ?1
            ORDER BY timestamp ASC, rowid ASC
            """,
            bindings: [.text(recommendationID.uuidString)]
        )
        return try rows.map(Self.outcome(fromRow:))
    }

    func allOutcomes() async throws -> [RecommendationOutcome] {
        let rows = try await database.query(
            """
            SELECT id, recommendation_id, outcome_type, timestamp
            FROM recommendation_outcomes
            ORDER BY timestamp ASC, rowid ASC
            """
        )
        return try rows.map(Self.outcome(fromRow:))
    }

    static func outcome(fromRow row: [SQLiteValue]) throws -> RecommendationOutcome {
        guard row.count >= 4,
              case .text(let idString) = row[0],
              let id = UUID(uuidString: idString),
              case .text(let recommendationIDString) = row[1],
              let recommendationID = UUID(uuidString: recommendationIDString),
              case .text(let typeString) = row[2],
              let type = OutcomeType(rawValue: typeString),
              case .real(let timestamp) = row[3] else {
            throw DatabaseError(message: "unexpected recommendation_outcomes row shape")
        }
        return RecommendationOutcome(
            recommendationID: recommendationID,
            outcome: type,
            timestamp: Date(timeIntervalSince1970: timestamp),
            id: id
        )
    }
}
