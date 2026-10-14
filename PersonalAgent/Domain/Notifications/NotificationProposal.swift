import Foundation

/// A notification the model proposed but that is NOT scheduled yet — only an
/// explicit user confirmation in the app turns it into an iOS notification.
struct NotificationProposal: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Set when the reminder is bound to a known task (enables history events).
    let taskID: UUID?
    let notificationID: String
    let notificationTitle: String
    let body: String
    let fireDate: Date
}
