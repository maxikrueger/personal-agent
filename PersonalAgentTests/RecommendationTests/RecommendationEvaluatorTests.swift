import XCTest
@testable import PersonalAgent

final class RecommendationEvaluatorTests: XCTestCase {
    private func outcomes(_ types: [OutcomeType]) -> [RecommendationOutcome] {
        types.map {
            RecommendationOutcome(
                recommendationID: UUID(),
                outcome: $0,
                timestamp: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }
    }

    func testSummaryCountsByType() {
        let summary = RecommendationEvaluator.summary(
            from: outcomes([.accepted, .accepted, .rejected, .ignored, .completed, .notCompleted])
        )

        XCTAssertEqual(summary.accepted, 2)
        XCTAssertEqual(summary.rejected, 1)
        XCTAssertEqual(summary.ignored, 1)
        XCTAssertEqual(summary.completed, 1)
        XCTAssertEqual(summary.notCompleted, 1)
        XCTAssertEqual(summary.snoozed, 0)
        XCTAssertEqual(summary.total, 6)
    }

    func testCompletionsRaiseConfidence() {
        let one = RecommendationEvaluator.summary(from: outcomes([.completed]))
        XCTAssertEqual(RecommendationEvaluator.confidenceAdjustment(for: one), 0.1 / 3, accuracy: 0.000001)

        let saturated = RecommendationEvaluator.summary(from: outcomes([.completed, .completed, .completed, .completed]))
        XCTAssertEqual(RecommendationEvaluator.confidenceAdjustment(for: saturated), 0.1, accuracy: 0.000001)
    }

    func testRejectionsAndIgnoresLowerConfidence() {
        let mixed = RecommendationEvaluator.summary(from: outcomes([.rejected, .ignored, .ignored]))
        XCTAssertEqual(RecommendationEvaluator.confidenceAdjustment(for: mixed), -0.1, accuracy: 0.000001)
    }

    func testBalancedOutcomesCancelOut() {
        let balanced = RecommendationEvaluator.summary(
            from: outcomes([.completed, .completed, .completed, .rejected, .rejected, .rejected])
        )
        XCTAssertEqual(RecommendationEvaluator.confidenceAdjustment(for: balanced), 0, accuracy: 0.000001)
    }

    func testEngineConfidenceAppliesAdjustment() {
        let taskID = UUID()
        let task = makeTask(id: taskID)
        let analysis = makeAnalysis(taskID: taskID, cycleCount: 1)
        // Base for this sparse setup is 0.325 (asserted in RecommendationScoringTests).
        let negative = RecommendationEvaluator.summary(from: outcomes([.rejected, .rejected, .rejected]))
        XCTAssertEqual(
            RecommendationEngine.confidence(for: analysis, task: task, outcomeSummary: negative),
            0.225,
            accuracy: 0.000001
        )

        let positive = RecommendationEvaluator.summary(from: outcomes([.completed, .completed, .completed]))
        XCTAssertEqual(
            RecommendationEngine.confidence(for: analysis, task: task, outcomeSummary: positive),
            0.425,
            accuracy: 0.000001
        )
    }
}
