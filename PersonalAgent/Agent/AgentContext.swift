import Foundation

/// Controlled per-request context: the model never sees
/// the whole database — only a compact, deterministic snapshot. Crucially it
/// carries the current date/time, which the on-device model does not know.
struct AgentContext: Equatable, Sendable {
    let now: Date
    let openTaskCount: Int
    /// Titles of currently overdue tasks, earliest due date first, capped.
    let overdueTitles: [String]
}

/// Pure selection + rendering (unit-tested exactly).
enum AgentContextComposer {
    static let maxOverdueTitles = 3

    static func context(tasks: [Task], now: Date) -> AgentContext {
        let openTasks = tasks.filter { !$0.isCompleted }
        let overdueTitles = openTasks
            .compactMap { task -> (title: String, dueDate: Date)? in
                guard let dueDate = task.dueDate, dueDate < now else { return nil }
                return (task.title, dueDate)
            }
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate {
                    return lhs.dueDate < rhs.dueDate
                }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
            .prefix(maxOverdueTitles)
            .map(\.title)
        return AgentContext(
            now: now,
            openTaskCount: openTasks.count,
            overdueTitles: Array(overdueTitles)
        )
    }

    /// One compact German line — instructions, tool schemas, transcript and
    /// this prefix all share the model's small context window.
    static func promptPrefix(for context: AgentContext, calendar: Calendar) -> String {
        var text = "[Kontext: Heute ist \(GermanDateText.dayText(for: context.now, calendar: calendar)), \(GermanDateText.timeText(context.now, calendar: calendar)) Uhr. "
        text += "Offene Aufgaben: \(context.openTaskCount)"
        if !context.overdueTitles.isEmpty {
            text += ", davon überfällig: " + context.overdueTitles.joined(separator: ", ")
        }
        text += ".]"
        return text
    }

    /// The small model occasionally repeats the context block in its answer.
    /// It is internal plumbing, so it is removed deterministically instead of
    /// relying on the instruction alone.
    static func strippingEchoedContext(from answer: String) -> String {
        let cleaned = answer
            .replacingOccurrences(of: #"\[Kontext:[^\]]*\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? answer : cleaned
    }
}

/// IO shell: reads the stored tasks and degrades to a date-only context on any
/// failure — the chat must never break because context loading did.
struct AgentContextBuilder: Sendable {
    let databaseProvider: DatabaseProvider
    let calendar: Calendar
    let now: @Sendable () -> Date

    init(
        databaseProvider: DatabaseProvider,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.databaseProvider = databaseProvider
        self.calendar = calendar
        self.now = now
    }

    func buildContext() async -> AgentContext {
        let currentDate = now()
        do {
            let database = try await databaseProvider.preparedDatabase()
            let tasks = try await TaskRepository(database: database).allTasks()
            return AgentContextComposer.context(tasks: tasks, now: currentDate)
        } catch {
            return AgentContext(now: currentDate, openTaskCount: 0, overdueTitles: [])
        }
    }

    func promptPrefix() async -> String {
        AgentContextComposer.promptPrefix(for: await buildContext(), calendar: calendar)
    }
}
