import Foundation

/// The repeat rule of a recurring reminder, reduced to what the sync needs to
/// tell "the next occurrence is due" apart from "the user postponed it".
///
/// Completing a recurring reminder in Apple Reminders does not mark it
/// completed: the reminder stays open and its due date jumps to the next
/// occurrence. Without this rule every completion would look like a
/// postponement.
struct TaskRecurrence: Equatable, Hashable, Sendable {
    enum Frequency: String, Equatable, Hashable, Sendable {
        case daily
        case weekly
        case monthly
        case yearly
    }

    let frequency: Frequency
    /// Every `interval` days/weeks/months/years; at least 1.
    let interval: Int
    /// The rule restricts occurrences further (e.g. "Mon, Wed, Fri" or "every
    /// last Friday"), so occurrences are not evenly spaced.
    let hasAdditionalConstraints: Bool

    init(frequency: Frequency, interval: Int = 1, hasAdditionalConstraints: Bool = false) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.hasAdditionalConstraints = hasAdditionalConstraints
    }

    /// Upper bound of steps checked, so a far-away date cannot loop for long.
    static let maxSteps = 400

    /// True when moving the due date from `oldDueDate` to `newDueDate` matches
    /// the rule advancing to a later occurrence.
    ///
    /// Evenly spaced rules must land exactly on a whole number of steps (wall
    /// time is kept across daylight-saving changes). Rules with additional
    /// constraints cannot be stepped this simply; there any forward move of
    /// at most one full period counts as the next occurrence.
    func isOccurrenceAdvance(from oldDueDate: Date, to newDueDate: Date, calendar: Calendar) -> Bool {
        guard newDueDate > oldDueDate else { return false }

        if hasAdditionalConstraints {
            guard let periodEnd = calendar.date(byAdding: component, value: interval, to: oldDueDate) else {
                return false
            }
            return newDueDate <= periodEnd
        }

        var candidate = oldDueDate
        for _ in 0..<Self.maxSteps {
            guard let next = calendar.date(byAdding: component, value: interval, to: candidate) else {
                return false
            }
            if next == newDueDate { return true }
            if next > newDueDate { return false }
            candidate = next
        }
        return false
    }

    private var component: Calendar.Component {
        switch frequency {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}
