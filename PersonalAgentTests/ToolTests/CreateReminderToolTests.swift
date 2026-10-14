import XCTest
@testable import PersonalAgent

@MainActor
final class CreateReminderToolTests: XCTestCase {
    private let calendar = utcCalendar()
    /// Sunday 2026-08-30, 14:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_788_098_400)

    private struct Environment {
        let tool: CreateReminderTool
        let center: ReminderCreationCenter
        let reminders: FakeReminderService
        let taskRepository: TaskRepository
    }

    private func makeEnvironment() async throws -> Environment {
        let reminders = FakeReminderService()
        reminders.fullAccess = false
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await provider.preparedDatabase()
        let syncService = TaskSyncService(reminderService: reminders, databaseProvider: provider)
        let center = ReminderCreationCenter(
            reminderService: reminders,
            syncService: syncService,
            calendar: calendar
        )
        let fixedNow = now
        let tool = CreateReminderTool(
            proposalCenter: center,
            databaseProvider: provider,
            syncService: syncService,
            calendar: calendar,
            now: { fixedNow }
        )
        return Environment(
            tool: tool,
            center: center,
            reminders: reminders,
            taskRepository: TaskRepository(database: database)
        )
    }

    private func args(
        title: String = "Steuer 2027",
        notes: String? = nil,
        dueDays: Int? = nil,
        dueHour: Int? = nil
    ) -> CreateReminderTool.Arguments {
        CreateReminderTool.Arguments(
            title: title,
            notes: notes,
            dueDaysFromToday: dueDays,
            dueHour: dueHour
        )
    }

    private func utcDate(month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func testValidationRejectsBadArguments() async throws {
        let environment = try await makeEnvironment()
        let tool = environment.tool

        let emptyTitle = try await tool.call(arguments: args(title: "   "))
        XCTAssertTrue(emptyTitle.contains("Titel"))

        let longTitle = try await tool.call(arguments: args(title: String(repeating: "a", count: 101)))
        XCTAssertTrue(longTitle.contains("zu lang"))

        let longNotes = try await tool.call(arguments: args(notes: String(repeating: "n", count: 501)))
        XCTAssertTrue(longNotes.contains("Notiz"))

        let badDay = try await tool.call(arguments: args(dueDays: -1))
        XCTAssertTrue(badDay.contains("Ungültiger Tag"))

        let badHour = try await tool.call(arguments: args(dueDays: 1, dueHour: 24))
        XCTAssertTrue(badHour.contains("Ungültige Stunde"))

        XCTAssertNil(environment.center.pending)
        XCTAssertTrue(environment.reminders.createdReminders.isEmpty)
    }

    func testProposalWithDueDateIsDepositedButNothingCreated() async throws {
        let environment = try await makeEnvironment()

        let output = try await environment.tool.call(arguments: args(dueDays: 1, dueHour: 18))

        XCTAssertTrue(output.contains("Vorschlag erstellt"))
        XCTAssertTrue(output.contains("Montag, 31.08.2026"))
        XCTAssertTrue(output.contains("noch nichts angelegt"))
        XCTAssertEqual(environment.center.pending?.title, "Steuer 2027")
        XCTAssertEqual(environment.center.pending?.dueDate, utcDate(month: 8, day: 31, hour: 18))
        // The mutation itself must not have happened.
        XCTAssertTrue(environment.reminders.createdReminders.isEmpty)
    }

    func testProposalWithoutDueDate() async throws {
        let environment = try await makeEnvironment()

        let output = try await environment.tool.call(arguments: args())

        XCTAssertFalse(output.contains("fällig"))
        XCTAssertNotNil(environment.center.pending)
        XCTAssertNil(environment.center.pending?.dueDate)
    }

    func testDefaultDueHourIsApplied() async throws {
        let environment = try await makeEnvironment()

        _ = try await environment.tool.call(arguments: args(dueDays: 2))

        XCTAssertEqual(environment.center.pending?.dueDate, utcDate(month: 9, day: 1, hour: 9))
    }

    func testDuplicateOpenTitleIsRejectedCaseInsensitively() async throws {
        let environment = try await makeEnvironment()
        try await environment.taskRepository.upsert(makeTask(title: "Steuer 2027"), updatedAt: now)

        let output = try await environment.tool.call(arguments: args(title: "steuer 2027"))

        XCTAssertTrue(output.contains("bereits eine offene Aufgabe"))
        XCTAssertNil(environment.center.pending)
    }

    func testCompletedTaskWithSameTitleDoesNotBlock() async throws {
        let environment = try await makeEnvironment()
        try await environment.taskRepository.upsert(
            makeTask(title: "Steuer 2027", completionDate: now.addingTimeInterval(-3600), isCompleted: true),
            updatedAt: now
        )

        let output = try await environment.tool.call(arguments: args())

        XCTAssertTrue(output.contains("Vorschlag erstellt"))
        XCTAssertNotNil(environment.center.pending)
    }

    func testSecondProposalWhilePendingIsRejected() async throws {
        let environment = try await makeEnvironment()

        _ = try await environment.tool.call(arguments: args(title: "Erste"))
        let output = try await environment.tool.call(arguments: args(title: "Zweite"))

        XCTAssertTrue(output.contains("wartet bereits"))
        XCTAssertEqual(environment.center.pending?.title, "Erste")
    }
}
