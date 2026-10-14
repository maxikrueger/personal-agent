import XCTest
@testable import PersonalAgent

final class RecommendationEngineTests: XCTestCase {
    private let calendar = utcCalendar()

    private func utcDate(month: Int = 8, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func interval(day: Int, fromHour: Int, toHour: Int) -> DateInterval {
        DateInterval(start: utcDate(day: day, hour: fromHour), end: utcDate(day: day, hour: toHour))
    }

    /// Monday 2026-08-31, 08:00 UTC.
    private var now: Date { utcDate(day: 31, hour: 8) }

    func testEveningPreferenceWinsOverMorningSlot() {
        // Historical completion in the evening, both slots free
        // → the evening slot must win.
        let taskID = UUID()
        let task = makeTask(id: taskID, title: "Steuer")
        let analysis = makeAnalysis(
            taskID: taskID,
            procrastinationScore: 0.2,
            window: .evening,
            windowConfidence: 0.8,
            windowSampleSize: 6
        )

        let ranked = RecommendationEngine.recommendation(
            for: task,
            analysis: analysis,
            freeSlots: [interval(day: 31, fromHour: 9, toHour: 11), interval(day: 31, fromHour: 18, toHour: 21)],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(ranked?.recommendation.recommendedTime, utcDate(day: 31, hour: 18))
        XCTAssertEqual(ranked?.candidates.count, 2)
        // Hand-computed: 0.3·0.3 + 0.3·0.9 + 0.15·0.2 + 0.15·0.5 + 0.1·(1 − 10/72)
        XCTAssertEqual(ranked?.score ?? 0, 0.5511111, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(ranked!.candidates[0].score, ranked!.candidates[1].score)
    }

    func testMorningPreferenceFallsBackWhenMorningUnavailable() {
        // Morning preferred but unavailable → best available alternative.
        let taskID = UUID()
        let task = makeTask(id: taskID)
        let analysis = makeAnalysis(
            taskID: taskID,
            window: .morning,
            windowConfidence: 0.9,
            windowSampleSize: 6
        )

        let ranked = RecommendationEngine.recommendation(
            for: task,
            analysis: analysis,
            freeSlots: [interval(day: 31, fromHour: 14, toHour: 16)],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(ranked?.recommendation.recommendedTime, utcDate(day: 31, hour: 14))
    }

    func testNoFreeSlotsGiveNoRecommendation() {
        let taskID = UUID()
        let ranked = RecommendationEngine.recommendation(
            for: makeTask(id: taskID),
            analysis: makeAnalysis(taskID: taskID),
            freeSlots: [],
            now: now,
            calendar: calendar
        )

        XCTAssertNil(ranked)
    }

    func testCandidatesInThePastAreFiltered() {
        let taskID = UUID()
        let ranked = RecommendationEngine.recommendation(
            for: makeTask(id: taskID),
            analysis: makeAnalysis(taskID: taskID),
            freeSlots: [interval(day: 31, fromHour: 6, toHour: 7)],
            now: now,
            calendar: calendar
        )

        XCTAssertNil(ranked)
    }

    func testSlotBeforeDeadlineBeatsLaterSlot() {
        let taskID = UUID()
        let task = makeTask(id: taskID, dueDate: utcDate(day: 31, hour: 20))
        let analysis = makeAnalysis(taskID: taskID)

        let ranked = RecommendationEngine.recommendation(
            for: task,
            analysis: analysis,
            freeSlots: [
                interval(day: 31, fromHour: 18, toHour: 19),
                DateInterval(start: utcDate(month: 9, day: 1, hour: 10), end: utcDate(month: 9, day: 1, hour: 12)),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(ranked?.recommendation.recommendedTime, utcDate(day: 31, hour: 18))
    }

    func testReasonCodesForPlanScenario() {
        // Typical case: frequently postponed, deadline near, weekly pattern,
        // evening preference, evening slot chosen.
        let taskID = UUID()
        let task = makeTask(id: taskID, dueDate: utcDate(month: 9, day: 1, hour: 18))
        let analysis = makeAnalysis(
            taskID: taskID,
            procrastinationScore: 0.8,
            postponementCount: 5,
            postponementRate: 1.0,
            recurrencePattern: .weekly,
            recurrenceConfidence: 0.8,
            window: .evening,
            windowConfidence: 0.8,
            windowSampleSize: 6
        )

        let ranked = RecommendationEngine.recommendation(
            for: task,
            analysis: analysis,
            freeSlots: [interval(day: 31, fromHour: 18, toHour: 21)],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(ranked?.recommendation.reasonCodes, [
            .deadlineApproaching,
            .frequentlyPostponed,
            .recurringPattern,
            .historicallySuccessfulTime,
            .currentlyFree,
        ])
    }

    func testOverdueTaskGetsOverdueReasonInsteadOfDeadlineApproaching() {
        let taskID = UUID()
        let task = makeTask(id: taskID, dueDate: utcDate(day: 30, hour: 18))
        let analysis = makeAnalysis(taskID: taskID, isCurrentlyOverdue: true)

        let ranked = RecommendationEngine.recommendation(
            for: task,
            analysis: analysis,
            freeSlots: [interval(day: 31, fromHour: 9, toHour: 10)],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(ranked?.recommendation.reasonCodes.first, .overdue)
        XCTAssertFalse(ranked?.recommendation.reasonCodes.contains(.deadlineApproaching) ?? true)
    }

    func testRecommendationCarriesConfidence() {
        let taskID = UUID()
        let task = makeTask(id: taskID, dueDate: utcDate(month: 9, day: 1, hour: 18))
        let analysis = makeAnalysis(
            taskID: taskID,
            cycleCount: 4,
            window: .evening,
            windowConfidence: 0.8,
            windowSampleSize: 6
        )

        let ranked = RecommendationEngine.recommendation(
            for: task,
            analysis: analysis,
            freeSlots: [interval(day: 31, fromHour: 18, toHour: 21)],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(ranked?.recommendation.confidence ?? 0, 0.92, accuracy: 0.000001)
        XCTAssertEqual(ranked?.recommendation.taskID, taskID)
    }
}
