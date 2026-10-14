import Foundation

/// Loads history and aggregates it into an `InsightsReport`. Nonisolated async,
/// so the work runs off the main actor; refreshes the history first
/// (never prompting for permissions).
struct InsightsBuilder: Sendable {
    let databaseProvider: DatabaseProvider
    let syncService: TaskSyncService
    let calendar: Calendar
    let now: @Sendable () -> Date

    init(
        databaseProvider: DatabaseProvider,
        syncService: TaskSyncService,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.databaseProvider = databaseProvider
        self.syncService = syncService
        self.calendar = calendar
        self.now = now
    }

    func hasReminderAccess() async -> Bool {
        await syncService.hasReminderAccess()
    }

    /// Only called from an explicit user action on the Insights screen.
    func requestReminderAccess() async throws {
        try await syncService.requestAccessAndSynchronize()
    }

    func buildReport() async throws -> InsightsReport {
        await syncService.syncIfAuthorized()
        let database = try await databaseProvider.preparedDatabase()
        let taskRepository = TaskRepository(database: database)
        let eventRepository = TaskEventRepository(database: database)
        let outcomeRepository = RecommendationOutcomeRepository(database: database)

        let tasks = try await taskRepository.allTasks()
        var taskData: [(task: Task, events: [TaskEvent])] = []
        taskData.reserveCapacity(tasks.count)
        for task in tasks {
            taskData.append((task, try await eventRepository.events(forTaskID: task.id)))
        }
        let outcomes = try await outcomeRepository.allOutcomes()

        return InsightsAggregator.report(
            taskData: taskData,
            outcomes: outcomes,
            now: now(),
            calendar: calendar
        )
    }
}
