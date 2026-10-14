import Foundation

/// Abstraction over the Apple Calendar integration.
/// `findFreeTime` returns `DateInterval`s (start + end per slot) rather than
/// plain durations, so callers know where each free slot lies.
protocol CalendarService: Sendable {
    func requestAccess() async throws
    func fetchEvents(from: Date, to: Date) async throws -> [CalendarEvent]
    func findFreeTime(from: Date, to: Date, duration: TimeInterval) async throws -> [DateInterval]
}

enum CalendarServiceError: Error, Equatable, LocalizedError {
    case accessDenied
    case accessRestricted
    case fetchFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Der Zugriff auf den Kalender wurde nicht erlaubt. Bitte erlaube ihn in den iOS-Einstellungen unter Datenschutz & Sicherheit → Kalender."
        case .accessRestricted:
            return "Der Zugriff auf den Kalender ist auf diesem Gerät eingeschränkt."
        case .fetchFailed:
            return "Die Kalendertermine konnten nicht geladen werden."
        }
    }
}
