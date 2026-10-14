import EventKit
import XCTest
@testable import PersonalAgent

/// Builds EKReminder objects purely in memory — nothing is saved to a store,
/// so no permissions are required.
final class ReminderMappingTests: XCTestCase {
    private var store: EKEventStore!

    override func setUp() {
        super.setUp()
        store = EKEventStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    func testMapsAllBasicFields() {
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Steuerunterlagen sortieren"
        reminder.notes = "Ordner im Regal"

        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Privat"
        reminder.calendar = calendar

        var dueComponents = DateComponents(year: 2026, month: 9, day: 1, hour: 18, minute: 30)
        dueComponents.calendar = Calendar.current
        reminder.dueDateComponents = dueComponents

        let task = ReminderMapper.task(from: reminder)

        XCTAssertEqual(task.title, "Steuerunterlagen sortieren")
        XCTAssertEqual(task.notes, "Ordner im Regal")
        XCTAssertEqual(task.listName, "Privat")
        XCTAssertEqual(task.externalID, reminder.calendarItemIdentifier)
        XCTAssertFalse(task.externalID.isEmpty)
        XCTAssertEqual(task.dueDate, Calendar.current.date(from: dueComponents))
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completionDate)
        // creationDate is only assigned by EventKit on save, so it stays nil here.
        XCTAssertNil(task.creationDate)
    }

    func testMapsCompletedReminder() {
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Erledigt"
        let completed = Date(timeIntervalSince1970: 1_756_000_000)
        reminder.completionDate = completed

        let task = ReminderMapper.task(from: reminder)

        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(task.completionDate, completed)
    }

    func testMapsReminderWithoutOptionalFields() {
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Nur Titel"

        let task = ReminderMapper.task(from: reminder)

        XCTAssertEqual(task.title, "Nur Titel")
        XCTAssertNil(task.notes)
        XCTAssertNil(task.dueDate)
        XCTAssertNil(task.listName)
    }

    func testDueDateFromDateOnlyComponents() {
        var components = DateComponents(year: 2026, month: 9, day: 1)
        components.calendar = Calendar.current

        let date = ReminderMapper.dueDate(from: components)

        XCTAssertEqual(date, Calendar.current.date(from: components))
    }

    func testDueDateFromComponentsWithoutEmbeddedCalendar() {
        let components = DateComponents(year: 2026, month: 9, day: 1, hour: 8)

        let date = ReminderMapper.dueDate(from: components)

        XCTAssertEqual(date, Calendar.current.date(from: components))
    }

    func testDueDateFromNilComponents() {
        XCTAssertNil(ReminderMapper.dueDate(from: nil))
    }

    func testNormalizedRoundsToWholeSeconds() {
        XCTAssertEqual(
            ReminderMapper.normalized(Date(timeIntervalSince1970: 1_756_000_000.789)),
            Date(timeIntervalSince1970: 1_756_000_001)
        )
        XCTAssertEqual(
            ReminderMapper.normalized(Date(timeIntervalSince1970: 1_756_000_000.2)),
            Date(timeIntervalSince1970: 1_756_000_000)
        )
        XCTAssertNil(ReminderMapper.normalized(nil))
    }

    func testMappedCompletionDateHasNoFractionalSeconds() throws {
        // EventKit may truncate or replace the completion date it hands back for
        // an unsaved reminder; the mapper's guarantee is only "whole seconds".
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Nachkommastellen"
        reminder.completionDate = Date(timeIntervalSince1970: 1_756_000_000.789)

        let task = ReminderMapper.task(from: reminder)

        let completionDate = try XCTUnwrap(task.completionDate)
        XCTAssertEqual(completionDate.timeIntervalSince1970, completionDate.timeIntervalSince1970.rounded())
    }

    func testDeterministicIDIsStableAndDistinct() {
        let first = ReminderMapper.deterministicID(forExternalID: "external-a")
        let second = ReminderMapper.deterministicID(forExternalID: "external-a")
        let other = ReminderMapper.deterministicID(forExternalID: "external-b")

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, other)
    }

    func testMappingSameReminderTwiceYieldsSameID() {
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Stabil"

        let taskA = ReminderMapper.task(from: reminder)
        let taskB = ReminderMapper.task(from: reminder)

        XCTAssertEqual(taskA.id, taskB.id)
    }

    func testDistinctRemindersYieldDistinctIDs() {
        let reminderA = EKReminder(eventStore: store)
        reminderA.title = "A"
        let reminderB = EKReminder(eventStore: store)
        reminderB.title = "B"

        XCTAssertNotEqual(
            ReminderMapper.task(from: reminderA).id,
            ReminderMapper.task(from: reminderB).id
        )
    }

    func testMapsRecurrenceRule() {
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Pflanzen gießen"
        reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 2, end: nil))

        let task = ReminderMapper.task(from: reminder)

        XCTAssertEqual(task.recurrence, TaskRecurrence(frequency: .daily, interval: 2))
    }

    func testWeekdayRestrictedRuleIsMarkedConstrained() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.friday)],
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )

        XCTAssertEqual(
            ReminderMapper.recurrence(from: rule),
            TaskRecurrence(frequency: .weekly, interval: 1, hasAdditionalConstraints: true)
        )
    }

    func testReminderWithoutRuleHasNoRecurrence() {
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Einmalig"

        XCTAssertNil(ReminderMapper.task(from: reminder).recurrence)
    }
}
