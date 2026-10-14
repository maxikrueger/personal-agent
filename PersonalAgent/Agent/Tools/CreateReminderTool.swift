import Foundation
import FoundationModels

/// MUTATION tool: validates the model's proposal
/// for a new Apple Reminder and hands it to the app-level confirmation gate.
/// It never creates anything itself.
struct CreateReminderTool: Tool {
    let name = "createReminder"
    let description = """
    Schlägt eine neue Aufgabe in Apple Erinnerungen vor. Legt selbst nichts an: \
    Der Nutzer muss den Vorschlag in der App bestätigen. dueDaysFromToday ist relativ zu heute (0 = heute).
    """

    @Generable
    struct Arguments {
        @Guide(description: "Titel der neuen Aufgabe.")
        var title: String
        @Guide(description: "Optionale Notiz zur Aufgabe.")
        var notes: String?
        @Guide(description: "Fälligkeit: Tag relativ zu heute (0 = heute, 1 = morgen, …). Weglassen für eine Aufgabe ohne Fälligkeit.")
        var dueDaysFromToday: Int?
        @Guide(description: "Stunde der Fälligkeit, 0–23 (Standard: 9). Nur zusammen mit dueDaysFromToday.")
        var dueHour: Int?
    }

    static let maxTitleLength = 100
    static let maxNotesLength = 500
    static let maxDaysAhead = 365
    static let defaultDueHour = 9

    private let proposalCenter: ReminderCreationCenter
    private let databaseProvider: DatabaseProvider
    private let syncService: TaskSyncService
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        proposalCenter: ReminderCreationCenter,
        databaseProvider: DatabaseProvider,
        syncService: TaskSyncService,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.proposalCenter = proposalCenter
        self.databaseProvider = databaseProvider
        self.syncService = syncService
        self.calendar = calendar
        self.now = now
    }

    func call(arguments: Arguments) async throws -> String {
        // Validate everything the model provided.
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return "Bitte einen Titel für die Aufgabe angeben."
        }
        guard title.count <= Self.maxTitleLength else {
            return "Der Titel ist zu lang (maximal \(Self.maxTitleLength) Zeichen)."
        }
        let notes = arguments.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let notes, notes.count > Self.maxNotesLength {
            return "Die Notiz ist zu lang (maximal \(Self.maxNotesLength) Zeichen)."
        }

        // Resolve the optional due date app-side, device timezone.
        var dueDate: Date?
        if let dueDaysFromToday = arguments.dueDaysFromToday {
            guard (0...Self.maxDaysAhead).contains(dueDaysFromToday) else {
                return "Ungültiger Tag: dueDaysFromToday muss zwischen 0 (heute) und \(Self.maxDaysAhead) liegen."
            }
            let dueHour = arguments.dueHour ?? Self.defaultDueHour
            guard (0...23).contains(dueHour) else {
                return "Ungültige Stunde: dueHour muss zwischen 0 und 23 liegen."
            }
            guard let day = calendar.date(
                byAdding: .day,
                value: dueDaysFromToday,
                to: calendar.startOfDay(for: now())
            ),
                let resolved = calendar.date(bySettingHour: dueHour, minute: 0, second: 0, of: day)
            else {
                return "Die Fälligkeit konnte nicht berechnet werden."
            }
            dueDate = resolved
        }

        // Avoid silent duplicates: an open task with the same title already exists.
        await syncService.syncIfAuthorized()
        do {
            let database = try await databaseProvider.preparedDatabase()
            let openTasks = try await TaskRepository(database: database).allTasks()
                .filter { !$0.isCompleted }
            if openTasks.contains(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                return "Es gibt bereits eine offene Aufgabe „\(title)“. Keine neue Aufgabe vorgeschlagen."
            }
        } catch let error as DatabaseError {
            return "Fehler beim Lesen der Daten: \(error.errorDescription ?? "Unbekannter Fehler.")"
        }

        let proposal = ReminderCreationProposal(
            id: UUID(),
            title: title,
            notes: notes?.isEmpty == true ? nil : notes,
            dueDate: dueDate
        )
        let accepted = await proposalCenter.propose(proposal)
        guard accepted else {
            return "Es wartet bereits ein Aufgaben-Vorschlag auf Bestätigung. Bitte zuerst bestätigen oder ablehnen."
        }
        var text = "Vorschlag erstellt: Aufgabe „\(title)“"
        if let dueDate {
            text += ", fällig \(GermanDateText.dayText(for: dueDate, calendar: calendar)), \(GermanDateText.timeText(dueDate, calendar: calendar)) Uhr"
        }
        return text + ". Es wurde noch nichts angelegt; der Nutzer muss den Vorschlag in der App bestätigen."
    }
}
