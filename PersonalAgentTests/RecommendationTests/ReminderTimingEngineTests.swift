import XCTest
@testable import PersonalAgent

final class ReminderTimingEngineTests: XCTestCase {
    private let calendar = utcCalendar()
    private let duration: TimeInterval = 1800

    private func utcDate(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
    }

    private func interval(day: Int, fromHour: Int, toHour: Int) -> DateInterval {
        DateInterval(start: utcDate(day: day, hour: fromHour), end: utcDate(day: day, hour: toHour))
    }

    func testSlotStartsAreCandidates() {
        let candidates = ReminderTimingEngine.candidateTimes(
            freeSlots: [interval(day: 31, fromHour: 9, toHour: 11), interval(day: 31, fromHour: 14, toHour: 16)],
            preferredWindow: nil,
            taskDuration: duration,
            calendar: calendar
        )

        XCTAssertEqual(candidates, [utcDate(day: 31, hour: 9), utcDate(day: 31, hour: 14)])
    }

    func testWindowStartInsideSlotIsAdded() {
        let candidates = ReminderTimingEngine.candidateTimes(
            freeSlots: [interval(day: 31, fromHour: 14, toHour: 21)],
            preferredWindow: .evening,
            taskDuration: duration,
            calendar: calendar
        )

        XCTAssertEqual(candidates, [utcDate(day: 31, hour: 14), utcDate(day: 31, hour: 18)])
    }

    func testWindowStartEqualToSlotStartIsNotDuplicated() {
        let candidates = ReminderTimingEngine.candidateTimes(
            freeSlots: [interval(day: 31, fromHour: 18, toHour: 21)],
            preferredWindow: .evening,
            taskDuration: duration,
            calendar: calendar
        )

        XCTAssertEqual(candidates, [utcDate(day: 31, hour: 18)])
    }

    func testSlotShorterThanTaskDurationIsSkipped() {
        let shortSlot = DateInterval(start: utcDate(day: 31, hour: 10), duration: 20 * 60)

        let candidates = ReminderTimingEngine.candidateTimes(
            freeSlots: [shortSlot],
            preferredWindow: nil,
            taskDuration: duration,
            calendar: calendar
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testWindowStartLeavingTooLittleRoomIsSkipped() {
        let slot = DateInterval(
            start: utcDate(day: 31, hour: 17),
            end: utcDate(day: 31, hour: 18, minute: 15)
        )

        let candidates = ReminderTimingEngine.candidateTimes(
            freeSlots: [slot],
            preferredWindow: .evening,
            taskDuration: duration,
            calendar: calendar
        )

        // 18:00 + 30 min would end past 18:15 — only the slot start remains.
        XCTAssertEqual(candidates, [utcDate(day: 31, hour: 17)])
    }

    func testMultiDaySlotGetsWindowStartPerDay() {
        let slot = DateInterval(
            start: utcDate(day: 31, hour: 10),
            end: utcDate(day: 32, hour: 23)
        )

        let candidates = ReminderTimingEngine.candidateTimes(
            freeSlots: [slot],
            preferredWindow: .evening,
            taskDuration: duration,
            calendar: calendar
        )

        XCTAssertEqual(candidates, [
            utcDate(day: 31, hour: 10),
            utcDate(day: 31, hour: 18),
            utcDate(day: 32, hour: 18),
        ])
    }

    func testCandidatesAreSortedAndDeduplicated() {
        let candidates = ReminderTimingEngine.candidateTimes(
            freeSlots: [
                interval(day: 31, fromHour: 18, toHour: 21),
                interval(day: 31, fromHour: 9, toHour: 10),
                interval(day: 31, fromHour: 18, toHour: 20),
            ],
            preferredWindow: .evening,
            taskDuration: duration,
            calendar: calendar
        )

        XCTAssertEqual(candidates, [utcDate(day: 31, hour: 9), utcDate(day: 31, hour: 18)])
    }
}
