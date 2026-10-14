import Foundation

/// Historical task events — the foundation of the
/// personalization system. New cases may be added, but never rename
/// existing ones: the raw values are persisted.
enum TaskEventType: String, CaseIterable, Sendable {
    case created
    case modified
    case completed
    case reopened
    case postponed
    case overdue
    case reminderScheduled
    case reminderDelivered
    case reminderDismissed
    case reminderSnoozed
    case recommendationAccepted
    case recommendationRejected
}

struct TaskEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let type: TaskEventType
    let timestamp: Date
    let metadata: [String: String]

    init(
        taskID: UUID,
        type: TaskEventType,
        timestamp: Date,
        metadata: [String: String] = [:],
        id: UUID = UUID()
    ) {
        self.id = id
        self.taskID = taskID
        self.type = type
        self.timestamp = timestamp
        self.metadata = metadata
    }
}
