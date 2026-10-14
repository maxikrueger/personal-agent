import XCTest
@testable import PersonalAgent

final class NotificationEventRecorderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_098_400)

    private struct Environment {
        let recorder: NotificationEventRecorder
        let taskRepository: TaskRepository
        let eventRepository: TaskEventRepository
    }

    private func makeEnvironment() async throws -> Environment {
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await provider.preparedDatabase()
        let fixedNow = now
        return Environment(
            recorder: NotificationEventRecorder(databaseProvider: provider, now: { fixedNow }),
            taskRepository: TaskRepository(database: database),
            eventRepository: TaskEventRepository(database: database)
        )
    }

    func testRecordsDeliveredEventForKnownTask() async throws {
        let environment = try await makeEnvironment()
        let task = makeTask(title: "Steuer")
        try await environment.taskRepository.upsert(task, updatedAt: now)
        let identifier = NotificationIdentifier.forTask(task.id)

        await environment.recorder.record(type: .reminderDelivered, identifier: identifier)

        let events = try await environment.eventRepository.events(forTaskID: task.id)
        XCTAssertEqual(events.map(\.type), [.reminderDelivered])
        XCTAssertEqual(events[0].metadata["notificationID"], identifier)
        XCTAssertEqual(events[0].timestamp, now)
    }

    func testRecordingIsIdempotentPerTypeAndNotification() async throws {
        let environment = try await makeEnvironment()
        let task = makeTask(title: "Steuer")
        try await environment.taskRepository.upsert(task, updatedAt: now)
        let identifier = NotificationIdentifier.forTask(task.id)

        await environment.recorder.record(type: .reminderDelivered, identifier: identifier)
        await environment.recorder.record(type: .reminderDelivered, identifier: identifier)
        await environment.recorder.record(type: .reminderDismissed, identifier: identifier)

        let events = try await environment.eventRepository.events(forTaskID: task.id)
        XCTAssertEqual(events.map(\.type), [.reminderDelivered, .reminderDismissed])
    }

    func testAdhocIdentifierRecordsNothing() async throws {
        let environment = try await makeEnvironment()

        await environment.recorder.record(
            type: .reminderDelivered,
            identifier: NotificationIdentifier.adhoc(UUID())
        )

        let events = try await environment.eventRepository.allEvents()
        XCTAssertTrue(events.isEmpty)
    }

    func testUnknownTaskIDIsSwallowedSafely() async throws {
        let environment = try await makeEnvironment()

        // No task row exists — the foreign-key failure must be swallowed.
        await environment.recorder.record(
            type: .reminderDelivered,
            identifier: NotificationIdentifier.forTask(UUID())
        )

        let events = try await environment.eventRepository.allEvents()
        XCTAssertTrue(events.isEmpty)
    }
}
