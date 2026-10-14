import XCTest
@testable import PersonalAgent

final class ReminderEffectivenessAnalyzerTests: XCTestCase {
    private let taskID = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func scheduledEvent(fireDate: Date) -> TaskEvent {
        makeEvent(
            taskID: taskID,
            type: .reminderScheduled,
            timestamp: fireDate.addingTimeInterval(-3600),
            metadata: ["notificationID": "task-x", "fireDate": fireDate.formatted(.iso8601)]
        )
    }

    func testWithoutRemindersRatesAreZero() {
        let events = [
            makeEvent(taskID: taskID, type: .completed, timestamp: now.addingTimeInterval(-86_400))
        ]

        let effectiveness = ReminderEffectivenessAnalyzer.analyze(events: events, now: now)

        XCTAssertEqual(effectiveness.firedReminderCount, 0)
        XCTAssertEqual(effectiveness.completionAfterReminderRate, 0)
        XCTAssertEqual(effectiveness.completionsWithoutReminder, 1)
        XCTAssertNil(effectiveness.averageDelayAfterReminder)
    }

    func testCompletionWithinWindowIsAttributed() {
        let fireDate = now.addingTimeInterval(-2 * 86_400)
        let events = [
            scheduledEvent(fireDate: fireDate),
            makeEvent(taskID: taskID, type: .completed, timestamp: fireDate.addingTimeInterval(2 * 3600)),
        ]

        let effectiveness = ReminderEffectivenessAnalyzer.analyze(events: events, now: now)

        XCTAssertEqual(effectiveness.firedReminderCount, 1)
        XCTAssertEqual(effectiveness.completionsAfterReminder, 1)
        XCTAssertEqual(effectiveness.completionAfterReminderRate, 1)
        XCTAssertEqual(effectiveness.averageDelayAfterReminder ?? 0, 2 * 3600, accuracy: 0.001)
        XCTAssertEqual(effectiveness.completionsWithoutReminder, 0)
    }

    func testCompletionOutsideWindowIsNotAttributed() {
        let fireDate = now.addingTimeInterval(-3 * 86_400)
        let events = [
            scheduledEvent(fireDate: fireDate),
            makeEvent(taskID: taskID, type: .completed, timestamp: fireDate.addingTimeInterval(30 * 3600)),
        ]

        let effectiveness = ReminderEffectivenessAnalyzer.analyze(events: events, now: now)

        XCTAssertEqual(effectiveness.completionsAfterReminder, 0)
        XCTAssertEqual(effectiveness.completionsWithoutReminder, 1)
    }

    func testFutureFireDatesAreExcluded() {
        let events = [scheduledEvent(fireDate: now.addingTimeInterval(86_400))]

        let effectiveness = ReminderEffectivenessAnalyzer.analyze(events: events, now: now)

        XCTAssertEqual(effectiveness.firedReminderCount, 0)
    }

    func testDismissRate() {
        let firstFire = now.addingTimeInterval(-4 * 86_400)
        let secondFire = now.addingTimeInterval(-2 * 86_400)
        let events = [
            scheduledEvent(fireDate: firstFire),
            scheduledEvent(fireDate: secondFire),
            makeEvent(taskID: taskID, type: .reminderDismissed, timestamp: secondFire.addingTimeInterval(600)),
        ]

        let effectiveness = ReminderEffectivenessAnalyzer.analyze(events: events, now: now)

        XCTAssertEqual(effectiveness.dismissedCount, 1)
        XCTAssertEqual(effectiveness.dismissRate, 0.5, accuracy: 0.000001)
    }

    func testMalformedFireDateIsIgnored() {
        let events = [
            makeEvent(
                taskID: taskID,
                type: .reminderScheduled,
                timestamp: now.addingTimeInterval(-86_400),
                metadata: ["fireDate": "kein-datum"]
            )
        ]

        let effectiveness = ReminderEffectivenessAnalyzer.analyze(events: events, now: now)

        XCTAssertEqual(effectiveness.firedReminderCount, 0)
    }

    func testMultipleRemindersAreEachAttributed() {
        let firstFire = now.addingTimeInterval(-5 * 86_400)
        let secondFire = now.addingTimeInterval(-2 * 86_400)
        let events = [
            scheduledEvent(fireDate: firstFire),
            scheduledEvent(fireDate: secondFire),
            makeEvent(taskID: taskID, type: .completed, timestamp: firstFire.addingTimeInterval(3600)),
            makeEvent(taskID: taskID, type: .completed, timestamp: secondFire.addingTimeInterval(2 * 3600)),
        ]

        let effectiveness = ReminderEffectivenessAnalyzer.analyze(events: events, now: now)

        XCTAssertEqual(effectiveness.completionsAfterReminder, 2)
        XCTAssertEqual(effectiveness.completionAfterReminderRate, 1)
        XCTAssertEqual(effectiveness.averageDelayAfterReminder ?? 0, 1.5 * 3600, accuracy: 0.001)
    }
}
