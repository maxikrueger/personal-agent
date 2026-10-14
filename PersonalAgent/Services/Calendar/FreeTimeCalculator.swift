import Foundation

/// Deterministic busy/free interval computation.
/// The language model never calculates availability itself.
enum FreeTimeCalculator {
    /// All-day events (birthdays, holidays) do not block time slots; events
    /// with a non-positive duration are ignored.
    static func busyIntervals(from events: [CalendarEvent]) -> [DateInterval] {
        events
            .filter { !$0.isAllDay && $0.endDate > $0.startDate }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
    }

    /// Gaps within `range` not covered by any busy interval and at least
    /// `minimumDuration` long, in chronological order. Overlapping and
    /// adjacent busy intervals are merged implicitly.
    static func freeIntervals(
        busy: [DateInterval],
        range: DateInterval,
        minimumDuration: TimeInterval
    ) -> [DateInterval] {
        guard minimumDuration > 0, range.duration >= minimumDuration else { return [] }

        let clipped = busy
            .compactMap { interval -> DateInterval? in
                guard let intersection = interval.intersection(with: range),
                      intersection.duration > 0 else { return nil }
                return intersection
            }
            .sorted { $0.start < $1.start }

        var free: [DateInterval] = []
        var cursor = range.start
        for interval in clipped {
            if interval.start > cursor {
                let gap = DateInterval(start: cursor, end: interval.start)
                if gap.duration >= minimumDuration {
                    free.append(gap)
                }
            }
            cursor = max(cursor, interval.end)
        }
        if cursor < range.end {
            let gap = DateInterval(start: cursor, end: range.end)
            if gap.duration >= minimumDuration {
                free.append(gap)
            }
        }
        return free
    }
}
