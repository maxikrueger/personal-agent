import Foundation

/// Deterministic recommendation core: combines
/// urgency, deadline fit, procrastination, preferred completion window, and
/// calendar availability into ranked candidate times. The LLM never invents
/// or alters scores; it only verbalizes the result.
enum RecommendationEngine {
    static func recommendation(
        for task: Task,
        analysis: TaskAnalysis,
        freeSlots: [DateInterval],
        now: Date,
        calendar: Calendar = .current,
        config: RecommendationConfig = .standard,
        outcomeSummary: RecommendationOutcomeSummary = .empty
    ) -> RankedRecommendation? {
        let candidateTimes = ReminderTimingEngine.candidateTimes(
            freeSlots: freeSlots,
            preferredWindow: analysis.preferredWindow.window,
            taskDuration: config.taskDuration,
            calendar: calendar
        ).filter { $0 >= now }
        guard !candidateTimes.isEmpty else { return nil }

        let scored = candidateTimes
            .map { candidate in
                ScoredCandidate(
                    time: candidate,
                    score: score(
                        candidate: candidate,
                        task: task,
                        analysis: analysis,
                        now: now,
                        calendar: calendar,
                        config: config
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.time < rhs.time
            }

        let best = scored[0]
        let recommendation = ReminderRecommendation(
            taskID: task.id,
            recommendedTime: best.time,
            confidence: confidence(for: analysis, task: task, outcomeSummary: outcomeSummary),
            reasonCodes: reasonCodes(
                for: best.time,
                task: task,
                analysis: analysis,
                now: now,
                calendar: calendar
            )
        )
        return RankedRecommendation(recommendation: recommendation, score: best.score, candidates: scored)
    }

    // MARK: - Scoring components (each 0…1, individually tested)

    static func score(
        candidate: Date,
        task: Task,
        analysis: TaskAnalysis,
        now: Date,
        calendar: Calendar,
        config: RecommendationConfig
    ) -> Double {
        let weights = config.weights
        let raw = weights.urgency * deadlineUrgency(
            dueDate: task.dueDate,
            isOverdue: analysis.isCurrentlyOverdue,
            now: now,
            horizon: config.urgencyHorizon
        )
            + weights.preferredWindow * windowMatch(
                candidate: candidate,
                window: analysis.preferredWindow,
                calendar: calendar
            )
            + weights.procrastination * analysis.statistics.procrastinationScore
            + weights.deadlineFit * deadlineFit(
                candidate: candidate,
                taskDuration: config.taskDuration,
                dueDate: task.dueDate
            )
            + weights.earliness * earliness(
                candidate: candidate,
                now: now,
                horizon: config.searchHorizon
            )
        return min(1, max(0, raw))
    }

    /// Overdue → 1; no due date → neutral 0.3; otherwise linear from 1 (due
    /// now) down to 0 (due at the urgency horizon).
    static func deadlineUrgency(
        dueDate: Date?,
        isOverdue: Bool,
        now: Date,
        horizon: TimeInterval
    ) -> Double {
        if isOverdue {
            return 1
        }
        guard let dueDate else {
            return 0.3
        }
        let remaining = max(0, dueDate.timeIntervalSince(now))
        return max(0, 1 - remaining / horizon)
    }

    /// Symmetric around a 0.5 neutral: inside the preferred window the match
    /// rises with the window's confidence, outside it falls with it.
    static func windowMatch(
        candidate: Date,
        window: PreferredWindowAnalysis,
        calendar: Calendar
    ) -> Double {
        guard let timeWindow = window.window else {
            return 0.5
        }
        let hour = calendar.component(.hour, from: candidate)
        let isInWindow = hour >= timeWindow.startHour && hour < timeWindow.endHour
        return isInWindow ? 0.5 + 0.5 * window.confidence : 0.5 - 0.5 * window.confidence
    }

    /// 1 when the task fits before its due date, 0 when it would end after it,
    /// neutral 0.5 without a due date.
    static func deadlineFit(candidate: Date, taskDuration: TimeInterval, dueDate: Date?) -> Double {
        guard let dueDate else {
            return 0.5
        }
        return candidate.addingTimeInterval(taskDuration) <= dueDate ? 1 : 0
    }

    /// Sooner candidates win ties: 1 at `now`, 0 at the search horizon.
    static func earliness(candidate: Date, now: Date, horizon: TimeInterval) -> Double {
        guard horizon > 0 else {
            return 0
        }
        return max(0, 1 - candidate.timeIntervalSince(now) / horizon)
    }

    /// How much data backs this recommendation: 0.3 base, up to
    /// +0.4 for a well-sampled preferred window, +0.2 for a due date,
    /// +0.1 for task history — shifted by up to ±0.1 from recorded
    /// recommendation outcomes (the loop feeds back).
    static func confidence(
        for analysis: TaskAnalysis,
        task: Task,
        outcomeSummary: RecommendationOutcomeSummary = .empty
    ) -> Double {
        let windowPart = analysis.preferredWindow.confidence
            * min(1, Double(analysis.preferredWindow.sampleSize) / 6.0)
        let duePart = task.dueDate != nil ? 1.0 : 0.0
        let historyPart = min(1, Double(analysis.cycleCount) / 4.0)
        let base = 0.3 + 0.4 * windowPart + 0.2 * duePart + 0.1 * historyPart
        let adjusted = base + RecommendationEvaluator.confidenceAdjustment(for: outcomeSummary)
        return min(1, max(0.05, adjusted))
    }

    /// Fixed emission order keeps outputs deterministic.
    static func reasonCodes(
        for chosenTime: Date,
        task: Task,
        analysis: TaskAnalysis,
        now: Date,
        calendar: Calendar
    ) -> [RecommendationReason] {
        var reasons: [RecommendationReason] = []
        if analysis.isCurrentlyOverdue {
            reasons.append(.overdue)
        }
        if !analysis.isCurrentlyOverdue,
           let dueDate = task.dueDate,
           dueDate.timeIntervalSince(now) <= 3 * 86_400 {
            reasons.append(.deadlineApproaching)
        }
        if analysis.statistics.postponementCount >= 2, analysis.statistics.postponementRate >= 0.5 {
            reasons.append(.frequentlyPostponed)
        }
        if analysis.recurrence.pattern != nil {
            reasons.append(.recurringPattern)
        }
        if let window = analysis.preferredWindow.window,
           analysis.preferredWindow.confidence >= 0.5 {
            let hour = calendar.component(.hour, from: chosenTime)
            if hour >= window.startHour && hour < window.endHour {
                reasons.append(.historicallySuccessfulTime)
            }
        }
        // Candidates only ever come from free calendar slots.
        reasons.append(.currentlyFree)
        return reasons
    }
}
