import Foundation

struct CompletionAnalysis: Equatable, Sendable {
    let completionCount: Int
    /// Open periods: every completion is one cycle; a currently open task adds one.
    let cycleCount: Int
    let completionRate: Double
    /// Timestamps of all completions, sorted ascending.
    let completionDates: [Date]
    /// Signed lateness vs. the due date in effect at completion time
    /// (negative = early); only completions that had a due date contribute.
    let delays: [TimeInterval]
    let averageDelay: TimeInterval?
    let medianDelay: TimeInterval?
    let isCurrentlyOverdue: Bool
    /// Start of the current open period (creation or last reopening); nil when completed.
    let currentOpenSince: Date?
}

enum CompletionAnalyzer {
    static func analyze(task: Task, events: [TaskEvent], now: Date) -> CompletionAnalysis {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var completionDates = sorted.filter { $0.type == .completed }.map(\.timestamp)
        // A reminder imported already-completed has no completed event yet —
        // its completion date still counts as one completion.
        if completionDates.isEmpty, task.isCompleted, let completionDate = task.completionDate {
            completionDates = [completionDate]
        }
        completionDates.sort()

        let completionCount = completionDates.count
        let cycleCount = completionCount + (task.isCompleted ? 0 : 1)
        let completionRate = cycleCount > 0 ? Double(completionCount) / Double(cycleCount) : 0

        let dueDateHistory = DueDateHistory(currentDueDate: task.dueDate, events: sorted)
        let delays = completionDates.compactMap { completion -> TimeInterval? in
            guard let dueDate = dueDateHistory.dueDate(at: completion) else { return nil }
            return completion.timeIntervalSince(dueDate)
        }

        let isCurrentlyOverdue = !task.isCompleted && task.dueDate.map { $0 < now } == true

        let currentOpenSince: Date?
        if task.isCompleted {
            currentOpenSince = nil
        } else if let lastReopened = sorted.last(where: { $0.type == .reopened })?.timestamp {
            currentOpenSince = lastReopened
        } else {
            currentOpenSince = task.creationDate
        }

        return CompletionAnalysis(
            completionCount: completionCount,
            cycleCount: cycleCount,
            completionRate: completionRate,
            completionDates: completionDates,
            delays: delays,
            averageDelay: average(of: delays),
            medianDelay: median(of: delays),
            isCurrentlyOverdue: isCurrentlyOverdue,
            currentOpenSince: currentOpenSince
        )
    }

    static func average(of values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func median(of values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
