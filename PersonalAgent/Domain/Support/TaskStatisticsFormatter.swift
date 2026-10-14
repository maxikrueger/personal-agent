import Foundation

/// Renders deterministic analysis results as compact German text for the model
/// (the tool retrieves, the LLM explains). Sample sizes are
/// always included so weak evidence is never presented as fact.
enum TaskStatisticsFormatter {
    static let lowDataHint = "Hinweis: wenige Datenpunkte — Aussagen sind vorläufig."

    static func detailText(title: String, analysis: TaskAnalysis) -> String {
        let statistics = analysis.statistics
        var lines = ["Statistik für „\(title)“:"]

        lines.append(
            "• Erledigungsquote: \(percentText(statistics.completionRate)) (\(analysis.completionCount) von \(analysis.cycleCount) Zyklen)"
        )

        var postponementLine =
            "• Aufschiebungen: \(statistics.postponementCount) (Quote \(percentText(statistics.postponementRate)))"
        if analysis.consecutivePostponements > 0 {
            postponementLine += ", davon \(analysis.consecutivePostponements) in Folge seit der letzten Erledigung"
        }
        if let shift = analysis.averagePostponementDelay, shift > 0 {
            postponementLine += "; im Schnitt um \(durationText(shift)) verschoben"
        }
        lines.append(postponementLine)

        if let averageDelay = statistics.averageDelay {
            var delayLine = "• Erledigung: im Schnitt \(durationText(averageDelay)) "
            delayLine += averageDelay >= 0 ? "nach Fälligkeit" : "vor Fälligkeit"
            if let medianDelay = statistics.medianDelay {
                delayLine += " (Median \(durationText(medianDelay)))"
            }
            lines.append(delayLine)
        }

        var overdueLine = "• Überfällig: \(statistics.overdueCount)×"
        if analysis.isCurrentlyOverdue {
            overdueLine += " (aktuell überfällig)"
        }
        lines.append(overdueLine)

        if let pattern = analysis.recurrence.pattern {
            lines.append(
                "• Wiederkehr: \(patternText(pattern)) (Konfidenz \(percentText(analysis.recurrence.confidence)), \(completionsText(analysis.recurrence.sampleSize)))"
            )
        } else {
            lines.append("• Wiederkehr: kein klares Muster erkennbar")
        }

        if let window = analysis.preferredWindow.window {
            lines.append(
                "• Bevorzugtes Zeitfenster: \(windowText(window.name)) (\(window.startHour)–\(window.endHour) Uhr; Anteil \(percentText(analysis.preferredWindow.confidence)) von \(completionsText(analysis.preferredWindow.sampleSize)))"
            )
        }

        lines.append("• Prokrastinations-Score: \(percentText(statistics.procrastinationScore))")

        if analysis.completionCount < 3 {
            lines.append(lowDataHint)
        }
        return lines.joined(separator: "\n")
    }

    static func overviewLine(title: String, analysis: TaskAnalysis) -> String {
        var line = "• \(title) — Score \(percentText(analysis.statistics.procrastinationScore))"
        line += " — \(analysis.statistics.postponementCount)× aufgeschoben"
        if analysis.isCurrentlyOverdue {
            line += " — überfällig"
        }
        if let window = analysis.preferredWindow.window {
            line += " — meist \(windowText(window.name)) erledigt"
        }
        return line
    }

    /// "1 Erledigung" / "3 Erledigungen".
    static func completionsText(_ count: Int) -> String {
        count == 1 ? "1 Erledigung" : "\(count) Erledigungen"
    }

    static func percentText(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) %"
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let seconds = abs(interval)
        if seconds < 3600 {
            let minutes = max(1, Int((seconds / 60).rounded()))
            return minutes == 1 ? "1 Minute" : "\(minutes) Minuten"
        }
        if seconds < 24 * 3600 {
            let hours = max(1, Int((seconds / 3600).rounded()))
            return hours == 1 ? "1 Stunde" : "\(hours) Stunden"
        }
        let days = Int((seconds / 86_400).rounded())
        return days == 1 ? "1 Tag" : "\(days) Tage"
    }

    static func windowText(_ name: TimeWindowName) -> String {
        switch name {
        case .night: return "nachts"
        case .morning: return "morgens"
        case .afternoon: return "nachmittags"
        case .evening: return "abends"
        }
    }

    static func patternText(_ pattern: RecurrencePattern) -> String {
        switch pattern {
        case .daily: return "täglich"
        case .everyWeekday: return "werktags"
        case .weekly: return "wöchentlich"
        case .biweekly: return "alle zwei Wochen"
        case .monthly: return "monatlich"
        case .irregular: return "regelmäßig, aber ohne festen Rhythmus"
        }
    }
}
