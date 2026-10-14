import XCTest
@testable import PersonalAgent

@MainActor
final class NotificationProposalCenterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_098_400)
    private let fireDate = Date(timeIntervalSince1970: 1_788_198_400)

    private struct Environment {
        let center: NotificationProposalCenter
        let notifications: FakeNotificationService
        let taskRepository: TaskRepository
        let eventRepository: TaskEventRepository
        let recommendationRepository: RecommendationRepository
        let outcomeRepository: RecommendationOutcomeRepository
    }

    private func makeEnvironment() async throws -> Environment {
        let notifications = FakeNotificationService()
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await provider.preparedDatabase()
        let fixedNow = now
        let center = NotificationProposalCenter(
            notificationService: notifications,
            databaseProvider: provider,
            calendar: utcCalendar(),
            now: { fixedNow }
        )
        return Environment(
            center: center,
            notifications: notifications,
            taskRepository: TaskRepository(database: database),
            eventRepository: TaskEventRepository(database: database),
            recommendationRepository: RecommendationRepository(database: database),
            outcomeRepository: RecommendationOutcomeRepository(database: database)
        )
    }

    private func makeProposal(taskID: UUID? = nil) -> NotificationProposal {
        let proposalID = UUID()
        return NotificationProposal(
            id: proposalID,
            taskID: taskID,
            notificationID: taskID.map(NotificationIdentifier.forTask)
                ?? NotificationIdentifier.adhoc(proposalID),
            notificationTitle: "Erinnerung",
            body: "Steuer machen",
            fireDate: fireDate
        )
    }

    func testProposeStoresPendingAndRejectsSecond() async throws {
        let environment = try await makeEnvironment()
        let first = makeProposal()
        let second = makeProposal()

        XCTAssertTrue(environment.center.propose(first))
        XCTAssertFalse(environment.center.propose(second))
        XCTAssertEqual(environment.center.pending, first)
    }

    func testDeclineClearsPending() async throws {
        let environment = try await makeEnvironment()
        _ = environment.center.propose(makeProposal())

        let status = await environment.center.declinePending()

        XCTAssertNil(environment.center.pending)
        XCTAssertTrue(status.contains("keine Erinnerung"))
        XCTAssertTrue(environment.notifications.scheduled.isEmpty)
    }

    // MARK: - Outcome capture

    private func seedRecommendation(
        _ environment: Environment,
        taskID: UUID,
        createdAt: Date
    ) async throws -> StoredRecommendation {
        let stored = StoredRecommendation(
            id: UUID(),
            taskID: taskID,
            recommendedTime: fireDate,
            confidence: 0.5,
            reasonCodes: [.currentlyFree],
            createdAt: createdAt
        )
        try await environment.recommendationRepository.insert(stored)
        return stored
    }

    func testConfirmRecordsAcceptedOutcomeForRecentRecommendation() async throws {
        let environment = try await makeEnvironment()
        let task = makeTask(title: "Steuer")
        try await environment.taskRepository.upsert(task, updatedAt: now)
        let stored = try await seedRecommendation(environment, taskID: task.id, createdAt: now.addingTimeInterval(-600))
        _ = environment.center.propose(makeProposal(taskID: task.id))

        _ = await environment.center.confirmPending()

        let outcomes = try await environment.outcomeRepository.outcomes(forRecommendationID: stored.id)
        XCTAssertEqual(outcomes.map(\.outcome), [.accepted])
        XCTAssertEqual(outcomes[0].timestamp, now)
    }

    func testDeclineRecordsRejectedOutcome() async throws {
        let environment = try await makeEnvironment()
        let task = makeTask(title: "Steuer")
        try await environment.taskRepository.upsert(task, updatedAt: now)
        let stored = try await seedRecommendation(environment, taskID: task.id, createdAt: now.addingTimeInterval(-600))
        _ = environment.center.propose(makeProposal(taskID: task.id))

        _ = await environment.center.declinePending()

        let outcomes = try await environment.outcomeRepository.outcomes(forRecommendationID: stored.id)
        XCTAssertEqual(outcomes.map(\.outcome), [.rejected])
    }

    func testStaleRecommendationIsNotLinked() async throws {
        let environment = try await makeEnvironment()
        let task = makeTask(title: "Steuer")
        try await environment.taskRepository.upsert(task, updatedAt: now)
        let stored = try await seedRecommendation(
            environment,
            taskID: task.id,
            createdAt: now.addingTimeInterval(-2 * NotificationProposalCenter.recommendationLinkWindow)
        )
        _ = environment.center.propose(makeProposal(taskID: task.id))

        _ = await environment.center.confirmPending()

        let outcomes = try await environment.outcomeRepository.outcomes(forRecommendationID: stored.id)
        XCTAssertTrue(outcomes.isEmpty)
    }

    func testConfirmWithoutPendingExplainsItself() async throws {
        let environment = try await makeEnvironment()

        let status = await environment.center.confirmPending()

        XCTAssertTrue(status.contains("kein Erinnerungs-Vorschlag"))
    }

    func testConfirmSchedulesAndRecordsTaskEvent() async throws {
        let environment = try await makeEnvironment()
        let task = makeTask(title: "Steuer")
        try await environment.taskRepository.upsert(task, updatedAt: now)
        let proposal = makeProposal(taskID: task.id)
        _ = environment.center.propose(proposal)

        let status = await environment.center.confirmPending()

        XCTAssertNil(environment.center.pending)
        XCTAssertTrue(status.contains("bestätigt und geplant"))
        XCTAssertEqual(environment.notifications.scheduled.count, 1)
        XCTAssertEqual(environment.notifications.scheduled[0].id, proposal.notificationID)
        XCTAssertEqual(environment.notifications.scheduled[0].body, "Steuer machen")
        XCTAssertEqual(environment.notifications.scheduled[0].date, fireDate)

        let events = try await environment.eventRepository.events(forTaskID: task.id)
        XCTAssertEqual(events.map(\.type), [.reminderScheduled])
        XCTAssertEqual(events[0].metadata["notificationID"], proposal.notificationID)
        XCTAssertEqual(events[0].metadata["fireDate"], fireDate.formatted(.iso8601))
        XCTAssertEqual(events[0].timestamp, now)
    }

    func testAdhocConfirmSchedulesWithoutHistoryEvent() async throws {
        let environment = try await makeEnvironment()
        _ = environment.center.propose(makeProposal(taskID: nil))

        let status = await environment.center.confirmPending()

        XCTAssertTrue(status.contains("bestätigt und geplant"))
        XCTAssertEqual(environment.notifications.scheduled.count, 1)
        let events = try await environment.eventRepository.allEvents()
        XCTAssertTrue(events.isEmpty)
    }

    func testDeniedAccessProducesFactualErrorAndSchedulesNothing() async throws {
        let environment = try await makeEnvironment()
        environment.notifications.accessResult = .failure(NotificationServiceError.accessDenied)
        _ = environment.center.propose(makeProposal())

        let status = await environment.center.confirmPending()

        XCTAssertTrue(status.contains("konnte nicht geplant werden"))
        XCTAssertTrue(status.contains("Mitteilungen"))
        XCTAssertTrue(environment.notifications.scheduled.isEmpty)
        XCTAssertNil(environment.center.pending)
    }
}
