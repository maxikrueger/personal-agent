import XCTest
@testable import PersonalAgent

@MainActor
final class AgentViewModelTests: XCTestCase {
    private func makeViewModel(
        agent: FakeAgentController,
        availability: AgentModelAvailability = .available
    ) -> AgentViewModel {
        AgentViewModel(agent: agent, availability: { availability })
    }

    func testSendAppendsUserAndAgentMessages() async {
        let agent = FakeAgentController()
        agent.result = .success("Du hast 2 offene Aufgaben.")
        let viewModel = makeViewModel(agent: agent)

        await viewModel.send("Welche offenen Aufgaben habe ich?")

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[0].role, .user)
        XCTAssertEqual(viewModel.messages[0].text, "Welche offenen Aufgaben habe ich?")
        XCTAssertEqual(viewModel.messages[1].role, .agent)
        XCTAssertEqual(viewModel.messages[1].text, "Du hast 2 offene Aufgaben.")
        XCTAssertEqual(agent.receivedMessages, ["Welche offenen Aufgaben habe ich?"])
        XCTAssertFalse(viewModel.isResponding)
    }

    func testAgentErrorBecomesAgentMessage() async {
        let agent = FakeAgentController()
        agent.result = .failure(AgentError.responseFailed(details: "Modell überlastet"))
        let viewModel = makeViewModel(agent: agent)

        await viewModel.send("Hallo")

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages[1].role, .agent)
        XCTAssertTrue(viewModel.messages[1].text.contains("Modell überlastet"))
        XCTAssertFalse(viewModel.isResponding)
    }

    func testModelUnavailableErrorShowsReason() async {
        let agent = FakeAgentController()
        agent.result = .failure(AgentError.modelUnavailable(reason: "Apple Intelligence ist nicht aktiviert."))
        let viewModel = makeViewModel(agent: agent)

        await viewModel.send("Hallo")

        XCTAssertEqual(viewModel.messages[1].text, "Apple Intelligence ist nicht aktiviert.")
    }

    func testUnknownErrorGetsGenericText() async {
        struct DummyError: Error {}
        let agent = FakeAgentController()
        agent.result = .failure(DummyError())
        let viewModel = makeViewModel(agent: agent)

        await viewModel.send("Hallo")

        XCTAssertTrue(viewModel.messages[1].text.contains("schiefgelaufen"))
    }

    func testSendCurrentInputIgnoresWhitespaceOnlyInput() {
        let agent = FakeAgentController()
        let viewModel = makeViewModel(agent: agent)
        viewModel.inputText = "   \n"

        viewModel.sendCurrentInput()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertFalse(viewModel.canSend)
    }

    func testCanSendReflectsInputAndRespondingState() {
        let agent = FakeAgentController()
        let viewModel = makeViewModel(agent: agent)

        XCTAssertFalse(viewModel.canSend)
        viewModel.inputText = "Hallo"
        XCTAssertTrue(viewModel.canSend)
    }

    func testRefreshAvailabilityShowsReasonWhenUnavailable() {
        let agent = FakeAgentController()
        let viewModel = makeViewModel(
            agent: agent,
            availability: .unavailable(reason: "Testgrund")
        )

        viewModel.refreshAvailability()

        XCTAssertEqual(viewModel.availabilityNote, "Testgrund")
    }

    func testRefreshAvailabilityClearsNoteWhenAvailable() {
        let agent = FakeAgentController()
        let viewModel = makeViewModel(agent: agent, availability: .available)

        viewModel.refreshAvailability()

        XCTAssertNil(viewModel.availabilityNote)
    }

    // MARK: - Notification proposal flow

    private func makeProposalCenter() async throws -> (NotificationProposalCenter, FakeNotificationService) {
        let notifications = FakeNotificationService()
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await provider.preparedDatabase()
        let center = NotificationProposalCenter(
            notificationService: notifications,
            databaseProvider: provider,
            calendar: utcCalendar(),
            now: { Date(timeIntervalSince1970: 1_788_098_400) }
        )
        return (center, notifications)
    }

    private func makeProposal() -> NotificationProposal {
        let proposalID = UUID()
        return NotificationProposal(
            id: proposalID,
            taskID: nil,
            notificationID: NotificationIdentifier.adhoc(proposalID),
            notificationTitle: "Erinnerung",
            body: "Müll rausbringen",
            fireDate: Date(timeIntervalSince1970: 1_788_198_400)
        )
    }

    func testPendingProposalIsExposedAndConfirmationAppendsMessage() async throws {
        let (center, notifications) = try await makeProposalCenter()
        let viewModel = AgentViewModel(
            agent: FakeAgentController(),
            availability: { .available },
            proposalCenter: center
        )
        _ = center.propose(makeProposal())
        XCTAssertNotNil(viewModel.pendingNotificationProposal)

        await viewModel.confirmPendingNotification()

        XCTAssertNil(viewModel.pendingNotificationProposal)
        XCTAssertTrue(viewModel.messages.last?.text.contains("bestätigt und geplant") ?? false)
        XCTAssertEqual(notifications.scheduled.count, 1)
    }

    func testDecliningProposalAppendsMessageAndSchedulesNothing() async throws {
        let (center, notifications) = try await makeProposalCenter()
        let viewModel = AgentViewModel(
            agent: FakeAgentController(),
            availability: { .available },
            proposalCenter: center
        )
        _ = center.propose(makeProposal())

        await viewModel.declinePendingNotification()

        XCTAssertNil(viewModel.pendingNotificationProposal)
        XCTAssertTrue(viewModel.messages.last?.text.contains("keine Erinnerung") ?? false)
        XCTAssertTrue(notifications.scheduled.isEmpty)
    }

    func testProposalActionsWithoutCenterAreNoOps() async {
        let viewModel = makeViewModel(agent: FakeAgentController())

        XCTAssertNil(viewModel.pendingNotificationProposal)
        await viewModel.confirmPendingNotification()
        await viewModel.declinePendingNotification()

        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    // MARK: - Reminder creation flow

    private func makeReminderCreationCenter() async throws -> (ReminderCreationCenter, FakeReminderService) {
        let reminders = FakeReminderService()
        reminders.fullAccess = false
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await provider.preparedDatabase()
        let syncService = TaskSyncService(reminderService: reminders, databaseProvider: provider)
        let center = ReminderCreationCenter(
            reminderService: reminders,
            syncService: syncService,
            calendar: utcCalendar()
        )
        return (center, reminders)
    }

    func testReminderCreationConfirmAppendsMessage() async throws {
        let (center, reminders) = try await makeReminderCreationCenter()
        let viewModel = AgentViewModel(
            agent: FakeAgentController(),
            availability: { .available },
            reminderCreationCenter: center
        )
        _ = center.propose(ReminderCreationProposal(id: UUID(), title: "Neu", notes: nil, dueDate: nil))
        XCTAssertNotNil(viewModel.pendingReminderCreationProposal)

        await viewModel.confirmPendingReminderCreation()

        XCTAssertNil(viewModel.pendingReminderCreationProposal)
        XCTAssertTrue(viewModel.messages.last?.text.contains("angelegt") ?? false)
        XCTAssertEqual(reminders.createdReminders.count, 1)
    }

    func testReminderCreationDeclineAppendsMessage() async throws {
        let (center, reminders) = try await makeReminderCreationCenter()
        let viewModel = AgentViewModel(
            agent: FakeAgentController(),
            availability: { .available },
            reminderCreationCenter: center
        )
        _ = center.propose(ReminderCreationProposal(id: UUID(), title: "Neu", notes: nil, dueDate: nil))

        viewModel.declinePendingReminderCreation()

        XCTAssertNil(viewModel.pendingReminderCreationProposal)
        XCTAssertTrue(viewModel.messages.last?.text.contains("keine Aufgabe") ?? false)
        XCTAssertTrue(reminders.createdReminders.isEmpty)
    }

    func testReminderCreationActionsWithoutCenterAreNoOps() async {
        let viewModel = makeViewModel(agent: FakeAgentController())

        XCTAssertNil(viewModel.pendingReminderCreationProposal)
        await viewModel.confirmPendingReminderCreation()
        viewModel.declinePendingReminderCreation()

        XCTAssertTrue(viewModel.messages.isEmpty)
    }
}
