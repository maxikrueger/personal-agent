import XCTest
@testable import PersonalAgent

final class TaskRecurrenceTests: XCTestCase {
    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 7) -> Date {
        berlin.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testDailyAdvanceByOneOrMoreDays() {
        let daily = TaskRecurrence(frequency: .daily)

        XCTAssertTrue(daily.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 10, 6), calendar: berlin))
        XCTAssertTrue(daily.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 10, 9), calendar: berlin))
    }

    func testDailyKeepsWallTimeAcrossDaylightSavingChange() {
        let daily = TaskRecurrence(frequency: .daily)

        // 28 → 29 March 2026 is only 23 hours in Berlin.
        XCTAssertTrue(daily.isOccurrenceAdvance(from: date(2026, 3, 28), to: date(2026, 3, 29), calendar: berlin))
    }

    func testOffScheduleOrBackwardMovesAreNotAdvances() {
        let daily = TaskRecurrence(frequency: .daily)

        XCTAssertFalse(daily.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 10, 5, 10), calendar: berlin))
        XCTAssertFalse(daily.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 10, 4), calendar: berlin))
        XCTAssertFalse(daily.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 10, 5), calendar: berlin))
    }

    func testIntervalIsRespected() {
        let everyOtherDay = TaskRecurrence(frequency: .daily, interval: 2)

        XCTAssertFalse(everyOtherDay.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 10, 6), calendar: berlin))
        XCTAssertTrue(everyOtherDay.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 10, 7), calendar: berlin))
    }

    func testWeeklyAndMonthlySteps() {
        let weekly = TaskRecurrence(frequency: .weekly)
        let monthly = TaskRecurrence(frequency: .monthly)

        XCTAssertTrue(weekly.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 10, 12), calendar: berlin))
        XCTAssertFalse(weekly.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 10, 8), calendar: berlin))
        XCTAssertTrue(monthly.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 11, 5), calendar: berlin))
    }

    func testConstrainedRuleAcceptsAnyMoveWithinOnePeriod() {
        // e.g. "every week on Monday and Friday": Monday → Friday is the next occurrence.
        let weekdays = TaskRecurrence(frequency: .weekly, hasAdditionalConstraints: true)

        XCTAssertTrue(weekdays.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 10, 9), calendar: berlin))
        XCTAssertFalse(weekdays.isOccurrenceAdvance(from: date(2026, 10, 5), to: date(2026, 10, 20), calendar: berlin))
    }

    func testIntervalBelowOneIsClamped() {
        XCTAssertEqual(TaskRecurrence(frequency: .daily, interval: 0).interval, 1)
    }
}
