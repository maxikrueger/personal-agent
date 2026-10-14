import Foundation
import Observation

/// Application-level gate for the confirmation flow: tools deposit
/// proposals here, the UI shows them, and only an explicit user confirmation
/// schedules the notification. The model can never bypass this.
@MainActor
@Observable
final class NotificationProposalCenter {
    private(set) var pending: NotificationProposal?

    private let notificationService: any NotificationService
    private let databaseProvider: DatabaseProvider
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        notificationService: any NotificationService,
        databaseProvider: DatabaseProvider,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.notificationService = notificationService
        self.databaseProvider = databaseProvider
        self.calendar = calendar
        self.now = now
    }

    /// One proposal at a time; returns false when one is already waiting.
    func propose(_ proposal: NotificationProposal) -> Bool {
        guard pending == nil else { return false }
        pending = proposal
        return true
    }

    /// Returns user-facing German status text for the chat (failures are
    /// explained, never crash).
    func confirmPending() async -> String {
        guard let proposal = pending else {
            return "Es liegt kein Erinnerungs-Vorschlag vor."
        }
        pending = nil
        do {
            try await notificationService.requestAccess()
            try await notificationService.schedule(
                id: proposal.notificationID,
                title: proposal.notificationTitle,
                body: proposal.body,
                date: proposal.fireDate
            )
        } catch {
            let details = (error as? LocalizedError)?.errorDescription ?? "Unbekannter Fehler."
            return "Die Erinnerung konnte nicht geplant werden: \(details)"
        }
        await recordScheduledEvent(for: proposal)
        await recordOutcome(.accepted, for: proposal)
        let day = GermanDateText.dayText(for: proposal.fireDate, calendar: calendar)
        let time = GermanDateText.timeText(proposal.fireDate, calendar: calendar)
        return "Erinnerung bestätigt und geplant für \(day), \(time) Uhr."
    }

    func declinePending() async -> String {
        guard let proposal = pending else {
            return "Es liegt kein Erinnerungs-Vorschlag vor."
        }
        pending = nil
        await recordOutcome(.rejected, for: proposal)
        return "Okay, ich habe keine Erinnerung geplant."
    }

    /// A proposal reacted to within this window after a recommendation counts
    /// as that recommendation's accepted/rejected outcome.
    static let recommendationLinkWindow: TimeInterval = 3600

    /// Link the user's reaction to the most recent recommendation for the
    /// same task. Best effort; ad-hoc proposals have no task and record nothing.
    private func recordOutcome(_ type: OutcomeType, for proposal: NotificationProposal) async {
        guard let taskID = proposal.taskID else { return }
        do {
            let database = try await databaseProvider.preparedDatabase()
            let recommendationRepository = RecommendationRepository(database: database)
            let outcomeRepository = RecommendationOutcomeRepository(database: database)
            guard let recommendation = try await recommendationRepository.latest(
                forTaskID: taskID,
                since: now().addingTimeInterval(-Self.recommendationLinkWindow)
            ) else { return }
            let existing = try await outcomeRepository.outcomes(forRecommendationID: recommendation.id)
            guard !existing.contains(where: { $0.outcome == .accepted || $0.outcome == .rejected }) else {
                return
            }
            try await outcomeRepository.insert(
                RecommendationOutcome(
                    recommendationID: recommendation.id,
                    outcome: type,
                    timestamp: now()
                )
            )
        } catch {
            // Outcome capture must never break the confirmation flow.
        }
    }

    /// `reminderScheduled` — only for task-bound proposals; best effort:
    /// the notification is already scheduled even if history writing fails.
    private func recordScheduledEvent(for proposal: NotificationProposal) async {
        guard let taskID = proposal.taskID else { return }
        do {
            let database = try await databaseProvider.preparedDatabase()
            try await TaskEventRepository(database: database).insert(
                TaskEvent(
                    taskID: taskID,
                    type: .reminderScheduled,
                    timestamp: now(),
                    metadata: [
                        "notificationID": proposal.notificationID,
                        "fireDate": proposal.fireDate.formatted(.iso8601),
                    ]
                )
            )
        } catch {
            // Intentionally swallowed; scheduling itself succeeded.
        }
    }
}
