import Foundation
import FoundationModels

/// MUTATION tool: validates the model's proposal and
/// hands it to the app-level confirmation gate. It never schedules anything
/// itself — without the user's tap in the app, no notification exists.
struct ScheduleNotificationTool: Tool {
    let name = "scheduleNotification"
    let description = """
    Schlägt eine iOS-Erinnerung vor. Plant selbst nichts: Der Nutzer muss den Vorschlag \
    in der App bestätigen. daysFromToday ist relativ zu heute (0 = heute, 1 = morgen). \
    Für Angaben wie „in 10 Minuten“ minutesFromNow setzen; dann werden daysFromToday, hour und minute ignoriert.
    """

    @Generable
    struct Arguments {
        @Guide(description: "Kurzer Erinnerungstext — woran erinnert werden soll.")
        var message: String
        @Guide(description: "Titel einer bestehenden Aufgabe, falls sich die Erinnerung darauf bezieht; sonst weglassen.")
        var taskTitle: String?
        @Guide(description: "Tag relativ zu heute: 0 = heute, 1 = morgen, 2 = übermorgen, …")
        var daysFromToday: Int
        @Guide(description: "Stunde der Erinnerung, 0–23.")
        var hour: Int
        @Guide(description: "Minute der Erinnerung, 0–59 (Standard: 0).")
        var minute: Int?
        @Guide(description: "Nur für relative Angaben wie „in 10 Minuten“: Minuten ab jetzt, 1–1440. Sonst weglassen.")
        var minutesFromNow: Int?
    }

    static let maxDaysAhead = 60
    static let maxMessageLength = 200
    static let maxSuggestedTitles = 10
    /// Minimum lead time so "in the past" and "right now" proposals are rejected.
    static let minimumLeadTime: TimeInterval = 60
    /// Upper bound for relative times ("in 10 Minuten"): one day.
    static let maxMinutesFromNow = 1440

    private let databaseProvider: DatabaseProvider
    private let syncService: TaskSyncService
    private let proposalCenter: NotificationProposalCenter
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        databaseProvider: DatabaseProvider,
        syncService: TaskSyncService,
        proposalCenter: NotificationProposalCenter,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.databaseProvider = databaseProvider
        self.syncService = syncService
        self.proposalCenter = proposalCenter
        self.calendar = calendar
        self.now = now
    }

    func call(arguments: Arguments) async throws -> String {
        let message = arguments.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return "Bitte angeben, woran erinnert werden soll (message)."
        }
        guard message.count <= Self.maxMessageLength else {
            return "Der Erinnerungstext ist zu lang (maximal \(Self.maxMessageLength) Zeichen)."
        }

        let currentDate = now()
        let fireDate: Date
        if let minutesFromNow = arguments.minutesFromNow {
            // Relative time: the app does the arithmetic, not the model.
            guard (1...Self.maxMinutesFromNow).contains(minutesFromNow) else {
                return "Ungültige Angabe: minutesFromNow muss zwischen 1 und \(Self.maxMinutesFromNow) liegen."
            }
            fireDate = currentDate.addingTimeInterval(TimeInterval(minutesFromNow * 60))
        } else {
            switch absoluteFireDate(for: arguments, now: currentDate) {
            case .success(let date): fireDate = date
            case .failure(let problem): return problem.message
            }
        }

        return try await propose(message: message, taskTitle: arguments.taskTitle, fireDate: fireDate)
    }

    private struct ValidationProblem: Error {
        let message: String
    }

    /// Validates the absolute day/hour/minute arguments and resolves them to a
    /// date in the device timezone.
    private func absoluteFireDate(for arguments: Arguments, now currentDate: Date) -> Result<Date, ValidationProblem> {
        guard (0...Self.maxDaysAhead).contains(arguments.daysFromToday) else {
            return .failure(ValidationProblem(
                message: "Ungültiger Tag: daysFromToday muss zwischen 0 (heute) und \(Self.maxDaysAhead) liegen."
            ))
        }
        guard (0...23).contains(arguments.hour) else {
            return .failure(ValidationProblem(message: "Ungültige Stunde: hour muss zwischen 0 und 23 liegen."))
        }
        let minute = arguments.minute ?? 0
        guard (0...59).contains(minute) else {
            return .failure(ValidationProblem(message: "Ungültige Minute: minute muss zwischen 0 und 59 liegen."))
        }
        guard let day = calendar.date(
            byAdding: .day,
            value: arguments.daysFromToday,
            to: calendar.startOfDay(for: currentDate)
        ),
            let fireDate = calendar.date(bySettingHour: arguments.hour, minute: minute, second: 0, of: day)
        else {
            return .failure(ValidationProblem(message: "Der Zeitpunkt konnte nicht berechnet werden."))
        }
        guard fireDate > currentDate.addingTimeInterval(Self.minimumLeadTime) else {
            return .failure(ValidationProblem(
                message: "Der Zeitpunkt liegt in der Vergangenheit oder ist zu knapp. Bitte einen späteren Zeitpunkt wählen."
            ))
        }
        return .success(fireDate)
    }

    private func propose(message: String, taskTitle: String?, fireDate: Date) async throws -> String {
        // Optional task binding, validated against stored tasks.
        var taskID: UUID?
        var boundTaskTitle: String?
        let rawTitle = taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !rawTitle.isEmpty {
            await syncService.syncIfAuthorized()
            do {
                let database = try await databaseProvider.preparedDatabase()
                let allTasks = try await TaskRepository(database: database).allTasks()
                let matches = TaskTitleResolver.matches(for: rawTitle, in: allTasks)
                if matches.isEmpty {
                    return "Keine Aufgabe mit dem Titel „\(rawTitle)“ gefunden. Lass taskTitle weg, um eine freie Erinnerung vorzuschlagen."
                }
                if matches.count > 1 {
                    let titles = matches.map(\.title).prefix(Self.maxSuggestedTitles)
                    return "Mehrere Aufgaben passen zu „\(rawTitle)“: " + titles.joined(separator: ", ")
                        + ". Bitte den Titel genauer angeben."
                }
                taskID = matches[0].id
                boundTaskTitle = matches[0].title
            } catch let error as DatabaseError {
                return "Fehler beim Lesen der Daten: \(error.errorDescription ?? "Unbekannter Fehler.")"
            }
        }

        let proposalID = UUID()
        let proposal = NotificationProposal(
            id: proposalID,
            taskID: taskID,
            notificationID: taskID.map(NotificationIdentifier.forTask) ?? NotificationIdentifier.adhoc(proposalID),
            notificationTitle: boundTaskTitle.map { "Erinnerung: \($0)" } ?? "Erinnerung",
            body: message,
            fireDate: fireDate
        )

        let accepted = await proposalCenter.propose(proposal)
        guard accepted else {
            return "Es wartet bereits ein Erinnerungs-Vorschlag auf Bestätigung. Bitte zuerst bestätigen oder ablehnen."
        }
        let day2 = GermanDateText.dayText(for: fireDate, calendar: calendar)
        let time = GermanDateText.timeText(fireDate, calendar: calendar)
        return "Vorschlag erstellt: \(day2), \(time) Uhr — „\(message)“. Es wurde noch nichts geplant; der Nutzer muss den Vorschlag in der App bestätigen."
    }
}
