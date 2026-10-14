import Foundation
import FoundationModels

/// Read-only tool: free calendar slots for one day.
/// The on-device model has no clock, so days are addressed relative to today
/// (daysFromToday) and resolved app-side into absolute dates in the device
/// timezone; every argument is validated before use.
struct FindFreeTimeTool: Tool {
    let name = "findFreeTime"
    let description = """
    Findet freie Zeiträume im Kalender des Nutzers an einem Tag. \
    daysFromToday ist relativ zu heute (0 = heute, 1 = morgen). Nenne nur Zeiträume aus dem Ergebnis.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Tag relativ zu heute: 0 = heute, 1 = morgen, 2 = übermorgen, …")
        var daysFromToday: Int
        @Guide(description: "Gewünschte Dauer in Minuten (Standard: 30)")
        var durationMinutes: Int?
        @Guide(description: "Früheste Stunde des Suchfensters, 0–23 (Standard: 8)")
        var earliestHour: Int?
        @Guide(description: "Späteste Stunde des Suchfensters, 1–24 (Standard: 21)")
        var latestHour: Int?
    }

    static let defaultDurationMinutes = 30
    static let defaultEarliestHour = 8
    static let defaultLatestHour = 21
    static let maxDaysAhead = 30
    static let durationRange = 5...480
    static let maxListedSlots = 8

    private let calendarService: any CalendarService
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        calendarService: any CalendarService,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.calendarService = calendarService
        self.calendar = calendar
        self.now = now
    }

    func call(arguments: Arguments) async throws -> String {
        guard (0...Self.maxDaysAhead).contains(arguments.daysFromToday) else {
            return "Ungültiger Tag: daysFromToday muss zwischen 0 (heute) und \(Self.maxDaysAhead) liegen."
        }
        let durationMinutes = arguments.durationMinutes ?? Self.defaultDurationMinutes
        guard Self.durationRange.contains(durationMinutes) else {
            return "Ungültige Dauer: durationMinutes muss zwischen \(Self.durationRange.lowerBound) und \(Self.durationRange.upperBound) liegen."
        }
        let earliestHour = arguments.earliestHour ?? Self.defaultEarliestHour
        let latestHour = arguments.latestHour ?? Self.defaultLatestHour
        guard (0...23).contains(earliestHour), (1...24).contains(latestHour), latestHour > earliestHour else {
            return "Ungültiges Zeitfenster: earliestHour (0–23) muss vor latestHour (1–24) liegen."
        }

        let currentDate = now()
        let startOfToday = calendar.startOfDay(for: currentDate)
        guard let day = calendar.date(byAdding: .day, value: arguments.daysFromToday, to: startOfToday),
              let windowStart = calendar.date(bySettingHour: earliestHour, minute: 0, second: 0, of: day),
              let windowEnd = Self.windowEnd(latestHour: latestHour, day: day, calendar: calendar) else {
            return "Der Zeitraum konnte nicht berechnet werden."
        }

        // For "today", slots in the past are useless.
        var searchStart = windowStart
        if arguments.daysFromToday == 0 {
            searchStart = max(searchStart, currentDate)
        }
        guard windowEnd.timeIntervalSince(searchStart) >= TimeInterval(durationMinutes * 60) else {
            return "Am \(Self.dayText(for: day, calendar: calendar)) ist in diesem Zeitfenster keine ausreichende Zeit mehr übrig."
        }

        do {
            let slots = try await calendarService.findFreeTime(
                from: searchStart,
                to: windowEnd,
                duration: TimeInterval(durationMinutes * 60)
            )
            return Self.text(
                for: slots,
                day: day,
                searchStart: searchStart,
                searchEnd: windowEnd,
                durationMinutes: durationMinutes,
                calendar: calendar
            )
        } catch let error as CalendarServiceError {
            return "Fehler beim Kalenderzugriff: \(error.errorDescription ?? "Unbekannter Fehler.")"
        }
    }

    private static func windowEnd(latestHour: Int, day: Date, calendar: Calendar) -> Date? {
        if latestHour >= 24 {
            return calendar.date(byAdding: .day, value: 1, to: day)
        }
        return calendar.date(bySettingHour: latestHour, minute: 0, second: 0, of: day)
    }

    static func text(
        for slots: [DateInterval],
        day: Date,
        searchStart: Date,
        searchEnd: Date,
        durationMinutes: Int,
        calendar: Calendar
    ) -> String {
        let dayLabel = dayText(for: day, calendar: calendar)
        let windowLabel = "zwischen \(timeText(searchStart, calendar: calendar)) und \(timeText(searchEnd, calendar: calendar))"
        guard !slots.isEmpty else {
            return "Keine freien Zeiträume am \(dayLabel) \(windowLabel) mit mindestens \(durationMinutes) Minuten."
        }
        var lines = ["Freie Zeiträume am \(dayLabel) \(windowLabel) (mindestens \(durationMinutes) Minuten):"]
        for slot in slots.prefix(maxListedSlots) {
            let minutes = Int((slot.duration / 60).rounded())
            lines.append("• \(timeText(slot.start, calendar: calendar))–\(timeText(slot.end, calendar: calendar)) (\(minutes) Minuten)")
        }
        let remaining = slots.count - maxListedSlots
        if remaining > 0 {
            lines.append("… und \(remaining) weitere freie Zeiträume.")
        }
        return lines.joined(separator: "\n")
    }

    static func dayText(for date: Date, calendar: Calendar) -> String {
        GermanDateText.dayText(for: date, calendar: calendar)
    }

    static func timeText(_ date: Date, calendar: Calendar) -> String {
        GermanDateText.timeText(date, calendar: calendar)
    }
}
