import XCTest
@testable import PersonalAgent

final class InsightsBuilderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_098_400)

    private struct Environment {
        let builder: InsightsBuilder
        let reminders: FakeReminderService
        let taskRepository: TaskRepository
        let eventRepository: TaskEventRepository
        let recommendationRepository: RecommendationRepository
        let outcomeRepository: RecommendationOutcomeRepository
    }

    private func makeEnvironment(authorized: Bool = false) async throws -> Environment {
        let reminders = FakeReminderService()
        reminders.fullAccess = authorized
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await provider.preparedDatabase()
        let syncService = TaskSyncService(reminderService: reminders, databaseProvider: provider)
        let fixedNow = now
        let builder = InsightsBuilder(
            databaseProvider: provider,
            syncService: syncService,
            calendar: utcCalendar(),
            now: { fixedNow }
        )
        return Environment(
            builder: builder,
            reminders: reminders,
            taskRepository: TaskRepository(database: database),
            eventRepository: TaskEventRepository(database: database),
            recommendationRepository: RecommendationRepository(database: database),
            outcomeRepository: RecommendationOutcomeRepository(database: database)
        )
    }

    func testBuildsReportFromStoredHistory() async throws {
        let environment = try await makeEnvironment()
        let taskID = UUID()
        try await environment.taskRepository.upsert(makeTask(id: taskID, title: "Bericht"), updatedAt: now)
        try await environment.taskRepository.upsert(
            makeTask(title: "Fertig", completionDate: now.addingTimeInterval(-3600), isCompleted: true),
            updatedAt: now
        )
        for index in 1...3 {
            try await environment.eventRepository.insert(
                makeEvent(
                    taskID: taskID,
                    type: .postponed,
                    timestamp: now.addingTimeInterval(Double(-index) * 86_400)
                )
            )
        }
        let recommendation = makeStoredRecommendation(
            taskID: taskID,
            recommendedTime: now.addingTimeInterval(-86_400),
            createdAt: now.addingTimeInterval(-2 * 86_400)
        )
        try await environment.recommendationRepository.insert(recommendation)
        try await environment.outcomeRepository.insert(
            RecommendationOutcome(recommendationID: recommendation.id, outcome: .rejected, timestamp: now)
        )

        let report = try await environment.builder.buildReport()

        XCTAssertEqual(report.openTaskCount, 1)
        XCTAssertEqual(report.completedTaskCount, 1)
        XCTAssertEqual(report.frequentlyPostponed.map(\.title), ["Bericht"])
        XCTAssertEqual(report.frequentlyPostponed[0].postponementCount, 3)
        XCTAssertEqual(report.outcomeTotals.rejected, 1)
        XCTAssertEqual(report.generatedAt, now)
    }

    func testBuilderSkipsSyncWithoutAccess() async throws {
        let environment = try await makeEnvironment(authorized: false)

        _ = try await environment.builder.buildReport()

        XCTAssertEqual(environment.reminders.fetchAllCallCount, 0)
    }

    func testBuilderSyncsWhenAuthorized() async throws {
        let environment = try await makeEnvironment(authorized: true)
        environment.reminders.allTasksResult = .success([makeTask(title: "Neu")])

        let report = try await environment.builder.buildReport()

        XCTAssertEqual(environment.reminders.fetchAllCallCount, 1)
        XCTAssertEqual(report.openTaskCount, 1)
    }
}
