import Foundation
import UserNotifications

struct UserNotificationService: NotificationService {
    /// Category with `customDismissAction` so explicit dismissals are reported
    /// to the delegate — one of the few outcome signals iOS actually exposes.
    static let reminderCategoryIdentifier = "PERSONAL_AGENT_REMINDER"

    /// Concrete parameter type on purpose: callers outside this layer never
    /// see UserNotifications types.
    static func installDelegate(_ recorder: NotificationEventRecorder) {
        UNUserNotificationCenter.current().delegate = recorder
    }

    func registerCategories() {
        let category = UNNotificationCategory(
            identifier: Self.reminderCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func requestAccess() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { throw NotificationServiceError.accessDenied }
        case .denied:
            throw NotificationServiceError.accessDenied
        @unknown default:
            throw NotificationServiceError.accessDenied
        }
    }

    func schedule(id: String, title: String, body: String, date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.reminderCategoryIdentifier

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            throw NotificationServiceError.schedulingFailed(details: error.localizedDescription)
        }
    }

    func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
