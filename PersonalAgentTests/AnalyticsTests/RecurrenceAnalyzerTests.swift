import XCTest
@testable import PersonalAgent

final class RecurrenceAnalyzerTests: XCTestCase {
    private let calendar = utcCalendar()

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func dates(startingAt start: Date, count: Int, intervalDays: Double) -> [Date] {
        (0..<count).map { start.addingTimeInterval(Double($0) * intervalDays * 86_400) }
    }

    func testFewerThanThreeCompletionsGiveNoInference() {
        let analysis = RecurrenceAnalyzer.analyze(
            completionDates: dates(startingAt: utcDate(2026, 8, 3), count: 2, intervalDays: 7),
            calendar: calendar
        )

        XCTAssertNil(analysis.pattern)
        XCTAssertEqual(analysis.confidence, 0)
        XCTAssertEqual(analysis.sampleSize, 2)
    }

    func testPerfectWeeklyPattern() {
        let analysis = RecurrenceAnalyzer.analyze(
            completionDates: dates(startingAt: utcDate(2026, 6, 1), count: 6, intervalDays: 7),
            calendar: calendar
        )

        XCTAssertEqual(analysis.pattern, .weekly)
        XCTAssertEqual(analysis.confidence, 5.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(analysis.sampleSize, 6)
    }

    func testDailyPatternSpanningWeekend() {
        // Fri Sep 4 … Tue Sep 8 2026 — includes a weekend, so daily, not everyWeekday.
        let analysis = RecurrenceAnalyzer.analyze(
            completionDates: dates(startingAt: utcDate(2026, 9, 4), count: 5, intervalDays: 1),
            calendar: calendar
        )

        XCTAssertEqual(analysis.pattern, .daily)
        XCTAssertEqual(analysis.confidence, 4.0 / 6.0, accuracy: 0.0001)
    }

    func testWeekdayOnlyPatternIsDetected() {
        // Mon Aug 31 – Fri Sep 4 and Mon Sep 7 – Fri Sep 11 2026 (all weekdays).
        let firstWeek = dates(startingAt: utcDate(2026, 8, 31), count: 5, intervalDays: 1)
        let secondWeek = dates(startingAt: utcDate(2026, 9, 7), count: 5, intervalDays: 1)

        let analysis = RecurrenceAnalyzer.analyze(
            completionDates: firstWeek + secondWeek,
            calendar: calendar
        )

        XCTAssertEqual(analysis.pattern, .everyWeekday)
        XCTAssertEqual(analysis.confidence, 8.0 / 9.0, accuracy: 0.0001)
    }

    func testMonthlyPattern() {
        let analysis = RecurrenceAnalyzer.analyze(
            completionDates: dates(startingAt: utcDate(2026, 1, 15), count: 4, intervalDays: 30),
            calendar: calendar
        )

        XCTAssertEqual(analysis.pattern, .monthly)
        XCTAssertEqual(analysis.confidence, 0.5, accuracy: 0.0001)
    }

    func testConsistentUnnamedIntervalIsIrregularButRecurring() {
        let analysis = RecurrenceAnalyzer.analyze(
            completionDates: dates(startingAt: utcDate(2026, 7, 1), count: 7, intervalDays: 3),
            calendar: calendar
        )

        XCTAssertEqual(analysis.pattern, .irregular)
        XCTAssertEqual(analysis.confidence, 1.0, accuracy: 0.0001)
    }

    func testChaoticDatesGiveNoPattern() {
        let start = utcDate(2026, 5, 1)
        let chaotic = [0.0, 1, 21, 24, 79].map { start.addingTimeInterval($0 * 86_400) }

        let analysis = RecurrenceAnalyzer.analyze(completionDates: chaotic, calendar: calendar)

        XCTAssertNil(analysis.pattern)
        XCTAssertLessThan(analysis.confidence, RecurrenceAnalyzer.confidenceThreshold)
    }
}
