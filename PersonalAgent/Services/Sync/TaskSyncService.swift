import Foundation
import os

struct SyncSummary: Equatable, Sendable {
    var created = 0
    var completed = 0
    var reopened = 0
    var postponed = 0
    var modified = 0
    var unchanged = 0

    var totalEvents: Int {
        created + completed + reopened + postponed + modified
    }

    mutating func count(_ type: TaskEventType) {
        switch type {
        case .created: created += 1
        case .completed: completed += 1
        case .reopened: reopened += 1
        case .postponed: postponed += 1
        case .modified: modified += 1
        default: break
        }
    }
}

/// Diffs the current Reminders state against the stored state and persists the
/// resulting task history. Changes made outside the
/// app (completing, postponing, editing in Apple Reminders) become TaskEvents.
actor TaskSyncService {
    private let reminderService: any ReminderService
    private let databaseProvider: DatabaseProvider
    private let logger = Logger(subsystem: "com.maxikrueger.PersonalAgent", category: "sync")
    private var isSyncing = false

    init(reminderService: any ReminderService, databaseProvider: DatabaseProvider) {
        self.reminderService = reminderService
        self.databaseProvider = databaseProvider
    }

    /// Fire-and-forget entry point for app lifecycle triggers. Never throws and
    /// never triggers the permission dialog — the first permission request must
    /// come from an explicit user action in the chat, not from a background sync.
    func syncIfAuthorized() async {
        guard await reminderService.hasFullAccess() else { return }
        do {
            let summary = try await synchronize()
            if summary.totalEvents > 0 {
                logger.info("Sync recorded \(summary.totalEvents) events (\(summary.unchanged) tasks unchanged)")
            }
        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
        }
    }

    /// True when Reminders access is granted. Never prompts.
    func hasReminderAccess() async -> Bool {
        await reminderService.hasFullAccess()
    }

    /// Explicit user action (e.g. a button): asks for Reminders access, which
    /// shows the system dialog the first time, then synchronizes right away.
    func requestAccessAndSynchronize() async throws {
        try await reminderService.requestAccess()
        try await synchronize()
    }

    @discardableResult
    func synchronize(now: Date = Date()) async throws -> SyncSummary {
        guard !isSyncing else { return SyncSummary() }
        isSyncing = true
        defer { isSyncing = false }

        let database = try await databaseProvider.preparedDatabase()
        let taskRepository = TaskRepository(database: database)
        let eventRepository = TaskEventRepository(database: database)
        let fetched = try await reminderService.fetchAllTasks()
        let stored = try await taskRepository.tasksByExternalID()

        var summary = SyncSummary()
        try await database.beginTransaction()
        do {
            for fetchedTask in fetched {
                let previous = stored[fetchedTask.externalID]
                let current = fetchedTask.replacingID(previous?.id ?? fetchedTask.id)
                if let previous, previous == current.withoutRecurrence {
                    summary.unchanged += 1
                    continue
                }
                let events = TaskChangeDetector.events(previous: previous, current: current, now: now)
                try await taskRepository.upsert(current, updatedAt: now)
                for event in events {
                    try await eventRepository.insert(event)
                    summary.count(event.type)
                }
            }
            try await database.commitTransaction()
        } catch {
            await database.rollbackTransaction()
            throw error
        }
        // Tasks stored locally but no longer returned by EventKit were deleted in
        // Reminders; their rows and history are preserved (no "deleted" event type
        // exists).

        // Derive recommendation outcomes from the freshly synced history.
        // Best-effort — the sync itself is already committed.
        do {
            let recordedOutcomes = try await OutcomeSweeper(database: database).sweep(now: now)
            if recordedOutcomes > 0 {
                logger.info("Sweep recorded \(recordedOutcomes) recommendation outcomes")
            }
        } catch {
            logger.error("Outcome sweep failed: \(error.localizedDescription)")
        }
        return summary
    }
}
