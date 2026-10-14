import Foundation
import UserNotifications

/// Records the notification outcomes iOS actually exposes:
/// foreground presentation and taps → `reminderDelivered`, explicit dismissal
/// (via the custom-dismiss category) → `reminderDismissed`. Background
/// deliveries without interaction are NOT observable and are not invented.
final class NotificationEventRecorder: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let databaseProvider: DatabaseProvider
    private let now: @Sendable () -> Date

    init(databaseProvider: DatabaseProvider, now: @escaping @Sendable () -> Date = { Date() }) {
        self.databaseProvider = databaseProvider
        self.now = now
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await record(type: .reminderDelivered, identifier: notification.request.identifier)
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        switch response.actionIdentifier {
        case UNNotificationDismissActionIdentifier:
            await record(type: .reminderDismissed, identifier: identifier)
        case UNNotificationDefaultActionIdentifier:
            // A tap implies the notification reached the user.
            await record(type: .reminderDelivered, identifier: identifier)
        default:
            break
        }
    }

    /// Best-effort and idempotent per (task, notification, type); ad-hoc
    /// notifications have no task and produce no history.
    func record(type: TaskEventType, identifier: String) async {
        guard let taskID = NotificationIdentifier.taskID(from: identifier) else { return }
        do {
            let database = try await databaseProvider.preparedDatabase()
            let repository = TaskEventRepository(database: database)
            let existing = try await repository.events(forTaskID: taskID)
            let alreadyRecorded = existing.contains {
                $0.type == type && $0.metadata["notificationID"] == identifier
            }
            guard !alreadyRecorded else { return }
            try await repository.insert(
                TaskEvent(
                    taskID: taskID,
                    type: type,
                    timestamp: now(),
                    metadata: ["notificationID": identifier]
                )
            )
        } catch {
            // History recording must never break notification handling.
        }
    }
}
