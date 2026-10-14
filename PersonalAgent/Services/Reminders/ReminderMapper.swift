import EventKit
import Foundation

/// Pure mapping from EventKit objects to domain models. Kept free of side effects
/// so it is unit-testable without permissions.
enum ReminderMapper {
    static func task(from reminder: EKReminder) -> Task {
        let externalID = reminder.calendarItemIdentifier
        return Task(
            id: deterministicID(forExternalID: externalID),
            externalID: externalID,
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDate: normalized(dueDate(from: reminder.dueDateComponents)),
            creationDate: normalized(reminder.creationDate),
            completionDate: normalized(reminder.completionDate),
            isCompleted: reminder.isCompleted,
            listName: reminder.calendar?.title,
            recurrence: recurrence(from: reminder.recurrenceRules?.first)
        )
    }

    /// Reminders carry at most one rule in practice; only the first is used.
    static func recurrence(from rule: EKRecurrenceRule?) -> TaskRecurrence? {
        guard let rule else { return nil }
        let frequency: TaskRecurrence.Frequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: return nil
        }
        // EventKit may report unused constraints as nil or as an empty array.
        let hasAdditionalConstraints = !(rule.daysOfTheWeek ?? []).isEmpty
            || !(rule.daysOfTheMonth ?? []).isEmpty
            || !(rule.daysOfTheYear ?? []).isEmpty
            || !(rule.weeksOfTheYear ?? []).isEmpty
            || !(rule.monthsOfTheYear ?? []).isEmpty
            || !(rule.setPositions ?? []).isEmpty
        return TaskRecurrence(
            frequency: frequency,
            interval: rule.interval,
            hasAdditionalConstraints: hasAdditionalConstraints
        )
    }

    /// Dates are rounded to whole seconds: sub-second fractions from EventKit do
    /// not survive the Date → SQLite REAL → Date roundtrip bit-exactly, which
    /// would make every sync see phantom changes. Whole seconds roundtrip exactly.
    static func normalized(_ date: Date?) -> Date? {
        guard let date else { return nil }
        return Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded())
    }

    /// EventKit due dates are `DateComponents` and may be date-only (no time).
    static func dueDate(from components: DateComponents?) -> Date? {
        guard let components else { return nil }
        if let date = components.date {
            return date
        }
        var calendar = components.calendar ?? Calendar.current
        if let timeZone = components.timeZone {
            calendar.timeZone = timeZone
        }
        return calendar.date(from: components)
    }

    static func deterministicID(forExternalID externalID: String) -> UUID {
        DeterministicID.uuid(forExternalID: externalID)
    }
}
