import XCTest
@testable import PersonalAgent

@MainActor
final class ScheduleNotificationToolTests: XCTestCase {
    private let calendar = utcCalendar()
    /// Sunday 2026-08-30, 14:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_788_098_400)

    private struct Environment {
        let tool: ScheduleNotificationTool
        let reminders: FakeReminderService
        let notifications: FakeNotificationService
        let center: NotificationProposalCenter
        let taskRepository: TaskRepository
    }

    private func makeEnvironment(authorized: Bool = false) async throws -> Environment {
        let reminders = FakeReminderService()
        reminders.fullAccess = authorized
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await provider.preparedDatabase()
        let syncService = TaskSyncService(reminderService: reminders, databaseProvider: provider)
        let notifications = FakeNotificationService()
        let fixedNow = now
        let center = NotificationProposalCenter(
            notificationService: notifications,
            databaseProvider: provider,
            calendar: calendar,
            now: { fixedNow }
        )
        let tool = ScheduleNotificationTool(
            databaseProvider: provider,
            syncService: syncService,
            proposalCenter: center,
            calendar: calendar,
            now: { fixedNow }
        )
        return Environment(
            tool: tool,
            reminders: reminders,
            notifications: notifications,
            center: center,
            taskRepository: TaskRepository(database: database)
        )
    }

    private func args(
        message: String = "Müll rausbringen",
        taskTitle: String? = nil,
        day: Int = 1,
        hour: Int = 18,
        minute: Int? = nil,
        minutesFromNow: Int? = nil
    ) -> ScheduleNotificationTool.Arguments {
        ScheduleNotificationTool.Arguments(
            message: message,
            taskTitle: taskTitle,
            daysFromToday: day,
            hour: hour,
            minute: minute,
            minutesFromNow: minutesFromNow
        )
    }

    private func utcDate(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
    }

    func testValidationRejectsBadArguments() async throws {
        let environment = try await makeEnvironment()
        let tool = environment.tool

        let dayOutput = try await tool.call(arguments: args(day: -1))
        XCTAssertTrue(dayOutput.contains("Ungültiger Tag"))

        let hourOutput = try await tool.call(arguments: args(hour: 24))
        XCTAssertTrue(hourOutput.contains("Ungültige Stunde"))

        let minuteOutput = try await tool.call(arguments: args(minute: 60))
        XCTAssertTrue(minuteOutput.contains("Ungültige Minute"))

        let emptyOutput = try await tool.call(arguments: args(message: "   "))
        XCTAssertTrue(emptyOutput.contains("woran erinnert"))

        let longOutput = try await tool.call(
            arguments: args(message: String(repeating: "a", count: 201))
        )
        XCTAssertTrue(longOutput.contains("zu lang"))

        let pastOutput = try await tool.call(arguments: args(day: 0, hour: 8))
        XCTAssertTrue(pastOutput.contains("Vergangenheit"))

        XCTAssertNil(environment.center.pending)
        XCTAssertTrue(environment.notifications.scheduled.isEmpty)
    }

    func testAdhocProposalIsDepositedButNothingScheduled() async throws {
        let environment = try await makeEnvironment()

        let output = try await environment.tool.call(arguments: args())

        XCTAssertTrue(output.contains("Vorschlag erstellt"))
        XCTAssertTrue(output.contains("Montag, 31.08.2026"))
        XCTAssertTrue(output.contains("18:00"))
        XCTAssertTrue(output.contains("noch nichts geplant"))

        let pending = environment.center.pending
        XCTAssertNotNil(pending)
        XCTAssertNil(pending?.taskID)
        XCTAssertEqual(pending?.body, "Müll rausbringen")
        XCTAssertEqual(pending?.notificationTitle, "Erinnerung")
        XCTAssertEqual(pending?.fireDate, utcDate(day: 31, hour: 18))
        XCTAssertTrue(pending?.notificationID.hasPrefix("adhoc-") ?? false)
        // The mutation itself must not have happened.
        XCTAssertTrue(environment.notifications.scheduled.isEmpty)
    }

    func testTaskBoundProposalResolvesStoredTask() async throws {
        let environment = try await makeEnvironment()
        let task = makeTask(title: "Steuer")
        try await environment.taskRepository.upsert(task, updatedAt: now)

        let output = try await environment.tool.call(arguments: args(taskTitle: "Steuer"))

        XCTAssertTrue(output.contains("Vorschlag erstellt"))
        XCTAssertEqual(environment.center.pending?.taskID, task.id)
        XCTAssertEqual(environment.center.pending?.notificationTitle, "Erinnerung: Steuer")
        XCTAssertEqual(
            environment.center.pending?.notificationID,
            NotificationIdentifier.forTask(task.id)
        )
    }

    func testUnknownTaskTitleIsRejected() async throws {
        let environment = try await makeEnvironment()
        try await environment.taskRepository.upsert(makeTask(title: "Steuer"), updatedAt: now)

        let output = try await environment.tool.call(arguments: args(taskTitle: "Wäsche"))

        XCTAssertTrue(output.contains("Keine Aufgabe"))
        XCTAssertNil(environment.center.pending)
    }

    func testAmbiguousTaskTitleAsksForPrecision() async throws {
        let environment = try await makeEnvironment()
        try await environment.taskRepository.upsert(makeTask(title: "Steuer 2025"), updatedAt: now)
        try await environment.taskRepository.upsert(makeTask(title: "Steuer 2026"), updatedAt: now)

        let output = try await environment.tool.call(arguments: args(taskTitle: "Steuer"))

        XCTAssertTrue(output.contains("Mehrere Aufgaben"))
        XCTAssertNil(environment.center.pending)
    }

    func testSecondProposalWhileOnePendingIsRejected() async throws {
        let environment = try await makeEnvironment()

        _ = try await environment.tool.call(arguments: args(message: "Erster"))
        let output = try await environment.tool.call(arguments: args(message: "Zweiter"))

        XCTAssertTrue(output.contains("wartet bereits"))
        XCTAssertEqual(environment.center.pending?.body, "Erster")
    }

    func testSyncRunsForTaskResolutionWhenAuthorized() async throws {
        let environment = try await makeEnvironment(authorized: true)
        environment.reminders.allTasksResult = .success([])
        try await environment.taskRepository.upsert(makeTask(title: "Steuer"), updatedAt: now)

        _ = try await environment.tool.call(arguments: args(taskTitle: "Steuer"))

        XCTAssertEqual(environment.reminders.fetchAllCallCount, 1)
    }

    // MARK: - Relative times ("in 3 Minuten")

    func testRelativeMinutesAreComputedByTheApp() async throws {
        let environment = try await makeEnvironment()

        // Absolute fields are ignored when minutesFromNow is set, even if invalid.
        let output = try await environment.tool.call(
            arguments: args(message: "Eier fertig", day: 99, hour: 99, minutesFromNow: 3)
        )

        XCTAssertTrue(output.contains("Vorschlag erstellt"))
        XCTAssertEqual(environment.center.pending?.fireDate, now.addingTimeInterval(180))
        XCTAssertTrue(environment.notifications.scheduled.isEmpty)
    }

    func testRelativeMinutesOutOfRangeAreRejected() async throws {
        let environment = try await makeEnvironment()

        let zero = try await environment.tool.call(arguments: args(minutesFromNow: 0))
        let tooFar = try await environment.tool.call(arguments: args(minutesFromNow: 1441))

        XCTAssertTrue(zero.contains("minutesFromNow"))
        XCTAssertTrue(tooFar.contains("minutesFromNow"))
        XCTAssertNil(environment.center.pending)
    }
}
