import Foundation

/// Compact task representation handed to the language model.
struct TaskSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let dueDate: Date?
    let isOverdue: Bool

    init(id: UUID, title: String, dueDate: Date?, isOverdue: Bool) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isOverdue = isOverdue
    }

    init(task: Task, now: Date) {
        self.init(
            id: task.id,
            title: task.title,
            dueDate: task.dueDate,
            isOverdue: !task.isCompleted && (task.dueDate.map { $0 < now } ?? false)
        )
    }
}
