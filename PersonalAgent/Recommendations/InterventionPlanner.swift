import Foundation

/// "Determine whether intervention is useful": ranks open tasks by how
/// much they need a reminder right now. Deterministic; the threshold keeps
/// calm tasks from triggering interventions.
struct InterventionCandidate: Equatable, Sendable {
    let task: Task
    let analysis: TaskAnalysis
    let priority: Double
}

enum InterventionPlanner {
    static let interventionThreshold = 0.35
    static let procrastinationWeight = 0.6
    static let urgencyWeight = 0.4

    static func priority(
        task: Task,
        analysis: TaskAnalysis,
        now: Date,
        urgencyHorizon: TimeInterval
    ) -> Double {
        let urgency = RecommendationEngine.deadlineUrgency(
            dueDate: task.dueDate,
            isOverdue: analysis.isCurrentlyOverdue,
            now: now,
            horizon: urgencyHorizon
        )
        return procrastinationWeight * analysis.statistics.procrastinationScore
            + urgencyWeight * urgency
    }

    /// Sorted by priority descending, ties broken by title for determinism.
    static func rank(
        _ tasks: [(task: Task, analysis: TaskAnalysis)],
        now: Date,
        urgencyHorizon: TimeInterval
    ) -> [InterventionCandidate] {
        tasks
            .map { entry in
                InterventionCandidate(
                    task: entry.task,
                    analysis: entry.analysis,
                    priority: priority(
                        task: entry.task,
                        analysis: entry.analysis,
                        now: now,
                        urgencyHorizon: urgencyHorizon
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.task.title.localizedCompare(rhs.task.title) == .orderedAscending
            }
    }
}
