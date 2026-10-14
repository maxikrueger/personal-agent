import EventKit
import Foundation

actor EventKitCalendarService: CalendarService {
    private let store = EKEventStore()

    func requestAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = try await store.requestFullAccessToEvents()
            guard granted else { throw CalendarServiceError.accessDenied }
        case .restricted:
            throw CalendarServiceError.accessRestricted
        default:
            // .denied, .writeOnly (reading needs full access), deprecated .authorized
            throw CalendarServiceError.accessDenied
        }
    }

    func fetchEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        guard to > from else { return [] }
        try await requestAccess()
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate)
            .compactMap(CalendarEventMapper.calendarEvent(from:))
            .sorted { $0.startDate < $1.startDate }
    }

    func findFreeTime(from: Date, to: Date, duration: TimeInterval) async throws -> [DateInterval] {
        guard to > from else { return [] }
        let events = try await fetchEvents(from: from, to: to)
        return FreeTimeCalculator.freeIntervals(
            busy: FreeTimeCalculator.busyIntervals(from: events),
            range: DateInterval(start: from, end: to),
            minimumDuration: duration
        )
    }
}
