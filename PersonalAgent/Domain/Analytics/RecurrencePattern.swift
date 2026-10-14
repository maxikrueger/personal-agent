/// Behavioral recurrence detected from completion history.
/// Stays a recommendation until the user confirms it.
enum RecurrencePattern: String, Equatable, Sendable {
    case daily
    case everyWeekday
    case weekly
    case biweekly
    case monthly
    case irregular
}
