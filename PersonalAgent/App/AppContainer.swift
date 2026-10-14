import Foundation

/// Composition root: the only place where concrete implementations are wired together.
@MainActor
final class AppContainer {
    let agentViewModel: AgentViewModel
    let insightsViewModel: InsightsViewModel
    private let syncService: TaskSyncService
    /// Retained so the notification delegate stays alive for the app's lifetime.
    private let notificationEventRecorder: NotificationEventRecorder

    init() {
        let reminderService = EventKitReminderService()
        let databaseProvider = DatabaseProvider(path: Self.databasePath())
        let syncService = TaskSyncService(
            reminderService: reminderService,
            databaseProvider: databaseProvider
        )
        let calendarService = EventKitCalendarService()
        let getOpenTasksTool = GetOpenTasksTool(reminderService: reminderService)
        let getTaskStatisticsTool = GetTaskStatisticsTool(
            databaseProvider: databaseProvider,
            syncService: syncService
        )
        let findFreeTimeTool = FindFreeTimeTool(calendarService: calendarService)
        let getReminderRecommendationTool = GetReminderRecommendationTool(
            databaseProvider: databaseProvider,
            syncService: syncService,
            calendarService: calendarService
        )

        let notificationService = UserNotificationService()
        notificationService.registerCategories()
        let proposalCenter = NotificationProposalCenter(
            notificationService: notificationService,
            databaseProvider: databaseProvider
        )
        let scheduleNotificationTool = ScheduleNotificationTool(
            databaseProvider: databaseProvider,
            syncService: syncService,
            proposalCenter: proposalCenter
        )
        let reminderCreationCenter = ReminderCreationCenter(
            reminderService: reminderService,
            syncService: syncService
        )
        let createReminderTool = CreateReminderTool(
            proposalCenter: reminderCreationCenter,
            databaseProvider: databaseProvider,
            syncService: syncService
        )
        let notificationEventRecorder = NotificationEventRecorder(databaseProvider: databaseProvider)
        UserNotificationService.installDelegate(notificationEventRecorder)

        // The registry is the single authority on which tools the model
        // can request, with their access declarations.
        let toolRegistry = ToolRegistry(entries: [
            ToolRegistry.entry(getOpenTasksTool),
            ToolRegistry.entry(getTaskStatisticsTool),
            ToolRegistry.entry(findFreeTimeTool),
            ToolRegistry.entry(getReminderRecommendationTool),
            ToolRegistry.entry(createReminderTool),
            ToolRegistry.entry(scheduleNotificationTool),
        ])

        let contextBuilder = AgentContextBuilder(databaseProvider: databaseProvider)
        // The agent sees only the LanguageModel seam. Swapping the
        // provider (a future Core AI/Gemma model) is a one-line change here.
        let languageModel = FoundationModelsLanguageModel()
        let agentController = AgentController(
            model: languageModel,
            registry: toolRegistry,
            contextPrefix: { await contextBuilder.promptPrefix() }
        )
        agentViewModel = AgentViewModel(
            agent: agentController,
            availability: { agentController.availability() },
            proposalCenter: proposalCenter,
            reminderCreationCenter: reminderCreationCenter
        )
        insightsViewModel = InsightsViewModel(
            builder: InsightsBuilder(
                databaseProvider: databaseProvider,
                syncService: syncService
            )
        )
        self.syncService = syncService
        self.notificationEventRecorder = notificationEventRecorder
    }

    /// Called on launch and whenever the app returns to the foreground.
    /// Skips silently when Reminders access has not been granted yet.
    func synchronizeHistory() {
        let syncService = syncService
        _Concurrency.Task {
            await syncService.syncIfAuthorized()
        }
    }

    private static func databasePath() -> String {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("PersonalAgent", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("personalagent.sqlite").path
    }
}
