import Foundation
@testable import PersonalAgent

/// Fixed data shared by the agent test environment and the scenarios.
/// Kept outside the main-actor environment so nonisolated scenario tables can
/// reference it.
enum AgentTestData {
    /// Sunday 2026-08-30, 14:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_788_098_400)

    /// Seeded tasks: one overdue, one due tomorrow 10:00, one without due date.
    static let overdueTitle = "Steuererklärung abgeben"
    static let dueTomorrowTitle = "Zahnarzt anrufen"
    static let undatedTitle = "Keller aufräumen"
}

/// The complete agent stack over fakes — the app's tool registry, in-memory
/// SQLite, fixed clock — shared by the controller tests and the provider
/// evaluation, so every provider is tested against identical tools and data.
@MainActor
struct AgentTestEnvironment {
    let now: Date
    let calendar: Calendar
    let reminders: FakeReminderService
    let calendarService: FakeCalendarService
    let notifications: FakeNotificationService
    let databaseProvider: DatabaseProvider
    let syncService: TaskSyncService
    let notificationCenter: NotificationProposalCenter
    let reminderCreationCenter: ReminderCreationCenter
    let registry: ToolRegistry
    let contextBuilder: AgentContextBuilder

    static func make(
        now: Date = AgentTestData.now,
        calendar: Calendar = utcCalendar(),
        seeded: Bool = true
    ) async throws -> AgentTestEnvironment {
        let reminders = FakeReminderService()
        let calendarService = FakeCalendarService()
        let notifications = FakeNotificationService()
        let database = SQLiteDatabase()
        let databaseProvider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await databaseProvider.preparedDatabase()
        let syncService = TaskSyncService(reminderService: reminders, databaseProvider: databaseProvider)
        let fixedNow = now
        let clock: @Sendable () -> Date = { fixedNow }

        if seeded {
            let tasks = [
                makeTask(
                    title: AgentTestData.overdueTitle,
                    dueDate: now.addingTimeInterval(-2 * 86_400),
                    creationDate: now.addingTimeInterval(-9 * 86_400)
                ),
                makeTask(
                    title: AgentTestData.dueTomorrowTitle,
                    dueDate: now.addingTimeInterval(20 * 3_600),
                    creationDate: now.addingTimeInterval(-3 * 86_400)
                ),
                makeTask(title: AgentTestData.undatedTitle, creationDate: now.addingTimeInterval(-6 * 86_400)),
            ]
            reminders.tasksResult = .success(tasks)
            reminders.allTasksResult = .success(tasks)
            reminders.fullAccess = true
            // The calendar fake answers every free-time query with tomorrow 18:00–19:30.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            let tomorrowEvening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow)!
            calendarService.freeTimeResult = .success([DateInterval(start: tomorrowEvening, duration: 5_400)])
            // Local history mirrors the reminders (context block, statistics, duplicates check).
            try await syncService.synchronize(now: now)
        }

        let notificationCenter = NotificationProposalCenter(
            notificationService: notifications,
            databaseProvider: databaseProvider,
            calendar: calendar,
            now: clock
        )
        let reminderCreationCenter = ReminderCreationCenter(
            reminderService: reminders,
            syncService: syncService,
            calendar: calendar
        )
        let registry = ToolRegistry(entries: [
            ToolRegistry.entry(GetOpenTasksTool(reminderService: reminders, now: clock)),
            ToolRegistry.entry(
                GetTaskStatisticsTool(
                    databaseProvider: databaseProvider,
                    syncService: syncService,
                    calendar: calendar,
                    now: clock
                )
            ),
            ToolRegistry.entry(FindFreeTimeTool(calendarService: calendarService, calendar: calendar, now: clock)),
            ToolRegistry.entry(
                GetReminderRecommendationTool(
                    databaseProvider: databaseProvider,
                    syncService: syncService,
                    calendarService: calendarService,
                    calendar: calendar,
                    now: clock
                )
            ),
            ToolRegistry.entry(
                CreateReminderTool(
                    proposalCenter: reminderCreationCenter,
                    databaseProvider: databaseProvider,
                    syncService: syncService,
                    calendar: calendar,
                    now: clock
                )
            ),
            ToolRegistry.entry(
                ScheduleNotificationTool(
                    databaseProvider: databaseProvider,
                    syncService: syncService,
                    proposalCenter: notificationCenter,
                    calendar: calendar,
                    now: clock
                )
            ),
        ])
        let contextBuilder = AgentContextBuilder(databaseProvider: databaseProvider, calendar: calendar, now: clock)

        return AgentTestEnvironment(
            now: now,
            calendar: calendar,
            reminders: reminders,
            calendarService: calendarService,
            notifications: notifications,
            databaseProvider: databaseProvider,
            syncService: syncService,
            notificationCenter: notificationCenter,
            reminderCreationCenter: reminderCreationCenter,
            registry: registry,
            contextBuilder: contextBuilder
        )
    }

    /// The controller exactly as `AppContainer` wires it, with the given provider.
    func makeController(model: any LanguageModel, instructions: String = AgentInstructions.text) -> AgentController {
        let contextBuilder = contextBuilder
        return AgentController(
            model: model,
            registry: registry,
            instructions: instructions,
            contextPrefix: { await contextBuilder.promptPrefix() }
        )
    }

    /// Clears pending proposals between scenarios without executing them.
    func declinePendingProposals() async {
        if reminderCreationCenter.pending != nil {
            _ = reminderCreationCenter.declinePending()
        }
        if notificationCenter.pending != nil {
            _ = await notificationCenter.declinePending()
        }
    }
}
