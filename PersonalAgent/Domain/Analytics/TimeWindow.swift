import Foundation

enum TimeWindowName: String, CaseIterable, Sendable {
    case night
    case morning
    case afternoon
    case evening
}

/// Fixed six-hour day windows (finer windows come later).
struct TimeWindow: Equatable, Hashable, Sendable {
    let name: TimeWindowName
    /// Inclusive start hour, exclusive end hour, local time.
    let startHour: Int
    let endHour: Int

    static let night = TimeWindow(name: .night, startHour: 0, endHour: 6)
    static let morning = TimeWindow(name: .morning, startHour: 6, endHour: 12)
    static let afternoon = TimeWindow(name: .afternoon, startHour: 12, endHour: 18)
    static let evening = TimeWindow(name: .evening, startHour: 18, endHour: 24)

    /// Fixed order — also the deterministic tie-break order in analysis.
    static let allWindows: [TimeWindow] = [.night, .morning, .afternoon, .evening]

    static func window(forHour hour: Int) -> TimeWindow {
        let clamped = min(max(hour, 0), 23)
        return allWindows.first { clamped >= $0.startHour && clamped < $0.endHour } ?? .night
    }
}
