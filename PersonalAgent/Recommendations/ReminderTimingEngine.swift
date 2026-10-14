import Foundation

/// Generates candidate reminder times from free calendar slots.
/// Deterministic and pure.
enum ReminderTimingEngine {
    /// For every slot long enough for the task: the slot start, plus the
    /// preferred-window start on each day the slot touches when that start
    /// lies inside the slot and still leaves room for the task.
    static func candidateTimes(
        freeSlots: [DateInterval],
        preferredWindow: TimeWindow?,
        taskDuration: TimeInterval,
        calendar: Calendar
    ) -> [Date] {
        var candidates: Set<Date> = []
        for slot in freeSlots where slot.duration >= taskDuration {
            candidates.insert(slot.start)
            guard let preferredWindow else { continue }
            var day = calendar.startOfDay(for: slot.start)
            while day < slot.end {
                if let windowStart = calendar.date(
                    bySettingHour: preferredWindow.startHour,
                    minute: 0,
                    second: 0,
                    of: day
                ),
                    windowStart > slot.start,
                    windowStart.addingTimeInterval(taskDuration) <= slot.end {
                    candidates.insert(windowStart)
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
        }
        return candidates.sorted()
    }
}
