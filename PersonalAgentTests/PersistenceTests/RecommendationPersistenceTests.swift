import XCTest
@testable import PersonalAgent

final class RecommendationPersistenceTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeEnvironment() async throws -> (
        tasks: TaskRepository,
        recommendations: RecommendationRepository,
        outcomes: RecommendationOutcomeRepository,
        seededTask: PersonalAgent.Task
    ) {
        let database = try await makeTestDatabase()
        let tasks = TaskRepository(database: database)
        let task = makeTask(title: "Steuer")
        try await tasks.upsert(task, updatedAt: createdAt)
        return (
            tasks,
            RecommendationRepository(database: database),
            RecommendationOutcomeRepository(database: database),
            task
        )
    }

    func testRecommendationRoundtripPreservesReasonOrder() async throws {
        let environment = try await makeEnvironment()
        let stored = makeStoredRecommendation(
            taskID: environment.seededTask.id,
            recommendedTime: createdAt.addingTimeInterval(4 * 3600),
            createdAt: createdAt,
            confidence: 0.87,
            reasonCodes: [.deadlineApproaching, .frequentlyPostponed, .currentlyFree]
        )

        try await environment.recommendations.insert(stored)
        let fetched = try await environment.recommendations.recommendations(forTaskID: environment.seededTask.id)

        XCTAssertEqual(fetched, [stored])
        XCTAssertEqual(
            fetched[0].reasonCodes,
            [.deadlineApproaching, .frequentlyPostponed, .currentlyFree]
        )
    }

    func testRecommendationsAreSortedNewestFirst() async throws {
        let environment = try await makeEnvironment()
        let older = makeStoredRecommendation(
            taskID: environment.seededTask.id,
            recommendedTime: createdAt,
            createdAt: createdAt.addingTimeInterval(-3600)
        )
        let newer = makeStoredRecommendation(
            taskID: environment.seededTask.id,
            recommendedTime: createdAt,
            createdAt: createdAt
        )
        try await environment.recommendations.insert(older)
        try await environment.recommendations.insert(newer)

        let fetched = try await environment.recommendations.recommendations(forTaskID: environment.seededTask.id)

        XCTAssertEqual(fetched.map(\.id), [newer.id, older.id])
    }

    func testLatestSinceRespectsWindow() async throws {
        let environment = try await makeEnvironment()
        let old = makeStoredRecommendation(
            taskID: environment.seededTask.id,
            recommendedTime: createdAt,
            createdAt: createdAt.addingTimeInterval(-7200)
        )
        let recent = makeStoredRecommendation(
            taskID: environment.seededTask.id,
            recommendedTime: createdAt,
            createdAt: createdAt.addingTimeInterval(-600)
        )
        try await environment.recommendations.insert(old)
        try await environment.recommendations.insert(recent)

        let found = try await environment.recommendations.latest(
            forTaskID: environment.seededTask.id,
            since: createdAt.addingTimeInterval(-3600)
        )
        XCTAssertEqual(found?.id, recent.id)

        let none = try await environment.recommendations.latest(
            forTaskID: environment.seededTask.id,
            since: createdAt
        )
        XCTAssertNil(none)
    }

    func testOutcomeRoundtrip() async throws {
        let environment = try await makeEnvironment()
        let stored = makeStoredRecommendation(
            taskID: environment.seededTask.id,
            recommendedTime: createdAt,
            createdAt: createdAt
        )
        try await environment.recommendations.insert(stored)
        let outcome = RecommendationOutcome(
            recommendationID: stored.id,
            outcome: .notCompleted,
            timestamp: createdAt.addingTimeInterval(86_400)
        )

        try await environment.outcomes.insert(outcome)
        let fetched = try await environment.outcomes.outcomes(forRecommendationID: stored.id)

        XCTAssertEqual(fetched, [outcome])
    }

    func testDuplicateOutcomeTypeIsRejected() async throws {
        let environment = try await makeEnvironment()
        let stored = makeStoredRecommendation(
            taskID: environment.seededTask.id,
            recommendedTime: createdAt,
            createdAt: createdAt
        )
        try await environment.recommendations.insert(stored)
        try await environment.outcomes.insert(
            RecommendationOutcome(recommendationID: stored.id, outcome: .ignored, timestamp: createdAt)
        )

        do {
            try await environment.outcomes.insert(
                RecommendationOutcome(recommendationID: stored.id, outcome: .ignored, timestamp: createdAt)
            )
            XCTFail("Expected the UNIQUE constraint to reject the duplicate")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }

    func testOutcomeForUnknownRecommendationIsRejected() async throws {
        let environment = try await makeEnvironment()

        do {
            try await environment.outcomes.insert(
                RecommendationOutcome(recommendationID: UUID(), outcome: .accepted, timestamp: createdAt)
            )
            XCTFail("Expected a foreign-key violation")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }
}
