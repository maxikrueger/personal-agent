import Foundation

/// Orchestrates the deterministic analyzers into one per-task analysis.
/// Pure: same inputs always give the same result.
enum TaskAnalyticsEngine {
    static func analyze(
        task: Task,
        events: [TaskEvent],
        now: Date,
        calendar: Calendar = .current,
        weights: ProcrastinationWeights = .standard
    ) -> TaskAnalysis {
        let completion = CompletionAnalyzer.analyze(task: task, events: events, now: now)
        let postponement = PostponementAnalyzer.analyze(
            events: events,
            completionCount: completion.completionCount
        )
        let recurrence = RecurrenceAnalyzer.analyze(
            completionDates: completion.completionDates,
            calendar: calendar
        )
        let preferredWindow = TimeWindowAnalyzer.analyze(
            completionDates: completion.completionDates,
            calendar: calendar
        )

        let lateCompletions = completion.delays.filter { $0 > 0 }.count
        let overdueCount = lateCompletions + (completion.isCurrentlyOverdue ? 1 : 0)
        let overdueRate = completion.cycleCount > 0
            ? min(1, Double(overdueCount) / Double(completion.cycleCount))
            : 0

        let openAge = completion.currentOpenSince.map { now.timeIntervalSince($0) }
        let procrastinationScore = ProcrastinationScorer.score(
            ProcrastinationInputs(
                postponementRate: postponement.postponementRate,
                overdueRate: overdueRate,
                averageDelay: completion.averageDelay,
                openAge: openAge,
                consecutivePostponements: postponement.consecutivePostponements
            ),
            weights: weights
        )

        let statistics = TaskStatistics(
            completionRate: completion.completionRate,
            postponementCount: postponement.postponementCount,
            postponementRate: postponement.postponementRate,
            overdueCount: overdueCount,
            averageDelay: completion.averageDelay,
            medianDelay: completion.medianDelay,
            recurrenceConfidence: recurrence.confidence,
            preferredCompletionWindow: preferredWindow.window,
            procrastinationScore: procrastinationScore
        )

        return TaskAnalysis(
            taskID: task.id,
            statistics: statistics,
            cycleCount: completion.cycleCount,
            completionCount: completion.completionCount,
            consecutivePostponements: postponement.consecutivePostponements,
            averagePostponementDelay: postponement.averagePostponementDelay,
            recurrence: recurrence,
            preferredWindow: preferredWindow,
            isCurrentlyOverdue: completion.isCurrentlyOverdue
        )
    }
}
