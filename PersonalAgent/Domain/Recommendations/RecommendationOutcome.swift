import Foundation

/// How the user (or reality) responded to a recommendation.
/// Raw values are persisted as snake_case codes.
enum OutcomeType: String, CaseIterable, Equatable, Sendable {
    case accepted
    case rejected
    case ignored
    case snoozed
    case completed
    case notCompleted = "not_completed"
}

/// — one recorded outcome for one stored recommendation.
struct RecommendationOutcome: Identifiable, Equatable, Sendable {
    let id: UUID
    let recommendationID: UUID
    let outcome: OutcomeType
    let timestamp: Date

    init(recommendationID: UUID, outcome: OutcomeType, timestamp: Date, id: UUID = UUID()) {
        self.id = id
        self.recommendationID = recommendationID
        self.outcome = outcome
        self.timestamp = timestamp
    }
}

/// Per-task aggregation of outcomes across all its recommendations,
/// produced by `RecommendationEvaluator` and fed back into confidence.
struct RecommendationOutcomeSummary: Equatable, Sendable {
    var accepted = 0
    var rejected = 0
    var ignored = 0
    var snoozed = 0
    var completed = 0
    var notCompleted = 0

    var total: Int {
        accepted + rejected + ignored + snoozed + completed + notCompleted
    }

    static let empty = RecommendationOutcomeSummary()
}
