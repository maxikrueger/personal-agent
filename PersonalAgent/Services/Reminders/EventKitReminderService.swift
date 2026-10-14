import EventKit
import Foundation

actor EventKitReminderService: ReminderService {
    private let store = EKEventStore()

    func hasFullAccess() -> Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func requestAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return
        case .notDetermined:
            let granted = try await store.requestFullAccessToReminders()
            guard granted else { throw ReminderServiceError.accessDenied }
        case .restricted:
            throw ReminderServiceError.accessRestricted
        default:
            // .denied, .writeOnly, and the deprecated .authorized (never returned on iOS 26)
            throw ReminderServiceError.accessDenied
        }
    }

    func fetchOpenTasks() async throws -> [Task] {
        try await requestAccess()
        return try await fetch(
            matching: store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil
            )
        )
    }

    func fetchAllTasks() async throws -> [Task] {
        try await requestAccess()
        return try await fetch(matching: store.predicateForReminders(in: nil))
    }

    func createReminder(title: String, notes: String?, dueDate: Date?) async throws -> Task {
        try await requestAccess()
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw ReminderServiceError.creationFailed
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = calendar
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw ReminderServiceError.creationFailed
        }
        return ReminderMapper.task(from: reminder)
    }

    private func fetch(matching predicate: NSPredicate) async throws -> [Task] {
        try await withCheckedThrowingContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else {
                    continuation.resume(throwing: ReminderServiceError.fetchFailed)
                    return
                }
                // Map before resuming so only Sendable domain values cross the boundary.
                continuation.resume(returning: reminders.map(ReminderMapper.task(from:)))
            }
        }
    }
}
