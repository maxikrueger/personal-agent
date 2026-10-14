import XCTest
@testable import PersonalAgent

final class OutcomeSweeperTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    private var recommendedTime: Date { createdAt.addingTimeInterval(4 * 3600) }
    private var afterGrace: Date { recommendedTime.addingTimeInterval(OutcomeSweeper.responseGrace + 60) }
    private var beforeGrace: Date { recommendedTime.addingTimeInterval(OutcomeSweeper.responseGrace - 3600) }

    private func makeRecommendation(taskID: UUID = UUID()) -> StoredRecommendation {
        makeStoredRecommendation(taskID: taskID, recommendedTime: recommendedTime, createdAt: createdAt)
    }

    // MARK: - Pure decision core

    func testCompletionWithinWindowRecordsCompletedWithCompletionTimestamp() {
        let recommendation = makeRecommendation()
        let completion = createdAt.addingTimeInterval(2 * 3600)

        let outcomes = OutcomeSweeper.outcomesToRecord(
            recommendation: recommendation,
            existingTypes: [],
            completionDates: [completion],
            now: beforeGrace
        )

        XCTAssertEqual(outcomes.map(\.outcome), [.completed])
        XCTAssertEqual(outcomes[0].timestamp, completion)
        XCTAssertEqual(outcomes[0].recommendationID, recommendation.id)
    }

    func testCompletionBeforeRecommendationDoesNotCount() {
        let outcomes = OutcomeSweeper.outcomesToRecord(
            recommendation: makeRecommendation(),
            existingTypes: [],
            completionDates: [createdAt.addingTimeInterval(-3600)],
            now: afterGrace
        )

        XCTAssertEqual(outcomes.map(\.outcome), [.ignored])
    }

    func testCompletionOutsideWindowDoesNotCount() {
        let lateCompletion = createdAt.addingTimeInterval(OutcomeSweeper.completionWindow + 3600)

        let outcomes = OutcomeSweeper.outcomesToRecord(
            recommendation: makeRecommendation(),
            existingTypes: [],
            completionDates: [lateCompletion],
            now: lateCompletion.addingTimeInterval(3600)
        )

        XCTAssertEqual(outcomes.map(\.outcome), [.ignored])
    }

    func testNothingBeforeGraceWithoutCompletion() {
        let outcomes = OutcomeSweeper.outcomesToRecord(
            recommendation: makeRecommendation(),
            existingTypes: [],
            completionDates: [],
            now: beforeGrace
        )

        XCTAssertTrue(outcomes.isEmpty)
    }

    func testAcceptedButUnfinishedBecomesNotCompleted() {
        let outcomes = OutcomeSweeper.outcomesToRecord(
            recommendation: makeRecommendation(),
            existingTypes: [.accepted],
            completionDates: [],
            now: afterGrace
        )

        XCTAssertEqual(outcomes.map(\.outcome), [.notCompleted])
        XCTAssertEqual(outcomes[0].timestamp, afterGrace)
    }

    func testAcceptedAndCompletedRecordsOnlyCompleted() {
        let completion = createdAt.addingTimeInterval(86_400)

        let outcomes = OutcomeSweeper.outcomesToRecord(
            recommendation: makeRecommendation(),
            existingTypes: [.accepted],
            completionDates: [completion],
            now: afterGrace
        )

        XCTAssertEqual(outcomes.map(\.outcome), [.completed])
    }

    func testRejectedRecommendationIsNeverIgnored() {
        let outcomes = OutcomeSweeper.outcomesToRecord(
            recommendation: makeRecommendation(),
            existingTypes: [.rejected],
            completionDates: [],
            now: afterGrace
        )

        XCTAssertTrue(outcomes.isEmpty)
    }

    func testExistingOutcomesAreNotDuplicated() {
        let completion = createdAt.addingTimeInterval(3600)

        let outcomes = OutcomeSweeper.outcomesToRecord(
            recommendation: makeRecommendation(),
            existingTypes: [.completed, .ignored],
            completionDates: [completion],
            now: afterGrace
        )

        XCTAssertTrue(outcomes.isEmpty)
    }

    // MARK: - Integration with the database

    func testSweepWritesOutcomesAndIsIdempotent() async throws {
        let database = try await makeTestDatabase()
        let taskRepository = TaskRepository(database: database)
        let eventRepository = TaskEventRepository(database: database)
        let recommendationRepository = RecommendationRepository(database: database)
        let outcomeRepository = RecommendationOutcomeRepository(database: database)

        // Task A: completed after its recommendation.
        let taskA = makeTask(title: "Erledigt")
        try await taskRepository.upsert(taskA, updatedAt: createdAt)
        try await eventRepository.insert(
            makeEvent(taskID: taskA.id, type: .completed, timestamp: createdAt.addingTimeInterval(2 * 3600))
        )
        let recommendationA = makeStoredRecommendation(
            taskID: taskA.id, recommendedTime: recommendedTime, createdAt: createdAt
        )
        try await recommendationRepository.insert(recommendationA)

        // Task B: no reaction, grace period over.
        let taskB = makeTask(title: "Ignoriert")
        try await taskRepository.upsert(taskB, updatedAt: createdAt)
        let recommendationB = makeStoredRecommendation(
            taskID: taskB.id, recommendedTime: recommendedTime, createdAt: createdAt
        )
        try await recommendationRepository.insert(recommendationB)

        let sweeper = OutcomeSweeper(database: database)
        let firstRun = try await sweeper.sweep(now: afterGrace)
        XCTAssertEqual(firstRun, 2)

        let outcomesA = try await outcomeRepository.outcomes(forRecommendationID: recommendationA.id)
        XCTAssertEqual(outcomesA.map(\.outcome), [.completed])
        let outcomesB = try await outcomeRepository.outcomes(forRecommendationID: recommendationB.id)
        XCTAssertEqual(outcomesB.map(\.outcome), [.ignored])

        let secondRun = try await sweeper.sweep(now: afterGrace.addingTimeInterval(3600))
        XCTAssertEqual(secondRun, 0)
    }
}
