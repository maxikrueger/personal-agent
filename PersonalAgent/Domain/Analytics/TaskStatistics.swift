import Foundation

/// Deterministic per-task behavioral statistics.
/// Computed exclusively by the analytics engine — never by the language model.
struct TaskStatistics: Equatable, Sendable {
    let completionRate: Double
    let postponementCount: Int
    let postponementRate: Double
    let overdueCount: Int
    let averageDelay: TimeInterval?
    let medianDelay: TimeInterval?
    let recurrenceConfidence: Double
    let preferredCompletionWindow: TimeWindow?
    let procrastinationScore: Double
}
