import Foundation

/// A reminder the model proposed to create in Apple Reminders — nothing exists
/// until the user confirms it in the app (create reminder →
/// confirmation).
struct ReminderCreationProposal: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let notes: String?
    let dueDate: Date?
}
