import EventKit
import XCTest
@testable import PersonalAgent

/// Builds EKEvent objects purely in memory — nothing is saved, no permissions needed.
final class CalendarEventMappingTests: XCTestCase {
    private var store: EKEventStore!

    override func setUp() {
        super.setUp()
        store = EKEventStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    func testMapsAllFields() {
        let event = EKEvent(eventStore: store)
        event.title = "Zahnarzt"
        event.startDate = Date(timeIntervalSince1970: 1_800_100_000)
        event.endDate = Date(timeIntervalSince1970: 1_800_103_600)
        event.isAllDay = false
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Privat"
        event.calendar = calendar

        let mapped = CalendarEventMapper.calendarEvent(from: event)

        XCTAssertNotNil(mapped)
        XCTAssertEqual(mapped?.title, "Zahnarzt")
        XCTAssertEqual(mapped?.startDate, Date(timeIntervalSince1970: 1_800_100_000))
        XCTAssertEqual(mapped?.endDate, Date(timeIntervalSince1970: 1_800_103_600))
        XCTAssertEqual(mapped?.isAllDay, false)
        XCTAssertEqual(mapped?.calendarName, "Privat")
        XCTAssertEqual(mapped?.externalID, event.calendarItemIdentifier)
        XCTAssertFalse(mapped?.externalID.isEmpty ?? true)
    }

    func testMappingIsDeterministic() {
        let event = EKEvent(eventStore: store)
        event.title = "Stabil"
        event.startDate = Date(timeIntervalSince1970: 1_800_100_000)
        event.endDate = Date(timeIntervalSince1970: 1_800_101_800)

        let first = CalendarEventMapper.calendarEvent(from: event)
        let second = CalendarEventMapper.calendarEvent(from: event)

        XCTAssertEqual(first?.id, second?.id)
    }

    func testEventWithoutDatesMapsToNil() {
        let event = EKEvent(eventStore: store)
        event.title = "Ohne Datum"

        XCTAssertNil(CalendarEventMapper.calendarEvent(from: event))
    }

    func testAllDayFlagIsPreserved() {
        let event = EKEvent(eventStore: store)
        event.title = "Feiertag"
        event.startDate = Date(timeIntervalSince1970: 1_800_100_000)
        event.endDate = Date(timeIntervalSince1970: 1_800_186_400)
        event.isAllDay = true

        XCTAssertEqual(CalendarEventMapper.calendarEvent(from: event)?.isAllDay, true)
    }
}
