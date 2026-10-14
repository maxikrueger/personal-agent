import Foundation

/// Materializes derivable outcomes after each sync: completions are
/// attributed to recommendations, unanswered recommendations become `ignored`,
/// accepted-but-unfinished ones become `not_completed`. Idempotent — at most
/// one outcome per (recommendation, type), enforced here and by the schema.
struct OutcomeSweeper: Sendable {
    let database: SQLiteDatabase

    /// A completion within this window after the recommendation counts as its outcome.
    static let completionWindow: TimeInterval = 7 * 86_400
    /// Grace period after the recommended time before ignored/not_completed verdicts.
    static let responseGrace: TimeInterval = 24 * 3600

    /// Returns the number of outcomes recorded.
    @discardableResult
    func sweep(now: Date) async throws -> Int {
        let recommendationRepository = RecommendationRepository(database: database)
        let outcomeRepository = RecommendationOutcomeRepository(database: database)
        let eventRepository = TaskEventRepository(database: database)

        var recorded = 0
        var completionsByTask: [UUID: [Date]] = [:]
        for recommendation in try await recommendationRepository.allRecommendations() {
            if completionsByTask[recommendation.taskID] == nil {
                let events = try await eventRepository.events(forTaskID: recommendation.taskID)
                completionsByTask[recommendation.taskID] = events
                    .filter { $0.type == .completed }
                    .map(\.timestamp)
                    .sorted()
            }
            let existing = Set(
                try await outcomeRepository.outcomes(forRecommendationID: recommendation.id)
                    .map(\.outcome)
            )
            let newOutcomes = Self.outcomesToRecord(
                recommendation: recommendation,
                existingTypes: existing,
                completionDates: completionsByTask[recommendation.taskID] ?? [],
                now: now
            )
            for outcome in newOutcomes {
                try await outcomeRepository.insert(outcome)
                recorded += 1
            }
        }
        return recorded
    }

    /// Pure decision core (unit-tested exactly):
    /// - `completed` when the task was completed within 7 days of the
    ///   recommendation (timestamped with the completion).
    /// - after the 24 h grace past the recommended time:
    ///   `not_completed` for accepted-but-unfinished recommendations,
    ///   `ignored` for recommendations with no reaction and no completion.
    static func outcomesToRecord(
        recommendation: StoredRecommendation,
        existingTypes: Set<OutcomeType>,
        completionDates: [Date],
        now: Date
    ) -> [RecommendationOutcome] {
        var newOutcomes: [RecommendationOutcome] = []

        let completionAfter = completionDates.first {
            $0 >= recommendation.createdAt
                && $0 <= recommendation.createdAt.addingTimeInterval(completionWindow)
        }
        if !existingTypes.contains(.completed), let completionAfter {
            newOutcomes.append(
                RecommendationOutcome(
                    recommendationID: recommendation.id,
                    outcome: .completed,
                    timestamp: completionAfter
                )
            )
        }
        let hasCompleted = existingTypes.contains(.completed) || completionAfter != nil

        let verdictTime = recommendation.recommendedTime.addingTimeInterval(responseGrace)
        guard now >= verdictTime else { return newOutcomes }

        if existingTypes.contains(.accepted) {
            if !hasCompleted, !existingTypes.contains(.notCompleted) {
                newOutcomes.append(
                    RecommendationOutcome(
                        recommendationID: recommendation.id,
                        outcome: .notCompleted,
                        timestamp: now
                    )
                )
            }
        } else if !existingTypes.contains(.rejected),
                  !existingTypes.contains(.ignored),
                  !hasCompleted {
            newOutcomes.append(
                RecommendationOutcome(
                    recommendationID: recommendation.id,
                    outcome: .ignored,
                    timestamp: now
                )
            )
        }
        return newOutcomes
    }
}
