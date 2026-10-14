import XCTest
@testable import PersonalAgent

final class TaskSyncServiceTests: XCTestCase {
    private let syncTime = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeEnvironment() -> (
        service: TaskSyncService,
        reminders: FakeReminderService,
        tasks: TaskRepository,
        events: TaskEventRepository
    ) {
        let reminders = FakeReminderService()
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        let service = TaskSyncService(reminderService: reminders, databaseProvider: provider)
        return (service, reminders, TaskRepository(database: database), TaskEventRepository(database: database))
    }

    func testFirstSyncStoresTasksAndCreatedEvents() async throws {
        let environment = makeEnvironment()
        let creation = Date(timeIntervalSince1970: 1_700_000_000)
        let taskA = makeTask(externalID: "ext-a", title: "A", creationDate: creation)
        let taskB = makeTask(externalID: "ext-b", title: "B")
        environment.reminders.allTasksResult = .success([taskA, taskB])

        let summary = try await environment.service.synchronize(now: syncTime)

        XCTAssertEqual(summary.created, 2)
        XCTAssertEqual(summary.totalEvents, 2)
        let storedTasks = try await environment.tasks.allTasks()
        XCTAssertEqual(storedTasks.count, 2)
        let events = try await environment.events.allEvents()
        XCTAssertEqual(events.map(\.type), [.created, .created])
        // Pre-existing reminders keep their original creation date as event timestamp.
        XCTAssertEqual(events[0].timestamp, creation)
        XCTAssertEqual(events[1].timestamp, syncTime)
    }

    func testSecondSyncWithSameStateEmitsNothing() async throws {
        let environment = makeEnvironment()
        let task = makeTask(
            externalID: "ext-a",
            title: "A",
            dueDate: Date(timeIntervalSince1970: 1_800_100_000),
            creationDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        environment.reminders.allTasksResult = .success([task])

        _ = try await environment.service.synchronize(now: syncTime)
        let second = try await environment.service.synchronize(now: syncTime.addingTimeInterval(60))

        XCTAssertEqual(second.totalEvents, 0)
        XCTAssertEqual(second.unchanged, 1)
        let events = try await environment.events.allEvents()
        XCTAssertEqual(events.count, 1)
    }

    func testCompletionInAppleRemindersIsDetected() async throws {
        let environment = makeEnvironment()
        let completionDate = Date(timeIntervalSince1970: 1_800_050_000)
        environment.reminders.allTasksResult = .success([makeTask(externalID: "ext-a", title: "A")])
        _ = try await environment.service.synchronize(now: syncTime)

        environment.reminders.allTasksResult = .success([
            makeTask(externalID: "ext-a", title: "A", completionDate: completionDate, isCompleted: true)
        ])
        let summary = try await environment.service.synchronize(now: syncTime.addingTimeInterval(60_000))

        XCTAssertEqual(summary.completed, 1)
        let storedTasks = try await environment.tasks.allTasks()
        XCTAssertTrue(storedTasks[0].isCompleted)
        let events = try await environment.events.allEvents()
        XCTAssertEqual(events.map(\.type), [.created, .completed])
        XCTAssertEqual(events[1].timestamp, completionDate)
    }

    func testReopeningIsDetected() async throws {
        let environment = makeEnvironment()
        environment.reminders.allTasksResult = .success([
            makeTask(
                externalID: "ext-a",
                title: "A",
                completionDate: Date(timeIntervalSince1970: 1_799_000_000),
                isCompleted: true
            )
        ])
        _ = try await environment.service.synchronize(now: syncTime)

        environment.reminders.allTasksResult = .success([makeTask(externalID: "ext-a", title: "A")])
        let summary = try await environment.service.synchronize(now: syncTime.addingTimeInterval(60))

        XCTAssertEqual(summary.reopened, 1)
        let storedTasks = try await environment.tasks.allTasks()
        XCTAssertFalse(storedTasks[0].isCompleted)
    }

    func testPostponementIsDetectedWithDates() async throws {
        let environment = makeEnvironment()
        let oldDue = Date(timeIntervalSince1970: 1_800_100_000)
        let newDue = Date(timeIntervalSince1970: 1_800_300_000)
        environment.reminders.allTasksResult = .success([
            makeTask(externalID: "ext-a", title: "A", dueDate: oldDue)
        ])
        _ = try await environment.service.synchronize(now: syncTime)

        environment.reminders.allTasksResult = .success([
            makeTask(externalID: "ext-a", title: "A", dueDate: newDue)
        ])
        let summary = try await environment.service.synchronize(now: syncTime.addingTimeInterval(60))

        XCTAssertEqual(summary.postponed, 1)
        let events = try await environment.events.allEvents()
        XCTAssertEqual(events.map(\.type), [.created, .postponed])
        XCTAssertEqual(events[1].metadata["oldDueDate"], oldDue.formatted(.iso8601))
        XCTAssertEqual(events[1].metadata["newDueDate"], newDue.formatted(.iso8601))
    }

    func testTitleChangeIsDetectedAsModified() async throws {
        let environment = makeEnvironment()
        environment.reminders.allTasksResult = .success([makeTask(externalID: "ext-a", title: "Alt")])
        _ = try await environment.service.synchronize(now: syncTime)

        environment.reminders.allTasksResult = .success([makeTask(externalID: "ext-a", title: "Neu")])
        let summary = try await environment.service.synchronize(now: syncTime.addingTimeInterval(60))

        XCTAssertEqual(summary.modified, 1)
        let storedTasks = try await environment.tasks.allTasks()
        XCTAssertEqual(storedTasks[0].title, "Neu")
    }

    func testStoredIDStaysStableAcrossSyncs() async throws {
        let environment = makeEnvironment()
        environment.reminders.allTasksResult = .success([makeTask(externalID: "ext-a", title: "A")])
        _ = try await environment.service.synchronize(now: syncTime)
        let originalID = try await environment.tasks.allTasks()[0].id

        // A freshly mapped task arrives with a different in-memory ID but the
        // same external ID — the stored identity must win.
        environment.reminders.allTasksResult = .success([
            makeTask(id: UUID(), externalID: "ext-a", title: "Neu")
        ])
        _ = try await environment.service.synchronize(now: syncTime.addingTimeInterval(60))

        let storedTasks = try await environment.tasks.allTasks()
        XCTAssertEqual(storedTasks.count, 1)
        XCTAssertEqual(storedTasks[0].id, originalID)
        let events = try await environment.events.allEvents()
        XCTAssertTrue(events.allSatisfy { $0.taskID == originalID })
    }

    func testTaskDeletedInRemindersIsPreservedWithoutEvents() async throws {
        let environment = makeEnvironment()
        environment.reminders.allTasksResult = .success([makeTask(externalID: "ext-a", title: "A")])
        _ = try await environment.service.synchronize(now: syncTime)

        environment.reminders.allTasksResult = .success([])
        let summary = try await environment.service.synchronize(now: syncTime.addingTimeInterval(60))

        XCTAssertEqual(summary.totalEvents, 0)
        let storedTasks = try await environment.tasks.allTasks()
        XCTAssertEqual(storedTasks.count, 1)
        let events = try await environment.events.allEvents()
        XCTAssertEqual(events.count, 1)
    }

    func testFetchFailurePropagates() async {
        let environment = makeEnvironment()
        environment.reminders.allTasksResult = .failure(ReminderServiceError.fetchFailed)

        do {
            _ = try await environment.service.synchronize(now: syncTime)
            XCTFail("Expected the fetch error to propagate")
        } catch {
            XCTAssertEqual(error as? ReminderServiceError, .fetchFailed)
        }
    }

    func testSyncIfAuthorizedSkipsWithoutAccess() async throws {
        let environment = makeEnvironment()
        environment.reminders.fullAccess = false
        environment.reminders.allTasksResult = .success([makeTask(externalID: "ext-a", title: "A")])

        await environment.service.syncIfAuthorized()

        XCTAssertEqual(environment.reminders.fetchAllCallCount, 0)
    }

    func testRecurringTaskIsUnchangedOnRepeatedSync() async throws {
        let environment = makeEnvironment()
        let task = makeTask(
            externalID: "ext-r",
            title: "Sport",
            dueDate: Date(timeIntervalSince1970: 1_800_100_000),
            recurrence: TaskRecurrence(frequency: .daily)
        )
        environment.reminders.allTasksResult = .success([task])

        _ = try await environment.service.synchronize(now: syncTime)
        let second = try await environment.service.synchronize(now: syncTime.addingTimeInterval(60))

        XCTAssertEqual(second.unchanged, 1)
        XCTAssertEqual(second.totalEvents, 0)
    }

    func testCompletingARecurringReminderIsRecordedAsCompletion() async throws {
        let environment = makeEnvironment()
        let firstDue = Date(timeIntervalSince1970: 1_800_100_000)
        let rule = TaskRecurrence(frequency: .daily)
        environment.reminders.allTasksResult = .success([
            makeTask(externalID: "ext-r", title: "Sport", dueDate: firstDue, recurrence: rule)
        ])
        _ = try await environment.service.synchronize(now: syncTime)

        let nextDue = Calendar.current.date(byAdding: .day, value: 1, to: firstDue)!
        environment.reminders.allTasksResult = .success([
            makeTask(externalID: "ext-r", title: "Sport", dueDate: nextDue, recurrence: rule)
        ])
        let summary = try await environment.service.synchronize(now: syncTime.addingTimeInterval(3600))

        XCTAssertEqual(summary.completed, 1)
        XCTAssertEqual(summary.postponed, 0)
    }
}
