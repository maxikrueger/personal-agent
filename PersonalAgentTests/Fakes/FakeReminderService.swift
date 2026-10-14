import Foundation
@testable import PersonalAgent

/// Configure results before use; tests drive it single-threaded.
final class FakeReminderService: ReminderService, @unchecked Sendable {
    var accessResult: Result<Void, Error> = .success(())
    var tasksResult: Result<[PersonalAgent.Task], Error> = .success([])
    var allTasksResult: Result<[PersonalAgent.Task], Error> = .success([])
    var fullAccess = true
    private(set) var fetchCallCount = 0
    private(set) var fetchAllCallCount = 0

    func requestAccess() async throws {
        try accessResult.get()
    }

    func hasFullAccess() async -> Bool {
        fullAccess
    }

    func fetchOpenTasks() async throws -> [PersonalAgent.Task] {
        fetchCallCount += 1
        try accessResult.get()
        return try tasksResult.get()
    }

    func fetchAllTasks() async throws -> [PersonalAgent.Task] {
        fetchAllCallCount += 1
        try accessResult.get()
        return try allTasksResult.get()
    }

    var createResult: Result<Void, Error> = .success(())
    private(set) var createdReminders: [(title: String, notes: String?, dueDate: Date?)] = []

    func createReminder(title: String, notes: String?, dueDate: Date?) async throws -> PersonalAgent.Task {
        try accessResult.get()
        try createResult.get()
        createdReminders.append((title, notes, dueDate))
        return PersonalAgent.Task(
            id: UUID(),
            externalID: UUID().uuidString,
            title: title,
            notes: notes,
            dueDate: dueDate,
            creationDate: nil,
            completionDate: nil,
            isCompleted: false,
            listName: nil
        )
    }
}
