import XCTest
@testable import PersonalAgent

final class TaskAnalyticsEngineTests: XCTestCase {
    private let calendar = utcCalendar()

    private func utcDate(_ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func postponedEvent(taskID: UUID, at timestamp: Date, old: Date, new: Date) -> TaskEvent {
        makeEvent(
            taskID: taskID,
            type: .postponed,
            timestamp: timestamp,
            metadata: [
                "field": "dueDate",
                "oldDueDate": old.formatted(.iso8601),
                "newDueDate": new.formatted(.iso8601),
            ]
        )
    }

    /// Exact scenario: postponed twice, then completed 4 hours after
    /// the final due date. Every derived number is asserted exactly.
    func testPostponedTwiceThenCompletedLate() {
        let taskID = UUID()
        let creation = utcDate(8, 1, hour: 10)
        let dueFirst = utcDate(8, 5, hour: 18)
        let dueSecond = utcDate(8, 7, hour: 18)
        let dueFinal = utcDate(8, 10, hour: 18)
        let completion = utcDate(8, 10, hour: 22)
        let now = utcDate(8, 15, hour: 12)

        let task = makeTask(
            id: taskID,
            externalID: "ext-tax",
            title: "Steuerunterlagen sortieren",
            dueDate: dueFinal,
            creationDate: creation,
            completionDate: completion,
            isCompleted: true
        )
        let events = [
            makeEvent(taskID: taskID, type: .created, timestamp: creation),
            postponedEvent(taskID: taskID, at: utcDate(8, 4, hour: 9), old: dueFirst, new: dueSecond),
            postponedEvent(taskID: taskID, at: utcDate(8, 6, hour: 9), old: dueSecond, new: dueFinal),
            makeEvent(taskID: taskID, type: .completed, timestamp: completion),
        ]

        let analysis = TaskAnalyticsEngine.analyze(
            task: task,
            events: events,
            now: now,
            calendar: calendar
        )
        let statistics = analysis.statistics

        XCTAssertEqual(analysis.completionCount, 1)
        XCTAssertEqual(analysis.cycleCount, 1)
        XCTAssertEqual(statistics.completionRate, 1.0)

        XCTAssertEqual(statistics.postponementCount, 2)
        XCTAssertEqual(statistics.postponementRate, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(analysis.consecutivePostponements, 0)
        // Shifts of 2 and 3 days average to 2.5 days.
        XCTAssertEqual(analysis.averagePostponementDelay ?? 0, 2.5 * 86_400, accuracy: 0.001)

        // Delay is measured against the due date in effect at completion (the final one).
        XCTAssertEqual(statistics.averageDelay ?? 0, 4 * 3600, accuracy: 0.001)
        XCTAssertEqual(statistics.medianDelay ?? 0, 4 * 3600, accuracy: 0.001)
        XCTAssertEqual(statistics.overdueCount, 1)
        XCTAssertFalse(analysis.isCurrentlyOverdue)

        // One completion: no recurrence, no window inference.
        XCTAssertEqual(statistics.recurrenceConfidence, 0)
        XCTAssertNil(statistics.preferredCompletionWindow)

        // score = 0.35·(2/3) + 0.25·1 + 0.2·(4h/7d) + 0.1·0 + 0.1·0
        let expectedScore = 0.35 * (2.0 / 3.0) + 0.25 * 1.0 + 0.2 * (4.0 * 3600 / (7 * 86_400))
        XCTAssertEqual(statistics.procrastinationScore, expectedScore, accuracy: 0.0001)
    }

    func testOpenLongPostponedTaskScoresHigh() {
        let taskID = UUID()
        let creation = utcDate(8, 1, hour: 8)
        let now = utcDate(8, 21, hour: 8) // open for exactly 20 days
        let due = utcDate(8, 20, hour: 18) // currently overdue

        let task = makeTask(
            id: taskID,
            externalID: "ext-call",
            title: "Versicherung anrufen",
            dueDate: due,
            creationDate: creation
        )
        let base = utcDate(8, 10, hour: 9)
        let events = [
            makeEvent(taskID: taskID, type: .created, timestamp: creation),
            postponedEvent(taskID: taskID, at: base, old: utcDate(8, 10, hour: 18), new: utcDate(8, 11, hour: 18)),
            postponedEvent(taskID: taskID, at: base.addingTimeInterval(86_400), old: utcDate(8, 11, hour: 18), new: utcDate(8, 12, hour: 18)),
            postponedEvent(taskID: taskID, at: base.addingTimeInterval(2 * 86_400), old: utcDate(8, 12, hour: 18), new: utcDate(8, 13, hour: 18)),
        ]

        let analysis = TaskAnalyticsEngine.analyze(
            task: task,
            events: events,
            now: now,
            calendar: calendar
        )
        let statistics = analysis.statistics

        XCTAssertEqual(statistics.completionRate, 0)
        XCTAssertEqual(statistics.postponementRate, 1.0)
        XCTAssertEqual(analysis.consecutivePostponements, 3)
        XCTAssertTrue(analysis.isCurrentlyOverdue)
        XCTAssertEqual(statistics.overdueCount, 1)
        XCTAssertNil(statistics.averageDelay)

        // score = 0.35·1 + 0.25·1 + 0.2·0 + 0.1·(20d/30d) + 0.1·(3/5)
        let expectedScore = 0.35 + 0.25 + 0.1 * (20.0 / 30.0) + 0.1 * 0.6
        XCTAssertEqual(statistics.procrastinationScore, expectedScore, accuracy: 0.0001)
    }

    func testRecurringEveningTaskGetsWindowAndPattern() {
        let taskID = UUID()
        // Completed weekly, always around 19:00 UTC, six times.
        let completions = (0..<6).map { utcDate(6, 1 + 7 * $0, hour: 19) }
        var events: [TaskEvent] = [
            makeEvent(taskID: taskID, type: .created, timestamp: utcDate(5, 30, hour: 12))
        ]
        for (index, completion) in completions.enumerated() {
            if index > 0 {
                events.append(makeEvent(taskID: taskID, type: .reopened, timestamp: completion.addingTimeInterval(-86_400)))
            }
            events.append(makeEvent(taskID: taskID, type: .completed, timestamp: completion))
        }
        let task = makeTask(
            id: taskID,
            externalID: "ext-weekly",
            title: "Wochenbericht",
            completionDate: completions.last,
            isCompleted: true
        )

        let analysis = TaskAnalyticsEngine.analyze(
            task: task,
            events: events,
            now: utcDate(7, 15, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(analysis.completionCount, 6)
        XCTAssertEqual(analysis.recurrence.pattern, .weekly)
        XCTAssertEqual(analysis.statistics.recurrenceConfidence, 5.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(analysis.statistics.preferredCompletionWindow, .evening)
        XCTAssertEqual(analysis.preferredWindow.confidence, 1.0, accuracy: 0.0001)
        XCTAssertEqual(analysis.preferredWindow.sampleSize, 6)
    }
}
