import Foundation

/// Machine-readable reasons behind a recommendation.
/// Raw values are stable snake_case codes; the LLM turns them into language.
enum RecommendationReason: String, Equatable, CaseIterable, Sendable {
    case frequentlyPostponed = "frequently_postponed"
    case deadlineApproaching = "deadline_approaching"
    case historicallySuccessfulTime = "historically_successful_time"
    case currentlyFree = "currently_free"
    case overdue
    case recurringPattern = "recurring_pattern"
}

/// Deterministic reminder recommendation.
struct ReminderRecommendation: Equatable, Sendable {
    let taskID: UUID
    let recommendedTime: Date
    let confidence: Double
    let reasonCodes: [RecommendationReason]
}

struct ScoredCandidate: Equatable, Sendable {
    let time: Date
    let score: Double
}

/// Engine result: the recommendation plus its score and the full ranked
/// candidate list (for tests, and later for Insights/adaptive phases).
struct RankedRecommendation: Equatable, Sendable {
    let recommendation: ReminderRecommendation
    let score: Double
    let candidates: [ScoredCandidate]
}
