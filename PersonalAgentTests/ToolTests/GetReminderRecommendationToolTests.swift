import XCTest
@testable import PersonalAgent

final class GetReminderRecommendationToolTests: XCTestCase {
    private let calendar = utcCalendar()
    /// Sunday 2026-08-30, 14:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_788_098_400)

    private struct Environment {
        let tool: GetReminderRecommendationTool
        let reminders: FakeReminderService
        let calendarFake: FakeCalendarService
        let taskRepository: TaskRepository
        let eventRepository: TaskEventRepository
        let recommendationRepository: RecommendationRepository
        let outcomeRepository: RecommendationOutcomeRepository
    }

    private func makeEnvironment(authorized: Bool = false) async throws -> Environment {
        let reminders = FakeReminderService()
        reminders.fullAccess = authorized
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await provider.preparedDatabase()
        let syncService = TaskSyncService(reminderService: reminders, databaseProvider: provider)
        let calendarFake = FakeCalendarService()
        let fixedNow = now
        let tool = GetReminderRecommendationTool(
            databaseProvider: provider,
            syncService: syncService,
            calendarService: calendarFake,
            calendar: calendar,
            now: { fixedNow }
        )
        return Environment(
            tool: tool,
            reminders: reminders,
            calendarFake: calendarFake,
            taskRepository: TaskRepository(database: database),
            eventRepository: TaskEventRepository(database: database),
            recommendationRepository: RecommendationRepository(database: database),
            outcomeRepository: RecommendationOutcomeRepository(database: database)
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

    private func utcDate(month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func testUnknownTitleListsOpenTasks() async throws {
        let environment = try await makeEnvironment()
        try await seed(environment, task: makeTask(title: "Steuer"))

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Wäsche"))

        XCTAssertTrue(output.contains("Keine Aufgabe"))
        XCTAssertTrue(output.contains("Steuer"))
        XCTAssertTrue(environment.calendarFake.recordedQueries.isEmpty)
    }

    func testAmbiguousTitleAsksForPrecision() async throws {
        let environment = try await makeEnvironment()
        try await seed(environment, task: makeTask(title: "Steuer 2025"))
        try await seed(environment, task: makeTask(title: "Steuer 2026"))

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Steuer"))

        XCTAssertTrue(output.contains("Mehrere Aufgaben"))
    }

    func testCompletedTaskNeedsNoReminder() async throws {
        let environment = try await makeEnvironment()
        try await seed(
            environment,
            task: makeTask(title: "Fertig", completionDate: now.addingTimeInterval(-3600), isCompleted: true)
        )

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Fertig"))

        XCTAssertTrue(output.contains("bereits erledigt"))
        XCTAssertTrue(environment.calendarFake.recordedQueries.isEmpty)
    }

    func testQueriesOneWakingWindowPerHorizonDay() async throws {
        let environment = try await makeEnvironment()
        try await seed(environment, task: makeTask(title: "Bericht"))
        environment.calendarFake.freeTimeResultsQueue = [[], [], []]

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Bericht"))

        XCTAssertTrue(output.contains("keine passenden freien Zeiträume"))
        XCTAssertEqual(environment.calendarFake.recordedQueries.count, 3)
        // Today starts at now (14:00), not at the waking-window start.
        XCTAssertEqual(environment.calendarFake.recordedQueries[0].from, now)
        XCTAssertEqual(environment.calendarFake.recordedQueries[0].to, utcDate(month: 8, day: 30, hour: 21))
        XCTAssertEqual(environment.calendarFake.recordedQueries[1].from, utcDate(month: 8, day: 31, hour: 8))
        XCTAssertEqual(environment.calendarFake.recordedQueries[2].to, utcDate(month: 9, day: 1, hour: 21))
    }

    func testHappyPathRecommendationText() async throws {
        let environment = try await makeEnvironment()
        let taskID = UUID()
        let task = makeTask(id: taskID, title: "Bericht", dueDate: utcDate(month: 9, day: 1, hour: 18))
        let events = [
            makeEvent(taskID: taskID, type: .created, timestamp: now.addingTimeInterval(-10 * 86_400)),
            makeEvent(taskID: taskID, type: .postponed, timestamp: now.addingTimeInterval(-2 * 86_400)),
            makeEvent(taskID: taskID, type: .postponed, timestamp: now.addingTimeInterval(-86_400)),
        ]
        try await seed(environment, task: task, events: events)
        environment.calendarFake.freeTimeResultsQueue = [
            [],
            [DateInterval(start: utcDate(month: 8, day: 31, hour: 18), end: utcDate(month: 8, day: 31, hour: 20))],
            [],
        ]

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Bericht"))

        XCTAssertTrue(output.contains("Empfehlung für „Bericht“"))
        XCTAssertTrue(output.contains("Montag, 31.08.2026, 18:00 Uhr"))
        XCTAssertTrue(output.contains("Konfidenz: 53 %"))
        XCTAssertTrue(output.contains("Frist rückt näher"))
        XCTAssertTrue(output.contains("häufig aufgeschoben"))
        XCTAssertTrue(output.contains("Kalender ist frei"))
        XCTAssertTrue(output.contains(TaskStatisticsFormatter.lowDataHint))
    }

    func testCalendarDeniedGivesFactualError() async throws {
        let environment = try await makeEnvironment()
        try await seed(environment, task: makeTask(title: "Bericht"))
        environment.calendarFake.accessResult = .failure(CalendarServiceError.accessDenied)

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Bericht"))

        XCTAssertTrue(output.contains("Fehler beim Kalenderzugriff"))
    }

    func testSyncRunsBeforeReadingWhenAuthorized() async throws {
        let environment = try await makeEnvironment(authorized: true)
        environment.reminders.allTasksResult = .success([])

        _ = try await environment.tool.call(arguments: .init(taskTitle: "Egal"))

        XCTAssertEqual(environment.reminders.fetchAllCallCount, 1)
    }

    // MARK: - intervention loop, persistence, outcome learning

    func testInterventionModePicksMostUrgentTask() async throws {
        let environment = try await makeEnvironment()
        try await seed(environment, task: makeTask(title: "Ruhig"))
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
        environment.calendarFake.freeTimeResultsQueue = [
            [],
            [DateInterval(start: utcDate(month: 8, day: 31, hour: 18), end: utcDate(month: 8, day: 31, hour: 20))],
            [],
        ]

        let output = try await environment.tool.call(arguments: .init(taskTitle: nil))

        XCTAssertTrue(output.contains("größten Handlungsbedarf"))
        XCTAssertTrue(output.contains("Empfehlung für „Zappelig“"))
        XCTAssertFalse(output.contains("Empfehlung für „Ruhig“"))
    }

    func testInterventionModeSaysNoNeedForCalmTasks() async throws {
        let environment = try await makeEnvironment()
        try await seed(environment, task: makeTask(title: "Ruhig"))

        let output = try await environment.tool.call(arguments: .init(taskTitle: nil))

        XCTAssertTrue(output.contains("Zurzeit braucht keine Aufgabe"))
        XCTAssertTrue(environment.calendarFake.recordedQueries.isEmpty)
    }

    func testShownRecommendationIsPersisted() async throws {
        let environment = try await makeEnvironment()
        let taskID = UUID()
        try await seed(
            environment,
            task: makeTask(id: taskID, title: "Bericht", dueDate: utcDate(month: 9, day: 1, hour: 18))
        )
        environment.calendarFake.freeTimeResultsQueue = [
            [],
            [DateInterval(start: utcDate(month: 8, day: 31, hour: 18), end: utcDate(month: 8, day: 31, hour: 20))],
            [],
        ]

        _ = try await environment.tool.call(arguments: .init(taskTitle: "Bericht"))

        let stored = try await environment.recommendationRepository.recommendations(forTaskID: taskID)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].recommendedTime, utcDate(month: 8, day: 31, hour: 18))
        XCTAssertEqual(stored[0].confidence, 0.525, accuracy: 0.0001)
        XCTAssertEqual(stored[0].createdAt, now)
        XCTAssertFalse(stored[0].reasonCodes.isEmpty)
    }

    func testPriorRejectionsLowerShownConfidence() async throws {
        let environment = try await makeEnvironment()
        let taskID = UUID()
        try await seed(
            environment,
            task: makeTask(id: taskID, title: "Bericht", dueDate: utcDate(month: 9, day: 1, hour: 18))
        )
        for _ in 0..<3 {
            let old = makeStoredRecommendation(
                taskID: taskID,
                recommendedTime: now.addingTimeInterval(-9 * 86_400),
                createdAt: now.addingTimeInterval(-10 * 86_400)
            )
            try await environment.recommendationRepository.insert(old)
            try await environment.outcomeRepository.insert(
                RecommendationOutcome(recommendationID: old.id, outcome: .rejected, timestamp: old.createdAt)
            )
        }
        environment.calendarFake.freeTimeResultsQueue = [
            [],
            [DateInterval(start: utcDate(month: 8, day: 31, hour: 18), end: utcDate(month: 8, day: 31, hour: 20))],
            [],
        ]

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Bericht"))

        // Base 0.525 shifted by -0.1 from three rejections → 43 %.
        XCTAssertTrue(output.contains("Konfidenz: 43 %"))
    }

    func testEffectivenessLineAppears() async throws {
        let environment = try await makeEnvironment()
        let taskID = UUID()
        let fireDate = now.addingTimeInterval(-2 * 86_400)
        let events = [
            makeEvent(
                taskID: taskID,
                type: .reminderScheduled,
                timestamp: fireDate.addingTimeInterval(-3600),
                metadata: ["notificationID": "task-x", "fireDate": fireDate.formatted(.iso8601)]
            ),
            makeEvent(taskID: taskID, type: .completed, timestamp: fireDate.addingTimeInterval(2 * 3600)),
            makeEvent(taskID: taskID, type: .reopened, timestamp: fireDate.addingTimeInterval(3 * 3600)),
        ]
        try await seed(environment, task: makeTask(id: taskID, title: "Projekt"), events: events)
        environment.calendarFake.freeTimeResultsQueue = [
            [],
            [DateInterval(start: utcDate(month: 8, day: 31, hour: 18), end: utcDate(month: 8, day: 31, hour: 20))],
            [],
        ]

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Projekt"))

        XCTAssertTrue(output.contains("Frühere Erinnerungen: 1 von 1"))
    }

    func testRecurrenceObservationAppears() async throws {
        let environment = try await makeEnvironment()
        let taskID = UUID()
        var events: [TaskEvent] = []
        for week in 0..<4 {
            let completion = utcDate(month: 6, day: 1 + 7 * week, hour: 19)
            events.append(makeEvent(taskID: taskID, type: .completed, timestamp: completion))
            events.append(makeEvent(taskID: taskID, type: .reopened, timestamp: completion.addingTimeInterval(3600)))
        }
        try await seed(environment, task: makeTask(id: taskID, title: "Wochenbericht"), events: events)
        environment.calendarFake.freeTimeResultsQueue = [
            [],
            [DateInterval(start: utcDate(month: 8, day: 31, hour: 18), end: utcDate(month: 8, day: 31, hour: 20))],
            [],
        ]

        let output = try await environment.tool.call(arguments: .init(taskTitle: "Wochenbericht"))

        XCTAssertTrue(output.contains("Beobachtung"))
        XCTAssertTrue(output.contains("wöchentlich"))
        XCTAssertTrue(output.contains("Apple Erinnerungen"))
    }
}
