import Foundation
import FoundationModels

/// Read-only tool: fetches open reminders and returns
/// compact summaries as text. Never exposes EventKit objects to the model.
struct GetOpenTasksTool: Tool {
    let name = "getOpenTasks"
    let description = "Liest die offenen (nicht erledigten) Aufgaben des Nutzers aus Apple Erinnerungen."

    @Generable
    struct Arguments {}

    private let reminderService: any ReminderService
    private let now: @Sendable () -> Date

    /// Task lists longer than this are truncated to protect the model's small context window.
    static let maxListedTasks = 25

    init(reminderService: any ReminderService, now: @escaping @Sendable () -> Date = { Date() }) {
        self.reminderService = reminderService
        self.now = now
    }

    func call(arguments: Arguments) async throws -> String {
        let tasks: [Task]
        do {
            tasks = try await reminderService.fetchOpenTasks()
        } catch let error as ReminderServiceError {
            // Known failures become factual text so the model can explain them
            // to the user instead of the whole turn failing.
            return "Fehler beim Zugriff auf die Aufgaben: \(error.errorDescription ?? "Unbekannter Fehler.")"
        }
        let referenceDate = now()
        let summaries = tasks
            .map { TaskSummary(task: $0, now: referenceDate) }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case (nil, nil):
                    return lhs.title.localizedCompare(rhs.title) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case (let lhsDue?, let rhsDue?):
                    return lhsDue < rhsDue
                }
            }
        return Self.text(for: summaries)
    }

    static func text(for summaries: [TaskSummary]) -> String {
        guard !summaries.isEmpty else {
            return "Es gibt derzeit keine offenen Aufgaben."
        }
        var lines = ["Offene Aufgaben (\(summaries.count)):"]
        for summary in summaries.prefix(maxListedTasks) {
            var line = "• \(summary.title.isEmpty ? "(Ohne Titel)" : summary.title)"
            if let dueDate = summary.dueDate {
                line += " – fällig: \(formattedDueDate(dueDate))"
            }
            if summary.isOverdue {
                line += " – ÜBERFÄLLIG"
            }
            lines.append(line)
        }
        let remaining = summaries.count - maxListedTasks
        if remaining > 0 {
            lines.append("… und \(remaining) weitere offene Aufgaben.")
        }
        return lines.joined(separator: "\n")
    }

    static func formattedDueDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        return formatter.string(from: date)
    }
}
