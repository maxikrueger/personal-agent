import XCTest
@testable import PersonalAgent

final class FreeTimeCalculatorTests: XCTestCase {
    private let halfHour: TimeInterval = 1800

    private func date(_ hours: Double) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + hours * 3600)
    }

    private func interval(_ fromHour: Double, _ toHour: Double) -> DateInterval {
        DateInterval(start: date(fromHour), end: date(toHour))
    }

    func testEmptyBusyReturnsWholeRange() {
        let free = FreeTimeCalculator.freeIntervals(
            busy: [],
            range: interval(8, 21),
            minimumDuration: halfHour
        )

        XCTAssertEqual(free, [interval(8, 21)])
    }

    func testSingleBusyIntervalSplitsRange() {
        let free = FreeTimeCalculator.freeIntervals(
            busy: [interval(10, 11)],
            range: interval(8, 21),
            minimumDuration: halfHour
        )

        XCTAssertEqual(free, [interval(8, 10), interval(11, 21)])
    }

    func testOverlappingBusyIntervalsAreMerged() {
        let free = FreeTimeCalculator.freeIntervals(
            busy: [interval(9, 11), interval(10, 12)],
            range: interval(8, 21),
            minimumDuration: halfHour
        )

        XCTAssertEqual(free, [interval(8, 9), interval(12, 21)])
    }

    func testAdjacentBusyIntervalsLeaveNoGap() {
        let free = FreeTimeCalculator.freeIntervals(
            busy: [interval(9, 10), interval(10, 11)],
            range: interval(8, 21),
            minimumDuration: halfHour
        )

        XCTAssertEqual(free, [interval(8, 9), interval(11, 21)])
    }

    func testBusyCoveringWholeRangeGivesNoSlots() {
        let free = FreeTimeCalculator.freeIntervals(
            busy: [interval(7, 22)],
            range: interval(8, 21),
            minimumDuration: halfHour
        )

        XCTAssertTrue(free.isEmpty)
    }

    func testShortGapsAreFilteredByMinimumDuration() {
        let free = FreeTimeCalculator.freeIntervals(
            busy: [interval(9, 20.5)],
            range: interval(8, 21),
            minimumDuration: 3600
        )

        // The trailing 30-minute gap is too short for 60 minutes.
        XCTAssertEqual(free, [interval(8, 9)])
    }

    func testBusyOutsideRangeIsIgnored() {
        let free = FreeTimeCalculator.freeIntervals(
            busy: [interval(5, 7), interval(22, 23)],
            range: interval(8, 21),
            minimumDuration: halfHour
        )

        XCTAssertEqual(free, [interval(8, 21)])
    }

    func testBusyPartiallyOverlappingRangeIsClipped() {
        let free = FreeTimeCalculator.freeIntervals(
            busy: [interval(7, 9), interval(20, 22)],
            range: interval(8, 21),
            minimumDuration: halfHour
        )

        XCTAssertEqual(free, [interval(9, 20)])
    }

    func testUnsortedBusyInputIsHandled() {
        let free = FreeTimeCalculator.freeIntervals(
            busy: [interval(15, 16), interval(9, 10)],
            range: interval(8, 21),
            minimumDuration: halfHour
        )

        XCTAssertEqual(free, [interval(8, 9), interval(10, 15), interval(16, 21)])
    }

    func testPlanScenarioEveningSlot() {
        // Evening range, 19:30–21:00 busy → 18:00–19:30 free.
        let free = FreeTimeCalculator.freeIntervals(
            busy: [interval(19.5, 21)],
            range: interval(18, 21),
            minimumDuration: 45 * 60
        )

        XCTAssertEqual(free, [interval(18, 19.5)])
    }

    func testRangeShorterThanDurationGivesNoSlots() {
        let free = FreeTimeCalculator.freeIntervals(
            busy: [],
            range: interval(8, 8.25),
            minimumDuration: halfHour
        )

        XCTAssertTrue(free.isEmpty)
    }

    func testBusyIntervalsExcludeAllDayAndEmptyEvents() {
        let events = [
            CalendarEvent(
                id: UUID(),
                externalID: "normal",
                title: "Meeting",
                startDate: date(10),
                endDate: date(11),
                isAllDay: false,
                calendarName: nil
            ),
            CalendarEvent(
                id: UUID(),
                externalID: "allday",
                title: "Feiertag",
                startDate: date(0),
                endDate: date(24),
                isAllDay: true,
                calendarName: nil
            ),
            CalendarEvent(
                id: UUID(),
                externalID: "empty",
                title: "Leer",
                startDate: date(12),
                endDate: date(12),
                isAllDay: false,
                calendarName: nil
            ),
        ]

        let busy = FreeTimeCalculator.busyIntervals(from: events)

        XCTAssertEqual(busy, [interval(10, 11)])
    }
}
