import XCTest
@testable import PersonalAgent

final class ProcrastinationScorerTests: XCTestCase {
    private func inputs(
        postponementRate: Double = 0,
        overdueRate: Double = 0,
        averageDelay: TimeInterval? = nil,
        openAge: TimeInterval? = nil,
        consecutivePostponements: Int = 0
    ) -> ProcrastinationInputs {
        ProcrastinationInputs(
            postponementRate: postponementRate,
            overdueRate: overdueRate,
            averageDelay: averageDelay,
            openAge: openAge,
            consecutivePostponements: consecutivePostponements
        )
    }

    func testZeroInputsScoreZero() {
        XCTAssertEqual(ProcrastinationScorer.score(inputs()), 0)
    }

    func testSaturatedInputsScoreOne() {
        let score = ProcrastinationScorer.score(
            inputs(
                postponementRate: 1,
                overdueRate: 1,
                averageDelay: 30 * 86_400,
                openAge: 90 * 86_400,
                consecutivePostponements: 10
            )
        )

        XCTAssertEqual(score, 1.0, accuracy: 0.000001)
    }

    func testPostponementRateComponentAlone() {
        let score = ProcrastinationScorer.score(inputs(postponementRate: 1))
        XCTAssertEqual(score, 0.35, accuracy: 0.000001)
    }

    func testDelayComponentIsNormalizedOverSevenDays() {
        let score = ProcrastinationScorer.score(inputs(averageDelay: 3.5 * 86_400))
        XCTAssertEqual(score, 0.2 * 0.5, accuracy: 0.000001)
    }

    func testEarlyCompletionDoesNotReduceScore() {
        XCTAssertEqual(ProcrastinationScorer.score(inputs(averageDelay: -86_400)), 0)
    }

    func testConsecutiveComponentIsNormalizedOverFive() {
        let score = ProcrastinationScorer.score(inputs(consecutivePostponements: 3))
        XCTAssertEqual(score, 0.1 * 0.6, accuracy: 0.000001)
    }

    func testCustomWeightsAreRespected() {
        let weights = ProcrastinationWeights(
            postponementRate: 1,
            overdueRate: 0,
            delay: 0,
            age: 0,
            consecutivePostponements: 0
        )

        let score = ProcrastinationScorer.score(inputs(postponementRate: 0.5), weights: weights)

        XCTAssertEqual(score, 0.5, accuracy: 0.000001)
    }
}
