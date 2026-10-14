import Foundation
import FoundationModels

/// Read-only tool: computes a deterministic
/// reminder recommendation — analytics, calendar availability, ranking and
/// outcome learning all happen app-side; the model only puts the result into
/// words. Without a task title it runs the intervention loop and
/// picks the task that most needs a reminder. Every shown recommendation is
/// persisted so later outcomes can be attributed to it.
struct GetReminderRecommendationTool: Tool {
    let name = "getReminderRecommendation"
    let description = """
    Berechnet einen empfohlenen Erinnerungszeitpunkt (mit Konfidenz und Gründen) aus Verhaltensstatistik, \
    Kalender und früheren Reaktionen. Mit taskTitle für eine bestimmte Aufgabe; ohne taskTitle wird die \
    Aufgabe mit dem größten Handlungsbedarf gewählt. Nenne nur die gelieferte Empfehlung.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Titel oder eindeutiger Titelteil der Aufgabe. Weglassen, um die dringendste Aufgabe automatisch zu wählen.")
        var taskTitle: String?
    }

    static let maxSuggestedTitles = 10

    private let databaseProvider: DatabaseProvider
    private let syncService: TaskSyncService
    private let calendarService: any CalendarService
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let config: RecommendationConfig

    init(
        databaseProvider: DatabaseProvider,
        syncService: TaskSyncService,
        calendarService: any CalendarService,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        config: RecommendationConfig = .standard
    ) {
        self.databaseProvider = databaseProvider
        self.syncService = syncService
        self.calendarService = calendarService
        self.calendar = calendar
        self.now = now
        self.config = config
    }

    func call(arguments: Arguments) async throws -> String {
        await syncService.syncIfAuthorized()

        let database: SQLiteDatabase
        do {
            database = try await databaseProvider.preparedDatabase()
        } catch {
            return "Fehler: Die lokale Verlaufsdatenbank ist nicht verfügbar."
        }
        let taskRepository = TaskRepository(database: database)
        let eventRepository = TaskEventRepository(database: database)
        let recommendationRepository = RecommendationRepository(database: database)
        let outcomeRepository = RecommendationOutcomeRepository(database: database)

        do {
            let allTasks = try await taskRepository.allTasks()
            guard !allTasks.isEmpty else {
                return "Es liegen noch keine Aufgaben vor. Frage zuerst nach den offenen Aufgaben, damit synchronisiert wird."
            }

            let currentDate = now()
            let query = (arguments.taskTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let task: Task
            let events: [TaskEvent]
            let analysis: TaskAnalysis
            var interventionHeader: String?

            if query.isEmpty {
                // intervention loop: rank open tasks by need.
                let openTasks = allTasks.filter { !$0.isCompleted }
                guard !openTasks.isEmpty else {
                    return "Es gibt derzeit keine offenen Aufgaben."
                }
                var pairs: [(task: Task, analysis: TaskAnalysis)] = []
                var eventsByTask: [UUID: [TaskEvent]] = [:]
                for candidate in openTasks {
                    let candidateEvents = try await eventRepository.events(forTaskID: candidate.id)
                    eventsByTask[candidate.id] = candidateEvents
                    pairs.append(
                        (candidate, TaskAnalyticsEngine.analyze(
                            task: candidate,
                            events: candidateEvents,
                            now: currentDate,
                            calendar: calendar
                        ))
                    )
                }
                let ranked = InterventionPlanner.rank(
                    pairs,
                    now: currentDate,
                    urgencyHorizon: config.urgencyHorizon
                )
                guard let top = ranked.first,
                      top.priority >= InterventionPlanner.interventionThreshold else {
                    return "Zurzeit braucht keine Aufgabe dringend eine Erinnerung (geprüft: \(openTasks.count) offene Aufgaben)."
                }
                task = top.task
                analysis = top.analysis
                events = eventsByTask[top.task.id] ?? []
                interventionHeader = "Aufgabe mit dem größten Handlungsbedarf: „\(top.task.title)“ (Priorität \(TaskStatisticsFormatter.percentText(top.priority)))"
            } else {
                let matches = TaskTitleResolver.matches(for: query, in: allTasks)
                if matches.isEmpty {
                    let openTitles = allTasks
                        .filter { !$0.isCompleted }
                        .map(\.title)
                        .prefix(Self.maxSuggestedTitles)
                    var text = "Keine Aufgabe mit dem Titel „\(query)“ gefunden."
                    if !openTitles.isEmpty {
                        text += " Offene Aufgaben: " + openTitles.joined(separator: ", ")
                    }
                    return text
                }
                if matches.count > 1 {
                    let titles = matches.map(\.title).prefix(Self.maxSuggestedTitles)
                    return "Mehrere Aufgaben passen zu „\(query)“: " + titles.joined(separator: ", ")
                        + ". Bitte den Titel genauer angeben."
                }
                task = matches[0]
                guard !task.isCompleted else {
                    return "„\(task.title)“ ist bereits erledigt — keine Erinnerung nötig."
                }
                events = try await eventRepository.events(forTaskID: task.id)
                analysis = TaskAnalyticsEngine.analyze(
                    task: task,
                    events: events,
                    now: currentDate,
                    calendar: calendar
                )
            }

            // Previous outcomes for this task adjust the confidence.
            var outcomes: [RecommendationOutcome] = []
            for stored in try await recommendationRepository.recommendations(forTaskID: task.id) {
                outcomes.append(contentsOf: try await outcomeRepository.outcomes(forRecommendationID: stored.id))
            }
            let outcomeSummary = RecommendationEvaluator.summary(from: outcomes)
            let effectiveness = ReminderEffectivenessAnalyzer.analyze(events: events, now: currentDate)

            let freeSlots = try await collectFreeSlots()
            guard let ranked = RecommendationEngine.recommendation(
                for: task,
                analysis: analysis,
                freeSlots: freeSlots,
                now: currentDate,
                calendar: calendar,
                config: config,
                outcomeSummary: outcomeSummary
            ) else {
                return "In den nächsten \(config.horizonDays) Tagen wurden keine passenden freien Zeiträume gefunden (Suchfenster \(config.wakingStartHour)–\(config.wakingEndHour) Uhr)."
            }

            // Persist what the user is about to see so outcomes can reference it.
            // Best effort: a failed insert must not withhold the answer.
            try? await recommendationRepository.insert(
                StoredRecommendation(recommendation: ranked.recommendation, createdAt: currentDate)
            )

            return Self.text(
                taskTitle: task.title,
                ranked: ranked,
                analysis: analysis,
                effectiveness: effectiveness,
                interventionHeader: interventionHeader,
                calendar: calendar
            )
        } catch let error as DatabaseError {
            return "Fehler beim Lesen der Daten: \(error.errorDescription ?? "Unbekannter Fehler.")"
        } catch let error as CalendarServiceError {
            return "Fehler beim Kalenderzugriff: \(error.errorDescription ?? "Unbekannter Fehler.")"
        }
    }

    /// Free slots per day inside waking hours over the search horizon;
    /// today starts no earlier than now.
    private func collectFreeSlots() async throws -> [DateInterval] {
        var slots: [DateInterval] = []
        let currentDate = now()
        let startOfToday = calendar.startOfDay(for: currentDate)
        for dayOffset in 0..<config.horizonDays {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                  let windowStart = calendar.date(
                    bySettingHour: config.wakingStartHour, minute: 0, second: 0, of: day
                  ),
                  let windowEnd = calendar.date(
                    bySettingHour: config.wakingEndHour, minute: 0, second: 0, of: day
                  ) else { continue }
            let from = dayOffset == 0 ? max(windowStart, currentDate) : windowStart
            guard windowEnd.timeIntervalSince(from) >= config.taskDuration else { continue }
            slots.append(
                contentsOf: try await calendarService.findFreeTime(
                    from: from,
                    to: windowEnd,
                    duration: config.taskDuration
                )
            )
        }
        return slots
    }

    static func text(
        taskTitle: String,
        ranked: RankedRecommendation,
        analysis: TaskAnalysis,
        effectiveness: ReminderEffectiveness,
        interventionHeader: String?,
        calendar: Calendar
    ) -> String {
        let recommendation = ranked.recommendation
        var lines: [String] = []
        if let interventionHeader {
            lines.append(interventionHeader)
        }
        lines.append("Empfehlung für „\(taskTitle)“:")
        lines.append(
            "• Vorgeschlagene Zeit: \(GermanDateText.dayText(for: recommendation.recommendedTime, calendar: calendar)), \(GermanDateText.timeText(recommendation.recommendedTime, calendar: calendar)) Uhr"
        )
        lines.append("• Konfidenz: \(TaskStatisticsFormatter.percentText(recommendation.confidence))")
        let reasons = recommendation.reasonCodes.map(Self.reasonText).joined(separator: ", ")
        lines.append("• Gründe: \(reasons)")

        var basis = "• Basis: Aufschiebe-Score \(TaskStatisticsFormatter.percentText(analysis.statistics.procrastinationScore))"
        basis += ", \(TaskStatisticsFormatter.completionsText(analysis.completionCount))"
        if let window = analysis.preferredWindow.window {
            basis += ", bevorzugt \(TaskStatisticsFormatter.windowText(window.name))"
        }
        lines.append(basis)

        if effectiveness.firedReminderCount > 0 {
            lines.append(
                "• Frühere Erinnerungen: \(effectiveness.completionsAfterReminder) von \(effectiveness.firedReminderCount) führten innerhalb eines Tages zur Erledigung"
            )
        }
        if let pattern = analysis.recurrence.pattern {
            // Behavioral recurrence stays an observation — never an automatic action.
            lines.append(
                "• Beobachtung: Du erledigst diese Aufgabe \(TaskStatisticsFormatter.patternText(pattern)). Eine feste Wiederholung legst du bei Bedarf selbst in Apple Erinnerungen an."
            )
        }

        if analysis.completionCount < 3 {
            lines.append(TaskStatisticsFormatter.lowDataHint)
        }
        return lines.joined(separator: "\n")
    }

    static func reasonText(_ reason: RecommendationReason) -> String {
        switch reason {
        case .frequentlyPostponed: return "häufig aufgeschoben"
        case .deadlineApproaching: return "Frist rückt näher"
        case .historicallySuccessfulTime: return "historisch erfolgreiche Zeit"
        case .currentlyFree: return "Kalender ist frei"
        case .overdue: return "überfällig"
        case .recurringPattern: return "wiederkehrendes Muster"
        }
    }
}
