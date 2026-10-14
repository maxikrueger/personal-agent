import Foundation

/// Aggregated behavioral insights. Every number originates
/// from the deterministic analytics — never from the language model — and
/// carries its sample size so the UI can stay honest.
struct InsightsReport: Equatable, Sendable {
    let generatedAt: Date
    let openTaskCount: Int
    let completedTaskCount: Int
    let frequentlyPostponed: [PostponedInsight]
    let reliablyCompleted: [ReliableInsight]
    let bestCompletionWindows: [WindowInsight]
    let reminderEffectiveness: ReminderEffectivenessInsight?
    let recurringPatterns: [RecurringInsight]
    let outcomeTotals: RecommendationOutcomeSummary
}

struct PostponedInsight: Equatable, Sendable {
    let title: String
    let postponementCount: Int
    let procrastinationScore: Double
}

struct ReliableInsight: Equatable, Sendable {
    let title: String
    let completionRate: Double
    let completionCount: Int
    let cycleCount: Int
}

struct WindowInsight: Equatable, Sendable {
    let window: TimeWindow
    let completionCount: Int
    let share: Double
}

struct WindowEffectiveness: Equatable, Sendable {
    let window: TimeWindow
    let firedCount: Int
    let completedAfterCount: Int
    let rate: Double
}

struct ReminderEffectivenessInsight: Equatable, Sendable {
    let firedCount: Int
    let completedAfterCount: Int
    let rate: Double
    let byWindow: [WindowEffectiveness]
}

struct RecurringInsight: Equatable, Sendable {
    let title: String
    let pattern: RecurrencePattern
    let confidence: Double
    let sampleSize: Int
}
