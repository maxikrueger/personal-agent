import EventKit
import Foundation

/// Pure mapping from EventKit events to domain models; unit-testable without
/// permissions (in-memory EKEvent objects only).
enum CalendarEventMapper {
    static func calendarEvent(from event: EKEvent) -> CalendarEvent? {
        guard let startDate = event.startDate, let endDate = event.endDate else {
            return nil
        }
        let externalID = event.calendarItemIdentifier
        return CalendarEvent(
            id: DeterministicID.uuid(forExternalID: externalID),
            externalID: externalID,
            title: event.title ?? "",
            startDate: startDate,
            endDate: endDate,
            isAllDay: event.isAllDay,
            calendarName: event.calendar?.title
        )
    }
}
