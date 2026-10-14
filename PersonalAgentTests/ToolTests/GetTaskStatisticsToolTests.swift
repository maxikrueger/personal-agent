import XCTest
@testable import PersonalAgent

final class GetTaskStatisticsToolTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Environment {
        let tool: GetTaskStatisticsTool
        let reminders: FakeReminderService
        let taskRepository: TaskRepository
        let eventRepository: TaskEventRepository
    }

    private func makeEnvironment(authorized: Bool = false) async throws -> Environment {
        let reminders = FakeReminderService()
        reminders.fullAccess = authorized
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await provider.preparedDatabase()
        let syncService = TaskSyncService(reminderService: reminders, databaseProvider: provider)
        let fixedNow = now
        let tool = GetTaskStatisticsTool(
            databaseProvider: provider,
            syncService: syncService,
            calendar: utcCalendar(),
            now: { fixedNow }
        )
        return Environment(
            tool: tool,
            reminders: reminders,
            taskRepository: TaskRepository(database: database),
            eventRepository: TaskEventRepository(database: database)
        )
    }

    private func seed(
        _ environment: Environment,
        task: PersonalAgent.Task,
        events: [TaskEvent] = []
    ) async throws {
        try await environment.taskRepository.upsert(task, updatedAt: now)
        for event in events {
            try await environment.eventRepository.insert(event)
        }
    }

    func testEmptyDatabaseReturnsNoDataMessage() async throws {
        let environment = try await makeEnvironment()

        let output = try await environment.tool.call(arguments: .init(taskTitle: nil))

        XCTAssertTrue(output.contains("keine Verlaufsdaten"))
    }

    func testUnknownTitleListsOpenTasks() async throws {
        let environment = try await makeEnvironment()
        try await seed(environment, task: makeTask(title: "Steuer"))

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Wäsche"))

        XCTAssertTrue(output.contains("Keine Aufgabe"))
        XCTAssertTrue(output.contains("Steuer"))
    }

    func testAmbiguousQueryAsksForPrecision() async throws {
        let environment = try await makeEnvironment()
        try await seed(environment, task: makeTask(title: "Steuer 2025"))
        try await seed(environment, task: makeTask(title: "Steuer 2026"))

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Steuer"))

        XCTAssertTrue(output.contains("Mehrere Aufgaben"))
        XCTAssertTrue(output.contains("Steuer 2025"))
        XCTAssertTrue(output.contains("Steuer 2026"))
    }

    func testExactMatchBeatsSubstringMatches() async throws {
        let environment = try await makeEnvironment()
        try await seed(environment, task: makeTask(title: "Steuer"))
        try await seed(environment, task: makeTask(title: "Steuererklärung"))

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Steuer"))

        XCTAssertTrue(output.contains("Statistik für „Steuer“"))
        XCTAssertFalse(output.contains("Mehrere Aufgaben"))
    }

    func testDetailContainsDeterministicNumbers() async throws {
        let environment = try await makeEnvironment()
        let taskID = UUID()
        let oldDue = now.addingTimeInterval(-5 * 86_400)
        let newDue = now.addingTimeInterval(-2 * 86_400)
        let task = makeTask(id: taskID, title: "Bericht", dueDate: newDue)
        let events = [
            makeEvent(taskID: taskID, type: .created, timestamp: now.addingTimeInterval(-10 * 86_400)),
            makeEvent(
                taskID: taskID,
                type: .postponed,
                timestamp: now.addingTimeInterval(-4 * 86_400),
                metadata: [
                    "field": "dueDate",
                    "oldDueDate": oldDue.formatted(.iso8601),
                    "newDueDate": newDue.formatted(.iso8601),
                ]
            ),
            makeEvent(
                taskID: taskID,
                type: .postponed,
                timestamp: now.addingTimeInterval(-3 * 86_400),
                metadata: ["field": "dueDate"]
            ),
        ]
        try await seed(environment, task: task, events: events)

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Bericht"))

        XCTAssertTrue(output.contains("Aufschiebungen: 2"))
        XCTAssertTrue(output.contains("aktuell überfällig"))
        XCTAssertTrue(output.contains("Prokrastinations-Score"))
        XCTAssertTrue(output.contains(TaskStatisticsFormatter.lowDataHint))
    }

    func testOverviewSortsByProcrastinationScoreAndSkipsCompleted() async throws {
        let environment = try await makeEnvironment()
        let hecticID = UUID()
        try await seed(
            environment,
            task: makeTask(id: hecticID, title: "Zappelig", dueDate: now.addingTimeInterval(-86_400)),
            events: (1...3).map { index in
                makeEvent(
                    taskID: hecticID,
                    type: .postponed,
                    timestamp: now.addingTimeInterval(Double(-index) * 86_400)
                )
            }
        )
        try await seed(environment, task: makeTask(title: "Ruhig", dueDate: now.addingTimeInterval(86_400)))
        try await seed(
            environment,
            task: makeTask(title: "Fertig", completionDate: now.addingTimeInterval(-3600), isCompleted: true)
        )

        let output = try await environment.tool.call(arguments: .init(taskTitle: nil))

        XCTAssertTrue(output.contains("Statistik-Übersicht"))
        XCTAssertFalse(output.contains("Fertig"))
        let hecticIndex = output.range(of: "Zappelig")!.lowerBound
        let calmIndex = output.range(of: "Ruhig")!.lowerBound
        XCTAssertLessThan(hecticIndex, calmIndex)
        XCTAssertTrue(output.contains("überfällig"))
    }

    func testSyncRunsBeforeReadingWhenAuthorized() async throws {
        let environment = try await makeEnvironment(authorized: true)
        environment.reminders.allTasksResult = .success([])

        _ = try await environment.tool.call(arguments: .init(taskTitle: nil))

        XCTAssertEqual(environment.reminders.fetchAllCallCount, 1)
    }

    func testSyncIsSkippedWithoutAccess() async throws {
        let environment = try await makeEnvironment(authorized: false)

        _ = try await environment.tool.call(arguments: .init(taskTitle: nil))

        XCTAssertEqual(environment.reminders.fetchAllCallCount, 0)
    }

    func testFormatterHelpers() {
        XCTAssertEqual(TaskStatisticsFormatter.percentText(0.667), "67 %")
        XCTAssertEqual(TaskStatisticsFormatter.percentText(0), "0 %")
        XCTAssertEqual(TaskStatisticsFormatter.durationText(300), "5 Minuten")
        XCTAssertEqual(TaskStatisticsFormatter.durationText(3600), "1 Stunde")
        XCTAssertEqual(TaskStatisticsFormatter.durationText(14_400), "4 Stunden")
        XCTAssertEqual(TaskStatisticsFormatter.durationText(86_400), "1 Tag")
        XCTAssertEqual(TaskStatisticsFormatter.durationText(2.5 * 86_400), "3 Tage")
        XCTAssertEqual(TaskStatisticsFormatter.durationText(-14_400), "4 Stunden")
        XCTAssertEqual(TaskStatisticsFormatter.windowText(.evening), "abends")
        XCTAssertEqual(TaskStatisticsFormatter.patternText(.weekly), "wöchentlich")
    }

    func testCompletionCountUsesSingularForOne() {
        XCTAssertEqual(TaskStatisticsFormatter.completionsText(1), "1 Erledigung")
        XCTAssertEqual(TaskStatisticsFormatter.completionsText(0), "0 Erledigungen")
        XCTAssertEqual(TaskStatisticsFormatter.completionsText(3), "3 Erledigungen")
    }
}
