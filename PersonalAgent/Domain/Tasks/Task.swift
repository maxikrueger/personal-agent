import Foundation

/// Domain model for a to-do item.
/// Shadows Swift Concurrency's `Task` inside this module — write `_Concurrency.Task`
/// when spawning concurrency tasks in files that can see this type.
struct Task: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let externalID: String
    let title: String
    let notes: String?
    let dueDate: Date?
    let creationDate: Date?
    let completionDate: Date?
    let isCompleted: Bool
    let listName: String?
    /// Repeat rule from EventKit. Not persisted: it is only needed at sync time
    /// to classify due-date changes, and EventKit always delivers it fresh.
    var recurrence: TaskRecurrence? = nil
}

extension Task {
    /// The persisted ID stays authoritative once a task is known (sync resolves
    /// freshly mapped tasks onto their stored identity).
    func replacingID(_ newID: UUID) -> Task {
        Task(
            id: newID,
            externalID: externalID,
            title: title,
            notes: notes,
            dueDate: dueDate,
            creationDate: creationDate,
            completionDate: completionDate,
            isCompleted: isCompleted,
            listName: listName,
            recurrence: recurrence
        )
    }

    /// The task as it is stored: the database does not keep the repeat rule,
    /// so comparisons against stored state must ignore it.
    var withoutRecurrence: Task {
        var copy = self
        copy.recurrence = nil
        return copy
    }
}
