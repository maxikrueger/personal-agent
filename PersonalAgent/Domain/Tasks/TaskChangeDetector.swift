import Foundation

/// Pure diff between the previously stored and the freshly fetched state of a
/// task. Deterministic and side-effect free so scenarios
/// can be unit-tested exactly.
///
/// Privacy: events never carry title/notes/list contents — only which
/// field changed. Due-date changes carry old/new dates because postponement
/// analytics need the deltas.
enum TaskChangeDetector {
    /// Metadata marking a due-date change caused by a recurring reminder moving
    /// on to its next occurrence (it takes effect right after the completion).
    static let nextOccurrenceReason = "nextOccurrence"

    static func events(
        previous: Task?,
        current: Task,
        now: Date,
        calendar: Calendar = .current
    ) -> [TaskEvent] {
        guard let previous else {
            // First time this task is seen; pre-existing reminders keep their
            // original creation date so age/recurrence analytics stay truthful.
            return [
                TaskEvent(
                    taskID: current.id,
                    type: .created,
                    timestamp: current.creationDate ?? now
                )
            ]
        }
        var events: [TaskEvent] = []
        let movedToNextOccurrence = isNextOccurrence(previous: previous, current: current, calendar: calendar)
        if movedToNextOccurrence,
           let oldDueDate = previous.dueDate,
           let newDueDate = current.dueDate {
            // Completing a recurring reminder keeps it open and moves its due date
            // to the next occurrence. That is a completion, not a postponement.
            // EventKit keeps no completion time for the finished occurrence, so
            // the sync time stands in for it.
            events.append(TaskEvent(taskID: current.id, type: .completed, timestamp: now))
            events.append(
                TaskEvent(
                    taskID: current.id,
                    type: .modified,
                    timestamp: now,
                    metadata: [
                        "field": "dueDate",
                        "oldDueDate": iso(oldDueDate),
                        "newDueDate": iso(newDueDate),
                        "reason": nextOccurrenceReason,
                    ]
                )
            )
        } else if !previous.isCompleted && current.isCompleted {
            events.append(
                TaskEvent(
                    taskID: current.id,
                    type: .completed,
                    timestamp: current.completionDate ?? now
                )
            )
        } else if previous.isCompleted && !current.isCompleted {
            events.append(TaskEvent(taskID: current.id, type: .reopened, timestamp: now))
        }
        if previous.dueDate != current.dueDate, !movedToNextOccurrence {
            events.append(dueDateEvent(previous: previous, current: current, now: now))
        }
        if previous.title != current.title {
            events.append(modifiedEvent(for: current, field: "title", now: now))
        }
        if previous.notes != current.notes {
            events.append(modifiedEvent(for: current, field: "notes", now: now))
        }
        if previous.listName != current.listName {
            events.append(modifiedEvent(for: current, field: "listName", now: now))
        }
        return events
    }

    /// A still-open recurring task whose due date moved forward by whole
    /// recurrence steps has been completed in Apple Reminders. A manual move by
    /// exactly one step is indistinguishable and is counted the same way.
    private static func isNextOccurrence(previous: Task, current: Task, calendar: Calendar) -> Bool {
        guard let recurrence = current.recurrence,
              !previous.isCompleted,
              !current.isCompleted,
              let oldDueDate = previous.dueDate,
              let newDueDate = current.dueDate
        else { return false }
        return recurrence.isOccurrenceAdvance(from: oldDueDate, to: newDueDate, calendar: calendar)
    }

    private static func dueDateEvent(previous: Task, current: Task, now: Date) -> TaskEvent {
        var metadata = ["field": "dueDate"]
        if let oldDueDate = previous.dueDate {
            metadata["oldDueDate"] = iso(oldDueDate)
        }
        if let newDueDate = current.dueDate {
            metadata["newDueDate"] = iso(newDueDate)
        }
        // Moving the due date of a still-open task further out is a postponement.
        if let oldDueDate = previous.dueDate,
           let newDueDate = current.dueDate,
           newDueDate > oldDueDate,
           !current.isCompleted {
            return TaskEvent(taskID: current.id, type: .postponed, timestamp: now, metadata: metadata)
        }
        return TaskEvent(taskID: current.id, type: .modified, timestamp: now, metadata: metadata)
    }

    private static func modifiedEvent(for task: Task, field: String, now: Date) -> TaskEvent {
        TaskEvent(taskID: task.id, type: .modified, timestamp: now, metadata: ["field": field])
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
