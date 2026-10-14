import Foundation

/// Domain model for a calendar event.
/// EventKit types never leave the calendar service layer.
struct CalendarEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let externalID: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String?
}
