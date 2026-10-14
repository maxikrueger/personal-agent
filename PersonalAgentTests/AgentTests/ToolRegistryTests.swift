import XCTest
@testable import PersonalAgent

@MainActor
final class ToolRegistryTests: XCTestCase {
    private func makeRegistry() async throws -> ToolRegistry {
        let reminders = FakeReminderService()
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        let syncService = TaskSyncService(reminderService: reminders, databaseProvider: provider)
        let calendarService = FakeCalendarService()
        let notificationCenter = NotificationProposalCenter(
            notificationService: FakeNotificationService(),
            databaseProvider: provider
        )
        let reminderCenter = ReminderCreationCenter(
            reminderService: reminders,
            syncService: syncService
        )
        return ToolRegistry(entries: [
            ToolRegistry.entry(GetOpenTasksTool(reminderService: reminders)),
            ToolRegistry.entry(GetTaskStatisticsTool(databaseProvider: provider, syncService: syncService)),
            ToolRegistry.entry(FindFreeTimeTool(calendarService: calendarService)),
            ToolRegistry.entry(
                GetReminderRecommendationTool(
                    databaseProvider: provider,
                    syncService: syncService,
                    calendarService: calendarService
                )
            ),
            ToolRegistry.entry(
                CreateReminderTool(
                    proposalCenter: reminderCenter,
                    databaseProvider: provider,
                    syncService: syncService
                )
            ),
            ToolRegistry.entry(
                ScheduleNotificationTool(
                    databaseProvider: provider,
                    syncService: syncService,
                    proposalCenter: notificationCenter
                )
            ),
        ])
    }

    func testRegistryListsAllToolsWithNames() async throws {
        let registry = try await makeRegistry()

        XCTAssertEqual(registry.toolNames, [
            "getOpenTasks",
            "getTaskStatistics",
            "findFreeTime",
            "getReminderRecommendation",
            "createReminder",
            "scheduleNotification",
        ])
        XCTAssertEqual(registry.tools.count, 6)
    }

    func testMutationToolsAreDeclared() async throws {
        let registry = try await makeRegistry()

        XCTAssertEqual(registry.mutationToolNames, ["createReminder", "scheduleNotification"])
        XCTAssertEqual(registry.entry(named: "findFreeTime")?.access, .readOnly)
        XCTAssertEqual(registry.entry(named: "createReminder")?.access, .mutation)
        XCTAssertNil(registry.entry(named: "searchWeb"))
    }
}
