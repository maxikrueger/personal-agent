import XCTest
@testable import PersonalAgent

final class TimeWindowAnalyzerTests: XCTestCase {
    private let calendar = utcCalendar()

    private func utcDate(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    func testFewerThanThreeCompletionsGiveNoWindow() {
        let analysis = TimeWindowAnalyzer.analyze(
            completionDates: [utcDate(day: 1, hour: 19), utcDate(day: 2, hour: 19)],
            calendar: calendar
        )

        XCTAssertNil(analysis.window)
        XCTAssertEqual(analysis.confidence, 0)
        XCTAssertEqual(analysis.sampleSize, 2)
    }

    func testEveningPreferenceIsDetected() {
        let completions = [
            utcDate(day: 1, hour: 19),
            utcDate(day: 2, hour: 20),
            utcDate(day: 3, hour: 18),
            utcDate(day: 4, hour: 21),
            utcDate(day: 5, hour: 9),
            utcDate(day: 6, hour: 10),
        ]

        let analysis = TimeWindowAnalyzer.analyze(completionDates: completions, calendar: calendar)

        XCTAssertEqual(analysis.window, .evening)
        XCTAssertEqual(analysis.confidence, 4.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(analysis.sampleSize, 6)
    }

    func testTieBreaksDeterministicallyTowardsEarlierWindow() {
        let completions = [
            utcDate(day: 1, hour: 9),
            utcDate(day: 2, hour: 10),
            utcDate(day: 3, hour: 19),
            utcDate(day: 4, hour: 20),
        ]

        let analysis = TimeWindowAnalyzer.analyze(completionDates: completions, calendar: calendar)

        XCTAssertEqual(analysis.window, .morning)
        XCTAssertEqual(analysis.confidence, 0.5, accuracy: 0.0001)
    }

    func testWindowBoundaries() {
        XCTAssertEqual(TimeWindow.window(forHour: 0), .night)
        XCTAssertEqual(TimeWindow.window(forHour: 5), .night)
        XCTAssertEqual(TimeWindow.window(forHour: 6), .morning)
        XCTAssertEqual(TimeWindow.window(forHour: 11), .morning)
        XCTAssertEqual(TimeWindow.window(forHour: 12), .afternoon)
        XCTAssertEqual(TimeWindow.window(forHour: 17), .afternoon)
        XCTAssertEqual(TimeWindow.window(forHour: 18), .evening)
        XCTAssertEqual(TimeWindow.window(forHour: 23), .evening)
    }
}
