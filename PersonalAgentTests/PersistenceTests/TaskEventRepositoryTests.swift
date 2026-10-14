import XCTest
@testable import PersonalAgent

final class TaskEventRepositoryTests: XCTestCase {
    private func makeRepositories() async throws -> (TaskRepository, TaskEventRepository) {
        let database = try await makeTestDatabase()
        return (TaskRepository(database: database), TaskEventRepository(database: database))
    }

    private func insertTask(_ repository: TaskRepository) async throws -> PersonalAgent.Task {
        let task = makeTask()
        try await repository.upsert(task, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        return task
    }

    func testInsertAndFetchRoundtrip() async throws {
        let (taskRepository, eventRepository) = try await makeRepositories()
        let task = try await insertTask(taskRepository)
        let event = TaskEvent(
            taskID: task.id,
            type: .postponed,
            timestamp: Date(timeIntervalSince1970: 1_800_100_000),
            metadata: ["field": "dueDate", "oldDueDate": "2026-09-01T18:00:00Z"]
        )

        try await eventRepository.insert(event)
        let events = try await eventRepository.events(forTaskID: task.id)

        XCTAssertEqual(events, [event])
    }

    func testEventsAreOrderedByTimestamp() async throws {
        let (taskRepository, eventRepository) = try await makeRepositories()
        let task = try await insertTask(taskRepository)
        let later = TaskEvent(taskID: task.id, type: .modified, timestamp: Date(timeIntervalSince1970: 1_800_200_000))
        let earlier = TaskEvent(taskID: task.id, type: .created, timestamp: Date(timeIntervalSince1970: 1_800_100_000))

        try await eventRepository.insert(later)
        try await eventRepository.insert(earlier)
        let events = try await eventRepository.events(forTaskID: task.id)

        XCTAssertEqual(events.map(\.type), [.created, .modified])
    }

    func testEventsAreFilteredByTask() async throws {
        let (taskRepository, eventRepository) = try await makeRepositories()
        let first = try await insertTask(taskRepository)
        let second = try await insertTask(taskRepository)
        try await eventRepository.insert(
            TaskEvent(taskID: first.id, type: .created, timestamp: Date(timeIntervalSince1970: 1_800_100_000))
        )
        try await eventRepository.insert(
            TaskEvent(taskID: second.id, type: .created, timestamp: Date(timeIntervalSince1970: 1_800_100_000))
        )

        let events = try await eventRepository.events(forTaskID: first.id)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].taskID, first.id)

        let all = try await eventRepository.allEvents()
        XCTAssertEqual(all.count, 2)
    }

    func testEmptyMetadataRoundtrips() async throws {
        let (taskRepository, eventRepository) = try await makeRepositories()
        let task = try await insertTask(taskRepository)
        let event = TaskEvent(taskID: task.id, type: .created, timestamp: Date(timeIntervalSince1970: 1_800_100_000))

        try await eventRepository.insert(event)
        let events = try await eventRepository.events(forTaskID: task.id)

        XCTAssertEqual(events[0].metadata, [:])
    }

    func testInsertForUnknownTaskThrowsForeignKeyError() async throws {
        let (_, eventRepository) = try await makeRepositories()
        let orphan = TaskEvent(taskID: UUID(), type: .created, timestamp: Date(timeIntervalSince1970: 1_800_100_000))

        do {
            try await eventRepository.insert(orphan)
            XCTFail("Expected a foreign-key violation")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }
}
