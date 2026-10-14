import XCTest
@testable import PersonalAgent

final class TaskChangeDetectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let taskID = UUID()
    private let externalID = "ext-1"

    private func base(
        title: String = "Aufgabe",
        notes: String? = nil,
        dueDate: Date? = nil,
        creationDate: Date? = nil,
        completionDate: Date? = nil,
        isCompleted: Bool = false,
        listName: String? = nil
    ) -> PersonalAgent.Task {
        makeTask(
            id: taskID,
            externalID: externalID,
            title: title,
            notes: notes,
            dueDate: dueDate,
            creationDate: creationDate,
            completionDate: completionDate,
            isCompleted: isCompleted,
            listName: listName
        )
    }

    func testNewTaskEmitsCreatedWithCreationDate() {
        let creation = Date(timeIntervalSince1970: 1_700_000_000)
        let task = base(creationDate: creation)

        let events = TaskChangeDetector.events(previous: nil, current: task, now: now)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .created)
        XCTAssertEqual(events[0].taskID, taskID)
        XCTAssertEqual(events[0].timestamp, creation)
        XCTAssertTrue(events[0].metadata.isEmpty)
    }

    func testNewTaskWithoutCreationDateUsesNow() {
        let events = TaskChangeDetector.events(previous: nil, current: base(), now: now)

        XCTAssertEqual(events.map(\.type), [.created])
        XCTAssertEqual(events[0].timestamp, now)
    }

    func testUnchangedTaskEmitsNothing() {
        let task = base(title: "Gleich", dueDate: now.addingTimeInterval(3600))

        let events = TaskChangeDetector.events(previous: task, current: task, now: now)

        XCTAssertTrue(events.isEmpty)
    }

    func testCompletionEmitsCompletedWithCompletionDate() {
        let completion = Date(timeIntervalSince1970: 1_799_000_000)
        let previous = base()
        let current = base(completionDate: completion, isCompleted: true)

        let events = TaskChangeDetector.events(previous: previous, current: current, now: now)

        XCTAssertEqual(events.map(\.type), [.completed])
        XCTAssertEqual(events[0].timestamp, completion)
    }

    func testCompletionWithoutCompletionDateUsesNow() {
        let events = TaskChangeDetector.events(
            previous: base(),
            current: base(isCompleted: true),
            now: now
        )

        XCTAssertEqual(events.map(\.type), [.completed])
        XCTAssertEqual(events[0].timestamp, now)
    }

    func testReopeningEmitsReopened() {
        let previous = base(completionDate: now.addingTimeInterval(-7200), isCompleted: true)
        let current = base()

        let events = TaskChangeDetector.events(previous: previous, current: current, now: now)

        XCTAssertEqual(events.map(\.type), [.reopened])
        XCTAssertEqual(events[0].timestamp, now)
    }

    func testDueDateMovedLaterEmitsPostponedWithDates() {
        let oldDue = Date(timeIntervalSince1970: 1_800_100_000)
        let newDue = Date(timeIntervalSince1970: 1_800_200_000)
        let events = TaskChangeDetector.events(
            previous: base(dueDate: oldDue),
            current: base(dueDate: newDue),
            now: now
        )

        XCTAssertEqual(events.map(\.type), [.postponed])
        XCTAssertEqual(events[0].metadata["field"], "dueDate")
        XCTAssertEqual(events[0].metadata["oldDueDate"], oldDue.formatted(.iso8601))
        XCTAssertEqual(events[0].metadata["newDueDate"], newDue.formatted(.iso8601))
    }

    func testDueDateMovedEarlierEmitsModified() {
        let oldDue = Date(timeIntervalSince1970: 1_800_200_000)
        let newDue = Date(timeIntervalSince1970: 1_800_100_000)
        let events = TaskChangeDetector.events(
            previous: base(dueDate: oldDue),
            current: base(dueDate: newDue),
            now: now
        )

        XCTAssertEqual(events.map(\.type), [.modified])
        XCTAssertEqual(events[0].metadata["field"], "dueDate")
    }

    func testDueDateAddedEmitsModifiedWithNewDateOnly() {
        let newDue = Date(timeIntervalSince1970: 1_800_100_000)
        let events = TaskChangeDetector.events(
            previous: base(),
            current: base(dueDate: newDue),
            now: now
        )

        XCTAssertEqual(events.map(\.type), [.modified])
        XCTAssertNil(events[0].metadata["oldDueDate"])
        XCTAssertEqual(events[0].metadata["newDueDate"], newDue.formatted(.iso8601))
    }

    func testDueDateRemovedEmitsModifiedWithOldDateOnly() {
        let oldDue = Date(timeIntervalSince1970: 1_800_100_000)
        let events = TaskChangeDetector.events(
            previous: base(dueDate: oldDue),
            current: base(),
            now: now
        )

        XCTAssertEqual(events.map(\.type), [.modified])
        XCTAssertEqual(events[0].metadata["oldDueDate"], oldDue.formatted(.iso8601))
        XCTAssertNil(events[0].metadata["newDueDate"])
    }

    func testDueDateMovedLaterOnCompletedTaskIsModifiedNotPostponed() {
        let oldDue = Date(timeIntervalSince1970: 1_800_100_000)
        let newDue = Date(timeIntervalSince1970: 1_800_200_000)
        let events = TaskChangeDetector.events(
            previous: base(dueDate: oldDue, isCompleted: true),
            current: base(dueDate: newDue, isCompleted: true),
            now: now
        )

        XCTAssertEqual(events.map(\.type), [.modified])
    }

    func testTitleChangeEmitsModifiedWithoutContent() {
        let events = TaskChangeDetector.events(
            previous: base(title: "Alt"),
            current: base(title: "Neu"),
            now: now
        )

        XCTAssertEqual(events.map(\.type), [.modified])
        // Privacy: the event records which field changed, never the contents.
        XCTAssertEqual(events[0].metadata, ["field": "title"])
    }

    func testNotesAndListChangesEmitModifiedPerField() {
        let events = TaskChangeDetector.events(
            previous: base(notes: "a", listName: "Privat"),
            current: base(notes: "b", listName: "Arbeit"),
            now: now
        )

        XCTAssertEqual(events.map(\.type), [.modified, .modified])
        XCTAssertEqual(
            Set(events.compactMap { $0.metadata["field"] }),
            ["notes", "listName"]
        )
    }

    func testCombinedCompletionAndTitleChangeEmitsBothEvents() {
        let events = TaskChangeDetector.events(
            previous: base(title: "Alt"),
            current: base(title: "Neu", isCompleted: true),
            now: now
        )

        XCTAssertEqual(events.map(\.type), [.completed, .modified])
    }

    // MARK: - Recurring reminders

    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func recurringTask(dueDate: Date, recurrence: TaskRecurrence) -> PersonalAgent.Task {
        makeTask(id: taskID, externalID: externalID, dueDate: dueDate, recurrence: recurrence)
    }

    func testDailyReminderMovingToNextOccurrenceIsACompletion() {
        let oldDue = now.addingTimeInterval(-3600)
        let newDue = berlin.date(byAdding: .day, value: 1, to: oldDue)!
        let previous = recurringTask(dueDate: oldDue, recurrence: TaskRecurrence(frequency: .daily))
        let current = recurringTask(dueDate: newDue, recurrence: TaskRecurrence(frequency: .daily))

        let events = TaskChangeDetector.events(previous: previous, current: current, now: now, calendar: berlin)

        XCTAssertEqual(events.map(\.type), [.completed, .modified])
        XCTAssertEqual(events[0].timestamp, now)
        XCTAssertEqual(events[1].metadata["field"], "dueDate")
        XCTAssertEqual(events[1].metadata["reason"], TaskChangeDetector.nextOccurrenceReason)
    }

    func testSkippedOccurrencesStillCountAsOneCompletion() {
        let oldDue = now.addingTimeInterval(-3 * 86_400)
        let newDue = berlin.date(byAdding: .day, value: 4, to: oldDue)!
        let rule = TaskRecurrence(frequency: .daily)

        let events = TaskChangeDetector.events(
            previous: recurringTask(dueDate: oldDue, recurrence: rule),
            current: recurringTask(dueDate: newDue, recurrence: rule),
            now: now,
            calendar: berlin
        )

        XCTAssertEqual(events.map(\.type), [.completed, .modified])
    }

    func testRecurringReminderMovedOffScheduleIsAPostponement() {
        let oldDue = now.addingTimeInterval(-3600)
        let rule = TaskRecurrence(frequency: .daily)

        let events = TaskChangeDetector.events(
            previous: recurringTask(dueDate: oldDue, recurrence: rule),
            current: recurringTask(dueDate: oldDue.addingTimeInterval(3 * 3600), recurrence: rule),
            now: now,
            calendar: berlin
        )

        XCTAssertEqual(events.map(\.type), [.postponed])
    }

    func testSameMoveWithoutRecurrenceIsAPostponement() {
        let oldDue = now.addingTimeInterval(-3600)
        let newDue = berlin.date(byAdding: .day, value: 1, to: oldDue)!

        let events = TaskChangeDetector.events(
            previous: base(dueDate: oldDue),
            current: base(dueDate: newDue),
            now: now,
            calendar: berlin
        )

        XCTAssertEqual(events.map(\.type), [.postponed])
    }
}
