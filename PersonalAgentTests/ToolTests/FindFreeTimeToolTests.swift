import XCTest
@testable import PersonalAgent

final class FindFreeTimeToolTests: XCTestCase {
    private let calendar = utcCalendar()
    /// Sunday 2026-08-30, 14:00 UTC (asserted in setUp).
    private let now = Date(timeIntervalSince1970: 1_788_098_400)

    override func setUp() {
        super.setUp()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: now)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 30)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.weekday, 1) // Sunday
    }

    private func makeTool(service: FakeCalendarService) -> FindFreeTimeTool {
        let fixedNow = now
        return FindFreeTimeTool(calendarService: service, calendar: calendar, now: { fixedNow })
    }

    private func args(
        day: Int,
        duration: Int? = nil,
        earliest: Int? = nil,
        latest: Int? = nil
    ) -> FindFreeTimeTool.Arguments {
        FindFreeTimeTool.Arguments(
            daysFromToday: day,
            durationMinutes: duration,
            earliestHour: earliest,
            latestHour: latest
        )
    }

    private func utcDate(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
    }

    func testDefaultsResolveTomorrowWindow() async throws {
        let service = FakeCalendarService()
        _ = try await makeTool(service: service).call(arguments: args(day: 1))

        XCTAssertEqual(service.recordedQueries.count, 1)
        XCTAssertEqual(service.recordedQueries[0].from, utcDate(day: 31, hour: 8))
        XCTAssertEqual(service.recordedQueries[0].to, utcDate(day: 31, hour: 21))
        XCTAssertEqual(service.recordedQueries[0].duration, 1800)
    }

    func testTodayClampsSearchStartToNow() async throws {
        let service = FakeCalendarService()
        _ = try await makeTool(service: service).call(arguments: args(day: 0))

        XCTAssertEqual(service.recordedQueries[0].from, now)
        XCTAssertEqual(service.recordedQueries[0].to, utcDate(day: 30, hour: 21))
    }

    func testLatestHour24ReachesMidnight() async throws {
        let service = FakeCalendarService()
        _ = try await makeTool(service: service).call(arguments: args(day: 1, earliest: 20, latest: 24))

        XCTAssertEqual(service.recordedQueries[0].to, utcDate(day: 32, hour: 0))
    }

    func testSlotsAreRenderedWithGermanDayAndTimes() async throws {
        let service = FakeCalendarService()
        service.freeTimeResult = .success([
            DateInterval(start: utcDate(day: 31, hour: 18, minute: 30), duration: 45 * 60)
        ])

        let output = try await makeTool(service: service)
            .call(arguments: args(day: 1, duration: 45, earliest: 18, latest: 21))

        XCTAssertTrue(output.contains("Montag, 31.08.2026"))
        XCTAssertTrue(output.contains("zwischen 18:00 und 21:00"))
        XCTAssertTrue(output.contains("• 18:30–19:15 (45 Minuten)"))
    }

    func testNoSlotsMessage() async throws {
        let service = FakeCalendarService()
        service.freeTimeResult = .success([])

        let output = try await makeTool(service: service).call(arguments: args(day: 1))

        XCTAssertTrue(output.contains("Keine freien Zeiträume"))
        XCTAssertTrue(output.contains("Montag, 31.08.2026"))
    }

    func testLongSlotListIsTruncated() async throws {
        let service = FakeCalendarService()
        service.freeTimeResult = .success(
            (0..<10).map { index in
                DateInterval(start: utcDate(day: 31, hour: 8 + index), duration: 1800)
            }
        )

        let output = try await makeTool(service: service).call(arguments: args(day: 1))

        let bulletCount = output.components(separatedBy: "• ").count - 1
        XCTAssertEqual(bulletCount, FindFreeTimeTool.maxListedSlots)
        XCTAssertTrue(output.contains("und 2 weitere"))
    }

    func testAccessDeniedBecomesFactualErrorText() async throws {
        let service = FakeCalendarService()
        service.accessResult = .failure(CalendarServiceError.accessDenied)

        let output = try await makeTool(service: service).call(arguments: args(day: 1))

        XCTAssertTrue(output.contains("Fehler beim Kalenderzugriff"))
        XCTAssertTrue(output.contains("Kalender"))
    }

    func testInvalidArgumentsAreRejectedWithoutServiceCall() async throws {
        let service = FakeCalendarService()
        let tool = makeTool(service: service)

        let dayOutput = try await tool.call(arguments: args(day: -1))
        XCTAssertTrue(dayOutput.contains("Ungültiger Tag"))

        let durationOutput = try await tool.call(arguments: args(day: 1, duration: 2))
        XCTAssertTrue(durationOutput.contains("Ungültige Dauer"))

        let windowOutput = try await tool.call(arguments: args(day: 1, earliest: 20, latest: 18))
        XCTAssertTrue(windowOutput.contains("Ungültiges Zeitfenster"))

        XCTAssertTrue(service.recordedQueries.isEmpty)
    }

    func testExhaustedTodayWindowShortCircuits() async throws {
        let service = FakeCalendarService()
        // Now is 14:00; a 90-minute slot cannot fit before 15:00.
        let output = try await makeTool(service: service)
            .call(arguments: args(day: 0, duration: 90, latest: 15))

        XCTAssertTrue(output.contains("keine ausreichende Zeit"))
        XCTAssertTrue(service.recordedQueries.isEmpty)
    }
}
