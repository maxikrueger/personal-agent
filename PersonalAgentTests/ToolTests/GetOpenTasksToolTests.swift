import XCTest
@testable import PersonalAgent

final class GetOpenTasksToolTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_788_000_000)

    private func makeTool(service: FakeReminderService) -> GetOpenTasksTool {
        let now = fixedNow
        return GetOpenTasksTool(reminderService: service, now: { now })
    }

    private func makeTask(
        title: String,
        dueDate: Date? = nil,
        isCompleted: Bool = false
    ) -> PersonalAgent.Task {
        PersonalAgent.Task(
            id: UUID(),
            externalID: UUID().uuidString,
            title: title,
            notes: nil,
            dueDate: dueDate,
            creationDate: nil,
            completionDate: nil,
            isCompleted: isCompleted,
            listName: nil
        )
    }

    func testEmptyResultProducesNoTasksMessage() async throws {
        let service = FakeReminderService()
        service.tasksResult = .success([])

        let output = try await makeTool(service: service).call(arguments: .init())

        XCTAssertTrue(output.contains("keine offenen Aufgaben"))
        XCTAssertEqual(service.fetchCallCount, 1)
    }

    func testTasksAreListedWithDueDateAndOverdueMarker() async throws {
        let overdueDate = fixedNow.addingTimeInterval(-3600)
        let futureDate = fixedNow.addingTimeInterval(3600)
        let service = FakeReminderService()
        service.tasksResult = .success([
            makeTask(title: "Zukunft", dueDate: futureDate),
            makeTask(title: "Versäumt", dueDate: overdueDate),
            makeTask(title: "Ohne Datum"),
        ])

        let output = try await makeTool(service: service).call(arguments: .init())

        XCTAssertTrue(output.contains("Offene Aufgaben (3):"))
        XCTAssertTrue(output.contains("Versäumt"))
        XCTAssertTrue(output.contains("Zukunft"))
        XCTAssertTrue(output.contains("Ohne Datum"))
        XCTAssertTrue(output.contains(GetOpenTasksTool.formattedDueDate(overdueDate)))
        XCTAssertTrue(output.contains("ÜBERFÄLLIG"))

        // Overdue (earlier due date) sorts before future; undated tasks come last.
        let overdueIndex = output.range(of: "Versäumt")!.lowerBound
        let futureIndex = output.range(of: "Zukunft")!.lowerBound
        let undatedIndex = output.range(of: "Ohne Datum")!.lowerBound
        XCTAssertLessThan(overdueIndex, futureIndex)
        XCTAssertLessThan(futureIndex, undatedIndex)
    }

    func testFutureTaskIsNotMarkedOverdue() async throws {
        let service = FakeReminderService()
        service.tasksResult = .success([
            makeTask(title: "Zukunft", dueDate: fixedNow.addingTimeInterval(3600))
        ])

        let output = try await makeTool(service: service).call(arguments: .init())

        XCTAssertFalse(output.contains("ÜBERFÄLLIG"))
    }

    func testAccessDeniedBecomesFactualErrorText() async throws {
        let service = FakeReminderService()
        service.accessResult = .failure(ReminderServiceError.accessDenied)

        let output = try await makeTool(service: service).call(arguments: .init())

        XCTAssertTrue(output.contains("Fehler beim Zugriff"))
        XCTAssertTrue(output.contains("Zugriff auf Erinnerungen"))
    }

    func testFetchFailureBecomesFactualErrorText() async throws {
        let service = FakeReminderService()
        service.tasksResult = .failure(ReminderServiceError.fetchFailed)

        let output = try await makeTool(service: service).call(arguments: .init())

        XCTAssertTrue(output.contains("Fehler beim Zugriff"))
    }

    func testUnknownErrorPropagates() async {
        struct DummyError: Error {}
        let service = FakeReminderService()
        service.tasksResult = .failure(DummyError())
        let tool = makeTool(service: service)

        do {
            _ = try await tool.call(arguments: .init())
            XCTFail("Expected the unknown error to propagate")
        } catch {
            XCTAssertTrue(error is DummyError)
        }
    }

    func testLongListIsTruncated() async throws {
        let service = FakeReminderService()
        let taskCount = GetOpenTasksTool.maxListedTasks + 5
        service.tasksResult = .success(
            (1...taskCount).map { makeTask(title: "Aufgabe \($0)") }
        )

        let output = try await makeTool(service: service).call(arguments: .init())

        let bulletCount = output.components(separatedBy: "• ").count - 1
        XCTAssertEqual(bulletCount, GetOpenTasksTool.maxListedTasks)
        XCTAssertTrue(output.contains("und 5 weitere offene Aufgaben"))
    }

    func testEmptyTitleGetsPlaceholder() async throws {
        let service = FakeReminderService()
        service.tasksResult = .success([makeTask(title: "")])

        let output = try await makeTool(service: service).call(arguments: .init())

        XCTAssertTrue(output.contains("(Ohne Titel)"))
    }
}
