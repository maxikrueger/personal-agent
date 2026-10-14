import Foundation
import Observation

/// Confirmation gate for creating Apple Reminders, following the
/// `NotificationProposalCenter` pattern: tools deposit proposals, only the
/// user's tap executes the mutation.
@MainActor
@Observable
final class ReminderCreationCenter {
    private(set) var pending: ReminderCreationProposal?

    private let reminderService: any ReminderService
    private let syncService: TaskSyncService
    private let calendar: Calendar

    init(
        reminderService: any ReminderService,
        syncService: TaskSyncService,
        calendar: Calendar = .current
    ) {
        self.reminderService = reminderService
        self.syncService = syncService
        self.calendar = calendar
    }

    /// One proposal at a time; returns false when one is already waiting.
    func propose(_ proposal: ReminderCreationProposal) -> Bool {
        guard pending == nil else { return false }
        pending = proposal
        return true
    }

    /// Returns user-facing German status text for the chat.
    func confirmPending() async -> String {
        guard let proposal = pending else {
            return "Es liegt kein Aufgaben-Vorschlag vor."
        }
        pending = nil
        do {
            _ = try await reminderService.createReminder(
                title: proposal.title,
                notes: proposal.notes,
                dueDate: proposal.dueDate
            )
        } catch {
            let details = (error as? LocalizedError)?.errorDescription ?? "Unbekannter Fehler."
            return "Die Aufgabe konnte nicht angelegt werden: \(details)"
        }
        // Pull the new reminder into the local history right away.
        await syncService.syncIfAuthorized()
        var text = "Aufgabe „\(proposal.title)“ in Apple Erinnerungen angelegt"
        if let dueDate = proposal.dueDate {
            text += " (fällig \(GermanDateText.dayText(for: dueDate, calendar: calendar)), \(GermanDateText.timeText(dueDate, calendar: calendar)) Uhr)"
        }
        return text + "."
    }

    func declinePending() -> String {
        guard pending != nil else {
            return "Es liegt kein Aufgaben-Vorschlag vor."
        }
        pending = nil
        return "Okay, ich habe keine Aufgabe angelegt."
    }
}
