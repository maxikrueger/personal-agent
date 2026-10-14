import Foundation

/// Pure aggregation of per-task analytics into the insights. Deterministic:
/// same inputs always produce the same report, with fixed sort orders and caps.
enum InsightsAggregator {
    static let maxListedTasks = 5
    static let minPostponements = 2
    static let reliableCompletionRate = 0.8
    static let minCompletionsForReliability = 3
    static let minCompletionsForWindows = 3

    static func report(
        taskData: [(task: Task, events: [TaskEvent])],
        outcomes: [RecommendationOutcome],
        now: Date,
        calendar: Calendar
    ) -> InsightsReport {
        struct Analyzed {
            let task: Task
            let analysis: TaskAnalysis
            let effectiveness: ReminderEffectiveness
            let completions: [Date]
        }
        let analyzed = taskData.map { entry in
            Analyzed(
                task: entry.task,
                analysis: TaskAnalyticsEngine.analyze(
                    task: entry.task, events: entry.events, now: now, calendar: calendar
                ),
                effectiveness: ReminderEffectivenessAnalyzer.analyze(events: entry.events, now: now),
                completions: CompletionAnalyzer.analyze(
                    task: entry.task, events: entry.events, now: now
                ).completionDates
            )
        }

        let openTaskCount = taskData.filter { !$0.task.isCompleted }.count

        // "Tasks frequently postponed" — open tasks only ("aktuell").
        let frequentlyPostponed = analyzed
            .filter {
                !$0.task.isCompleted
                    && $0.analysis.statistics.postponementCount >= minPostponements
            }
            .sorted { lhs, rhs in
                if lhs.analysis.statistics.postponementCount != rhs.analysis.statistics.postponementCount {
                    return lhs.analysis.statistics.postponementCount > rhs.analysis.statistics.postponementCount
                }
                if lhs.analysis.statistics.procrastinationScore != rhs.analysis.statistics.procrastinationScore {
                    return lhs.analysis.statistics.procrastinationScore > rhs.analysis.statistics.procrastinationScore
                }
                return lhs.task.title.localizedCompare(rhs.task.title) == .orderedAscending
            }
            .prefix(maxListedTasks)
            .map {
                PostponedInsight(
                    title: $0.task.title,
                    postponementCount: $0.analysis.statistics.postponementCount,
                    procrastinationScore: $0.analysis.statistics.procrastinationScore
                )
            }

        // "Tasks usually completed successfully" — needs a real sample.
        let reliablyCompleted = analyzed
            .filter {
                $0.analysis.completionCount >= minCompletionsForReliability
                    && $0.analysis.statistics.completionRate >= reliableCompletionRate
            }
            .sorted { lhs, rhs in
                if lhs.analysis.statistics.completionRate != rhs.analysis.statistics.completionRate {
                    return lhs.analysis.statistics.completionRate > rhs.analysis.statistics.completionRate
                }
                if lhs.analysis.completionCount != rhs.analysis.completionCount {
                    return lhs.analysis.completionCount > rhs.analysis.completionCount
                }
                return lhs.task.title.localizedCompare(rhs.task.title) == .orderedAscending
            }
            .prefix(maxListedTasks)
            .map {
                ReliableInsight(
                    title: $0.task.title,
                    completionRate: $0.analysis.statistics.completionRate,
                    completionCount: $0.analysis.completionCount,
                    cycleCount: $0.analysis.cycleCount
                )
            }

        // "Best completion times" — all completions across all tasks.
        let allCompletions = analyzed.flatMap(\.completions)
        var bestCompletionWindows: [WindowInsight] = []
        if allCompletions.count >= minCompletionsForWindows {
            var counts: [TimeWindow: Int] = [:]
            for date in allCompletions {
                let window = TimeWindow.window(forHour: calendar.component(.hour, from: date))
                counts[window, default: 0] += 1
            }
            bestCompletionWindows = TimeWindow.allWindows
                .compactMap { window -> WindowInsight? in
                    guard let count = counts[window], count > 0 else { return nil }
                    return WindowInsight(
                        window: window,
                        completionCount: count,
                        share: Double(count) / Double(allCompletions.count)
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.completionCount != rhs.completionCount {
                        return lhs.completionCount > rhs.completionCount
                    }
                    return windowIndex(lhs.window) < windowIndex(rhs.window)
                }
        }

        // "Reminder effectiveness" incl. the by-window comparison
        // ("Erinnerungen um 18:00 wirken besser als am Morgen").
        let allFired = analyzed.flatMap { $0.effectiveness.firedReminders }
        var reminderEffectiveness: ReminderEffectivenessInsight?
        if !allFired.isEmpty {
            let completedAfter = allFired.filter(\.completedWithinWindow).count
            let byWindow = TimeWindow.allWindows.compactMap { window -> WindowEffectiveness? in
                let inWindow = allFired.filter {
                    TimeWindow.window(forHour: calendar.component(.hour, from: $0.fireDate)) == window
                }
                guard !inWindow.isEmpty else { return nil }
                let completed = inWindow.filter(\.completedWithinWindow).count
                return WindowEffectiveness(
                    window: window,
                    firedCount: inWindow.count,
                    completedAfterCount: completed,
                    rate: Double(completed) / Double(inWindow.count)
                )
            }
            reminderEffectiveness = ReminderEffectivenessInsight(
                firedCount: allFired.count,
                completedAfterCount: completedAfter,
                rate: Double(completedAfter) / Double(allFired.count),
                byWindow: byWindow
            )
        }

        // "Recurring patterns" — the analyzer only claims patterns at
        // confidence ≥ 0.5, so everything listed is presentable.
        let recurringPatterns = analyzed
            .compactMap { entry -> RecurringInsight? in
                guard let pattern = entry.analysis.recurrence.pattern else { return nil }
                return RecurringInsight(
                    title: entry.task.title,
                    pattern: pattern,
                    confidence: entry.analysis.recurrence.confidence,
                    sampleSize: entry.analysis.recurrence.sampleSize
                )
            }
            .sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
            .prefix(maxListedTasks)

        return InsightsReport(
            generatedAt: now,
            openTaskCount: openTaskCount,
            completedTaskCount: taskData.count - openTaskCount,
            frequentlyPostponed: Array(frequentlyPostponed),
            reliablyCompleted: Array(reliablyCompleted),
            bestCompletionWindows: bestCompletionWindows,
            reminderEffectiveness: reminderEffectiveness,
            recurringPatterns: Array(recurringPatterns),
            outcomeTotals: RecommendationEvaluator.summary(from: outcomes)
        )
    }

    private static func windowIndex(_ window: TimeWindow) -> Int {
        TimeWindow.allWindows.firstIndex(of: window) ?? 0
    }
}
