import Foundation

/// Abstraction over the Apple Reminders integration.
/// The rest of the app never sees EventKit types.
protocol ReminderService: Sendable {
    func requestAccess() async throws
    /// True only when full read access is already granted — never prompts.
    func hasFullAccess() async -> Bool
    func fetchOpenTasks() async throws -> [Task]
    /// All reminders including completed ones — required by sync to distinguish
    /// "completed in Apple Reminders" from "deleted".
    func fetchAllTasks() async throws -> [Task]
    /// Creates a reminder in Apple Reminders. Only ever called from the
    /// app-level confirmation gate, never directly from a tool.
    func createReminder(title: String, notes: String?, dueDate: Date?) async throws -> Task
}

enum ReminderServiceError: Error, Equatable, LocalizedError {
    case accessDenied
    case accessRestricted
    case fetchFailed
    case creationFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Der Zugriff auf Erinnerungen wurde nicht erlaubt. Bitte erlaube ihn in den iOS-Einstellungen unter Datenschutz & Sicherheit → Erinnerungen."
        case .accessRestricted:
            return "Der Zugriff auf Erinnerungen ist auf diesem Gerät eingeschränkt."
        case .fetchFailed:
            return "Die Erinnerungen konnten nicht geladen werden."
        case .creationFailed:
            return "Die Aufgabe konnte nicht in Apple Erinnerungen angelegt werden."
        }
    }
}
