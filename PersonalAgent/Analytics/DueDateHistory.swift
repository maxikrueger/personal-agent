import Foundation

/// Reconstructs which due date was in effect at any point in time from the
/// recorded due-date-change events (postponed/modified with field=dueDate)
/// plus the task's current due date. Needed so completion delays are measured
/// against the due date that actually applied at completion time.
struct DueDateHistory: Sendable {
    private struct Change {
        let timestamp: Date
        let oldDueDate: Date?
        let newDueDate: Date?
        /// A recurring task moving on to its next occurrence is recorded at the
        /// same instant as the completion it follows; the completion still
        /// belongs to the old due date, so this change applies only afterwards.
        let appliesAfterTimestamp: Bool
    }

    private let changes: [Change]
    private let currentDueDate: Date?

    init(currentDueDate: Date?, events: [TaskEvent]) {
        self.currentDueDate = currentDueDate
        self.changes = events
            .filter { event in
                event.type == .postponed
                    || (event.type == .modified && event.metadata["field"] == "dueDate")
            }
            .sorted { $0.timestamp < $1.timestamp }
            .map { event in
                Change(
                    timestamp: event.timestamp,
                    oldDueDate: Self.parse(event.metadata["oldDueDate"]),
                    newDueDate: Self.parse(event.metadata["newDueDate"]),
                    appliesAfterTimestamp: event.metadata["reason"] == TaskChangeDetector.nextOccurrenceReason
                )
            }
    }

    func dueDate(at date: Date) -> Date? {
        let lastChangeBefore = changes.last { change in
            change.timestamp < date || (change.timestamp == date && !change.appliesAfterTimestamp)
        }
        if let lastChangeBefore {
            return lastChangeBefore.newDueDate
        }
        if let firstChange = changes.first {
            return firstChange.oldDueDate
        }
        return currentDueDate
    }

    private static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return try? Date(iso, strategy: Date.ISO8601FormatStyle())
    }
}
