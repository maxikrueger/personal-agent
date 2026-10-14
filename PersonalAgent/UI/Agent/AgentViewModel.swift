import Foundation
import Observation

@MainActor
@Observable
final class AgentViewModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isResponding = false
    private(set) var availabilityNote: String?
    var inputText = ""

    private let agent: any AgentControllerProtocol
    private let availability: @Sendable () -> AgentModelAvailability
    private let proposalCenter: NotificationProposalCenter?
    private let reminderCreationCenter: ReminderCreationCenter?

    init(
        agent: any AgentControllerProtocol,
        availability: @escaping @Sendable () -> AgentModelAvailability,
        proposalCenter: NotificationProposalCenter? = nil,
        reminderCreationCenter: ReminderCreationCenter? = nil
    ) {
        self.agent = agent
        self.availability = availability
        self.proposalCenter = proposalCenter
        self.reminderCreationCenter = reminderCreationCenter
    }

    var pendingReminderCreationProposal: ReminderCreationProposal? {
        reminderCreationCenter?.pending
    }

    func confirmPendingReminderCreationTapped() {
        _Concurrency.Task {
            await confirmPendingReminderCreation()
        }
    }

    func confirmPendingReminderCreation() async {
        guard let reminderCreationCenter else { return }
        let status = await reminderCreationCenter.confirmPending()
        messages.append(ChatMessage(role: .agent, text: status))
    }

    func declinePendingReminderCreation() {
        guard let reminderCreationCenter else { return }
        let status = reminderCreationCenter.declinePending()
        messages.append(ChatMessage(role: .agent, text: status))
    }

    var pendingNotificationProposal: NotificationProposal? {
        proposalCenter?.pending
    }

    func confirmPendingNotificationTapped() {
        _Concurrency.Task {
            await confirmPendingNotification()
        }
    }

    func confirmPendingNotification() async {
        guard let proposalCenter else { return }
        let status = await proposalCenter.confirmPending()
        messages.append(ChatMessage(role: .agent, text: status))
    }

    func declinePendingNotificationTapped() {
        _Concurrency.Task {
            await declinePendingNotification()
        }
    }

    func declinePendingNotification() async {
        guard let proposalCenter else { return }
        let status = await proposalCenter.declinePending()
        messages.append(ChatMessage(role: .agent, text: status))
    }

    var canSend: Bool {
        !trimmedInput.isEmpty && !isResponding
    }

    func refreshAvailability() {
        if case .unavailable(let reason) = availability() {
            availabilityNote = reason
        } else {
            availabilityNote = nil
        }
    }

    func sendCurrentInput() {
        let text = trimmedInput
        guard !text.isEmpty, !isResponding else { return }
        inputText = ""
        _Concurrency.Task {
            await send(text)
        }
    }

    func send(_ text: String) async {
        guard !isResponding else { return }
        messages.append(ChatMessage(role: .user, text: text))
        isResponding = true
        defer { isResponding = false }
        do {
            let reply = try await agent.send(text)
            messages.append(ChatMessage(role: .agent, text: reply))
        } catch {
            messages.append(ChatMessage(role: .agent, text: Self.errorText(for: error)))
        }
    }

    static func errorText(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return "Entschuldigung, da ist etwas schiefgelaufen. Bitte versuche es erneut."
    }

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
