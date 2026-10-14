import Foundation

/// Deterministic reminder-effectiveness metrics per task,
/// computed from recorded notification events. Only counts what was actually
/// observed: snoozes are included for completeness but stay zero until
/// iOS-side snooze actions exist.
/// One reminder that fired, with its attributed completion (if any) — the
/// per-fire granularity insights need for time-window comparisons.
struct FiredReminderOutcome: Equatable, Sendable {
    let fireDate: Date
    let completionDate: Date?

    var completedWithinWindow: Bool {
        completionDate != nil
    }

    var delay: TimeInterval? {
        completionDate.map { $0.timeIntervalSince(fireDate) }
    }
}

struct ReminderEffectiveness: Equatable, Sendable {
    /// Reminders whose fire date lies in the past, chronological.
    let firedReminders: [FiredReminderOutcome]
    let firedReminderCount: Int
    let completionsAfterReminder: Int
    let completionAfterReminderRate: Double
    let averageDelayAfterReminder: TimeInterval?
    /// Completions not preceded by a reminder within the attribution window.
    let completionsWithoutReminder: Int
    let dismissedCount: Int
    let dismissRate: Double
    let snoozedCount: Int
}

enum ReminderEffectivenessAnalyzer {
    /// A completion within this window after a reminder fired counts as
    /// "completion after reminder".
    static let attributionWindow: TimeInterval = 24 * 3600

    static func analyze(events: [TaskEvent], now: Date) -> ReminderEffectiveness {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        let fireDates = sorted
            .filter { $0.type == .reminderScheduled }
            .compactMap { parse($0.metadata["fireDate"]) }
            .filter { $0 <= now }
            .sorted()
        let completions = sorted.filter { $0.type == .completed }.map(\.timestamp)
        let dismissedCount = sorted.filter { $0.type == .reminderDismissed }.count
        let snoozedCount = sorted.filter { $0.type == .reminderSnoozed }.count

        let firedReminders = fireDates.map { fireDate in
            FiredReminderOutcome(
                fireDate: fireDate,
                completionDate: completions.first {
                    $0 > fireDate && $0 <= fireDate.addingTimeInterval(attributionWindow)
                }
            )
        }
        let completionsAfterReminder = firedReminders.filter(\.completedWithinWindow).count
        let delays = firedReminders.compactMap(\.delay)

        let completionsWithoutReminder = completions.filter { completion in
            !fireDates.contains {
                completion > $0 && completion <= $0.addingTimeInterval(attributionWindow)
            }
        }.count

        let firedCount = fireDates.count
        return ReminderEffectiveness(
            firedReminders: firedReminders,
            firedReminderCount: firedCount,
            completionsAfterReminder: completionsAfterReminder,
            completionAfterReminderRate: firedCount > 0
                ? Double(completionsAfterReminder) / Double(firedCount)
                : 0,
            averageDelayAfterReminder: CompletionAnalyzer.average(of: delays),
            completionsWithoutReminder: completionsWithoutReminder,
            dismissedCount: dismissedCount,
            dismissRate: firedCount > 0 ? min(1, Double(dismissedCount) / Double(firedCount)) : 0,
            snoozedCount: snoozedCount
        )
    }

    private static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return try? Date(iso, strategy: Date.ISO8601FormatStyle())
    }
}
