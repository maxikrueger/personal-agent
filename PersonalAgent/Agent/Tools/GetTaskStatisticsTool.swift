import Foundation
import FoundationModels

/// Read-only tool: deterministic behavioral statistics
/// from the local event history. The model explains the numbers, it never
/// computes them.
///
/// Tasks are addressed by title
/// instead of raw UUID — the small on-device model handles titles reliably,
/// and resolving titles against stored tasks is the validation step.
struct GetTaskStatisticsTool: Tool {
    let name = "getTaskStatistics"
    let description = """
    Liefert deterministische Verhaltensstatistiken zu Aufgaben (Aufschieben, Erledigung, Muster, Zeitfenster). \
    Ohne taskTitle: kompakte Übersicht aller offenen Aufgaben. Mit taskTitle: Details zu genau einer Aufgabe.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Titel oder eindeutiger Titelteil der Aufgabe. Weglassen für eine Übersicht aller offenen Aufgaben.")
        var taskTitle: String?
    }

    /// Overview lists at most this many tasks to protect the context window.
    static let maxOverviewTasks = 15
    static let maxSuggestedTitles = 10

    private let databaseProvider: DatabaseProvider
    private let syncService: TaskSyncService
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        databaseProvider: DatabaseProvider,
        syncService: TaskSyncService,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.databaseProvider = databaseProvider
        self.syncService = syncService
        self.calendar = calendar
        self.now = now
    }

    func call(arguments: Arguments) async throws -> String {
        // Statistics answer from the local history — refresh it first so
        // changes made in Apple Reminders are already reflected.
        await syncService.syncIfAuthorized()

        let database: SQLiteDatabase
        do {
            database = try await databaseProvider.preparedDatabase()
        } catch {
            return "Fehler: Die lokale Verlaufsdatenbank ist nicht verfügbar."
        }
        let taskRepository = TaskRepository(database: database)
        let eventRepository = TaskEventRepository(database: database)

        do {
            let allTasks = try await taskRepository.allTasks()
            guard !allTasks.isEmpty else {
                return "Es liegen noch keine Verlaufsdaten vor. Statistiken entstehen, sobald Aufgaben synchronisiert wurden."
            }

            let query = (arguments.taskTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                return try await overviewText(tasks: allTasks, eventRepository: eventRepository)
            }

            let matches = TaskTitleResolver.matches(for: query, in: allTasks)
            switch matches.count {
            case 0:
                let openTitles = allTasks
                    .filter { !$0.isCompleted }
                    .map(\.title)
                    .prefix(Self.maxSuggestedTitles)
                var text = "Keine Aufgabe mit dem Titel „\(query)“ gefunden."
                if !openTitles.isEmpty {
                    text += " Offene Aufgaben: " + openTitles.joined(separator: ", ")
                }
                return text
            case 1:
                let task = matches[0]
                let analysis = try await analyze(task: task, eventRepository: eventRepository)
                return TaskStatisticsFormatter.detailText(title: task.title, analysis: analysis)
            default:
                let titles = matches.map(\.title).prefix(Self.maxSuggestedTitles)
                return "Mehrere Aufgaben passen zu „\(query)“: " + titles.joined(separator: ", ")
                    + ". Bitte den Titel genauer angeben."
            }
        } catch let error as DatabaseError {
            return "Fehler beim Lesen der Statistik: \(error.errorDescription ?? "Unbekannter Fehler.")"
        }
    }

    private func analyze(task: Task, eventRepository: TaskEventRepository) async throws -> TaskAnalysis {
        let events = try await eventRepository.events(forTaskID: task.id)
        return TaskAnalyticsEngine.analyze(task: task, events: events, now: now(), calendar: calendar)
    }

    private func overviewText(
        tasks: [Task],
        eventRepository: TaskEventRepository
    ) async throws -> String {
        let openTasks = tasks.filter { !$0.isCompleted }
        guard !openTasks.isEmpty else {
            return "Es gibt derzeit keine offenen Aufgaben, zu denen Statistiken gehören."
        }
        var analyzed: [(task: Task, analysis: TaskAnalysis)] = []
        for task in openTasks {
            analyzed.append((task, try await analyze(task: task, eventRepository: eventRepository)))
        }
        analyzed.sort { lhs, rhs in
            if lhs.analysis.statistics.procrastinationScore != rhs.analysis.statistics.procrastinationScore {
                return lhs.analysis.statistics.procrastinationScore > rhs.analysis.statistics.procrastinationScore
            }
            return lhs.task.title.localizedCompare(rhs.task.title) == .orderedAscending
        }

        var lines = ["Statistik-Übersicht offener Aufgaben (\(analyzed.count)), sortiert nach Prokrastinations-Score:"]
        for entry in analyzed.prefix(Self.maxOverviewTasks) {
            lines.append(TaskStatisticsFormatter.overviewLine(title: entry.task.title, analysis: entry.analysis))
        }
        let remaining = analyzed.count - Self.maxOverviewTasks
        if remaining > 0 {
            lines.append("… und \(remaining) weitere.")
        }
        return lines.joined(separator: "\n")
    }
}
