import Foundation

/// Abstraction over local notifications.
/// UserNotifications types never leave this service layer.
protocol NotificationService: Sendable {
    func requestAccess() async throws
    func schedule(id: String, title: String, body: String, date: Date) async throws
    func cancel(id: String)
}

enum NotificationServiceError: Error, Equatable, LocalizedError {
    case accessDenied
    case schedulingFailed(details: String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Mitteilungen sind nicht erlaubt. Bitte erlaube sie in den iOS-Einstellungen unter Mitteilungen → PersonalAgent."
        case .schedulingFailed(let details):
            return "Die Mitteilung konnte nicht geplant werden: \(details)"
        }
    }
}
