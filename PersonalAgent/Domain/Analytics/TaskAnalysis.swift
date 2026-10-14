import Foundation

/// Full analysis result: the core statistics plus the sample
/// sizes and secondary values needed to present them honestly and to
/// build recommendations later.
struct TaskAnalysis: Equatable, Sendable {
    let taskID: UUID
    let statistics: TaskStatistics
    let cycleCount: Int
    let completionCount: Int
    let consecutivePostponements: Int
    let averagePostponementDelay: TimeInterval?
    let recurrence: RecurrenceAnalysis
    let preferredWindow: PreferredWindowAnalysis
    let isCurrentlyOverdue: Bool
}

struct RecurrenceAnalysis: Equatable, Sendable {
    let pattern: RecurrencePattern?
    let confidence: Double
    let sampleSize: Int
}

struct PreferredWindowAnalysis: Equatable, Sendable {
    let window: TimeWindow?
    let confidence: Double
    let sampleSize: Int
}
