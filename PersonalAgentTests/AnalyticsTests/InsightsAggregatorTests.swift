import XCTest
@testable import PersonalAgent

final class InsightsAggregatorTests: XCTestCase {
    private let calendar = utcCalendar()
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12))!
    }

    private func utcDate(month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func report(
        _ taskData: [(task: PersonalAgent.Task, events: [TaskEvent])],
        outcomes: [RecommendationOutcome] = []
    ) -> InsightsReport {
        InsightsAggregator.report(taskData: taskData, outcomes: outcomes, now: now, calendar: calendar)
    }

    private func postponedTask(title: String, count: Int) -> (task: PersonalAgent.Task, events: [TaskEvent]) {
        let taskID = UUID()
        let events = (1...count).map { index in
            makeEvent(
                taskID: taskID,
                type: .postponed,
                timestamp: now.addingTimeInterval(Double(-index) * 86_400)
            )
        }
        return (makeTask(id: taskID, title: title), events)
    }

    private func completedTask(
        title: String,
        completionHours: [Date]
    ) -> (task: PersonalAgent.Task, events: [TaskEvent]) {
        let taskID = UUID()
        var events: [TaskEvent] = []
        for (index, completion) in completionHours.enumerated() {
            if index > 0 {
                events.append(
                    makeEvent(taskID: taskID, type: .reopened, timestamp: completion.addingTimeInterval(-43_200))
                )
            }
            events.append(makeEvent(taskID: taskID, type: .completed, timestamp: completion))
        }
        let task = makeTask(
            id: taskID,
            title: title,
            completionDate: completionHours.last,
            isCompleted: true
        )
        return (task, events)
    }

    func testEmptyDataProducesEmptyReport() {
        let result = report([])

        XCTAssertEqual(result.openTaskCount, 0)
        XCTAssertEqual(result.completedTaskCount, 0)
        XCTAssertTrue(result.frequentlyPostponed.isEmpty)
        XCTAssertTrue(result.reliablyCompleted.isEmpty)
        XCTAssertTrue(result.bestCompletionWindows.isEmpty)
        XCTAssertNil(result.reminderEffectiveness)
        XCTAssertTrue(result.recurringPatterns.isEmpty)
        XCTAssertEqual(result.outcomeTotals, .empty)
    }

    func testTaskCounts() {
        let result = report([
            (makeTask(title: "Offen A"), []),
            (makeTask(title: "Offen B"), []),
            completedTask(title: "Fertig", completionHours: [utcDate(month: 8, day: 20, hour: 19)]),
        ])

        XCTAssertEqual(result.openTaskCount, 2)
        XCTAssertEqual(result.completedTaskCount, 1)
    }

    func testFrequentlyPostponedFiltersSortsAndExcludesCompleted() {
        var closedPostponed = postponedTask(title: "Erledigt trotz Schieben", count: 4)
        closedPostponed.task = makeTask(
            id: closedPostponed.task.id,
            title: closedPostponed.task.title,
            completionDate: now.addingTimeInterval(-3600),
            isCompleted: true
        )

        let result = report([
            postponedTask(title: "Einmal", count: 1),
            postponedTask(title: "Zweimal", count: 2),
            postponedTask(title: "Dreimal", count: 3),
            closedPostponed,
        ])

        XCTAssertEqual(result.frequentlyPostponed.map(\.title), ["Dreimal", "Zweimal"])
        XCTAssertEqual(result.frequentlyPostponed.map(\.postponementCount), [3, 2])
    }

    func testFrequentlyPostponedIsCappedAtFive() {
        let tasks = (2...8).map { count in
            postponedTask(title: "Aufgabe \(count)", count: count)
        }

        let result = report(tasks)

        XCTAssertEqual(result.frequentlyPostponed.count, InsightsAggregator.maxListedTasks)
        XCTAssertEqual(result.frequentlyPostponed.first?.postponementCount, 8)
        XCTAssertEqual(result.frequentlyPostponed.last?.postponementCount, 4)
    }

    func testReliablyCompletedRequiresRateAndSample() {
        let reliable = completedTask(
            title: "Zuverlässig",
            completionHours: [
                utcDate(month: 8, day: 10, hour: 19),
                utcDate(month: 8, day: 17, hour: 19),
                utcDate(month: 8, day: 24, hour: 19),
            ]
        )
        let tooFew = completedTask(
            title: "Zu wenig",
            completionHours: [utcDate(month: 8, day: 24, hour: 19)]
        )
        // Three completions but currently open again → rate 3/4 = 0.75 < 0.8.
        let unreliableID = UUID()
        var unreliableEvents: [TaskEvent] = []
        for day in [5, 12, 19] {
            unreliableEvents.append(
                makeEvent(taskID: unreliableID, type: .completed, timestamp: utcDate(month: 8, day: day, hour: 19))
            )
            unreliableEvents.append(
                makeEvent(taskID: unreliableID, type: .reopened, timestamp: utcDate(month: 8, day: day + 1, hour: 9))
            )
        }
        let unreliable = (makeTask(id: unreliableID, title: "Wackelig"), unreliableEvents)

        let result = report([reliable, tooFew, unreliable])

        XCTAssertEqual(result.reliablyCompleted.map(\.title), ["Zuverlässig"])
        XCTAssertEqual(result.reliablyCompleted[0].completionRate, 1.0)
        XCTAssertEqual(result.reliablyCompleted[0].completionCount, 3)
    }

    func testBestWindowsAggregateAcrossTasks() {
        let eveningTask = completedTask(
            title: "Abend",
            completionHours: [
                utcDate(month: 8, day: 10, hour: 19),
                utcDate(month: 8, day: 12, hour: 20),
            ]
        )
        let mixedTask = completedTask(
            title: "Gemischt",
            completionHours: [
                utcDate(month: 8, day: 14, hour: 19),
                utcDate(month: 8, day: 16, hour: 9),
            ]
        )

        let result = report([eveningTask, mixedTask])

        XCTAssertEqual(result.bestCompletionWindows.count, 2)
        XCTAssertEqual(result.bestCompletionWindows[0].window, .evening)
        XCTAssertEqual(result.bestCompletionWindows[0].completionCount, 3)
        XCTAssertEqual(result.bestCompletionWindows[0].share, 0.75, accuracy: 0.000001)
        XCTAssertEqual(result.bestCompletionWindows[1].window, .morning)
        XCTAssertEqual(result.bestCompletionWindows[1].completionCount, 1)
    }

    func testWindowsRequireMinimumCompletions() {
        let result = report([
            completedTask(
                title: "Zu wenig",
                completionHours: [utcDate(month: 8, day: 10, hour: 19), utcDate(month: 8, day: 12, hour: 19)]
            )
        ])

        XCTAssertTrue(result.bestCompletionWindows.isEmpty)
    }

    func testReminderEffectivenessAggregatesAndBucketsByWindow() throws {
        let successID = UUID()
        let eveningFire = utcDate(month: 8, day: 25, hour: 19)
        let successEvents = [
            makeEvent(
                taskID: successID,
                type: .reminderScheduled,
                timestamp: eveningFire.addingTimeInterval(-3600),
                metadata: ["fireDate": eveningFire.formatted(.iso8601)]
            ),
            makeEvent(taskID: successID, type: .completed, timestamp: eveningFire.addingTimeInterval(2 * 3600)),
        ]
        let failureID = UUID()
        let morningFire = utcDate(month: 8, day: 26, hour: 9)
        let failureEvents = [
            makeEvent(
                taskID: failureID,
                type: .reminderScheduled,
                timestamp: morningFire.addingTimeInterval(-3600),
                metadata: ["fireDate": morningFire.formatted(.iso8601)]
            )
        ]

        let result = report([
            (makeTask(id: successID, title: "Klappt", completionDate: nil, isCompleted: false), successEvents),
            (makeTask(id: failureID, title: "Klappt nicht"), failureEvents),
        ])

        let effectiveness = try XCTUnwrap(result.reminderEffectiveness)
        XCTAssertEqual(effectiveness.firedCount, 2)
        XCTAssertEqual(effectiveness.completedAfterCount, 1)
        XCTAssertEqual(effectiveness.rate, 0.5, accuracy: 0.000001)
        XCTAssertEqual(effectiveness.byWindow.map(\.window), [.morning, .evening])
        XCTAssertEqual(effectiveness.byWindow[0].completedAfterCount, 0)
        XCTAssertEqual(effectiveness.byWindow[1].completedAfterCount, 1)
        XCTAssertEqual(effectiveness.byWindow[1].rate, 1.0, accuracy: 0.000001)
    }

    func testFutureRemindersProduceNoEffectivenessInsight() {
        let taskID = UUID()
        let futureFire = now.addingTimeInterval(86_400)
        let events = [
            makeEvent(
                taskID: taskID,
                type: .reminderScheduled,
                timestamp: now.addingTimeInterval(-3600),
                metadata: ["fireDate": futureFire.formatted(.iso8601)]
            )
        ]

        let result = report([(makeTask(id: taskID, title: "Später"), events)])

        XCTAssertNil(result.reminderEffectiveness)
    }

    func testRecurringPatternsListed() {
        let weekly = completedTask(
            title: "Wochenbericht",
            completionHours: (0..<4).map { utcDate(month: 6, day: 1 + 7 * $0, hour: 19) }
        )
        let oneOff = completedTask(
            title: "Einmalig",
            completionHours: [utcDate(month: 8, day: 20, hour: 19)]
        )

        let result = report([weekly, oneOff])

        XCTAssertEqual(result.recurringPatterns.count, 1)
        XCTAssertEqual(result.recurringPatterns[0].title, "Wochenbericht")
        XCTAssertEqual(result.recurringPatterns[0].pattern, .weekly)
        XCTAssertEqual(result.recurringPatterns[0].confidence, 0.5, accuracy: 0.000001)
        XCTAssertEqual(result.recurringPatterns[0].sampleSize, 4)
    }

    func testOutcomeTotalsAreSummed() {
        let outcomes = [
            RecommendationOutcome(recommendationID: UUID(), outcome: .accepted, timestamp: now),
            RecommendationOutcome(recommendationID: UUID(), outcome: .completed, timestamp: now),
            RecommendationOutcome(recommendationID: UUID(), outcome: .completed, timestamp: now),
        ]

        let result = report([], outcomes: outcomes)

        XCTAssertEqual(result.outcomeTotals.accepted, 1)
        XCTAssertEqual(result.outcomeTotals.completed, 2)
        XCTAssertEqual(result.outcomeTotals.total, 3)
    }
}
