import XCTest
@testable import PersonalAgent

final class RecommendationScoringTests: XCTestCase {
    private let calendar = utcCalendar()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    func testDeadlineUrgency() {
        XCTAssertEqual(
            RecommendationEngine.deadlineUrgency(dueDate: now, isOverdue: true, now: now, horizon: 7 * day),
            1
        )
        XCTAssertEqual(
            RecommendationEngine.deadlineUrgency(dueDate: nil, isOverdue: false, now: now, horizon: 7 * day),
            0.3
        )
        XCTAssertEqual(
            RecommendationEngine.deadlineUrgency(
                dueDate: now.addingTimeInterval(3.5 * day),
                isOverdue: false,
                now: now,
                horizon: 7 * day
            ),
            0.5,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            RecommendationEngine.deadlineUrgency(dueDate: now, isOverdue: false, now: now, horizon: 7 * day),
            1,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            RecommendationEngine.deadlineUrgency(
                dueDate: now.addingTimeInterval(14 * day),
                isOverdue: false,
                now: now,
                horizon: 7 * day
            ),
            0
        )
    }

    func testWindowMatch() {
        let evening = utcCalendar().date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 19))!
        let morning = utcCalendar().date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9))!
        let confident = PreferredWindowAnalysis(window: .evening, confidence: 0.8, sampleSize: 6)
        let none = PreferredWindowAnalysis(window: nil, confidence: 0, sampleSize: 0)

        XCTAssertEqual(RecommendationEngine.windowMatch(candidate: evening, window: confident, calendar: calendar), 0.9, accuracy: 0.000001)
        XCTAssertEqual(RecommendationEngine.windowMatch(candidate: morning, window: confident, calendar: calendar), 0.1, accuracy: 0.000001)
        XCTAssertEqual(RecommendationEngine.windowMatch(candidate: morning, window: none, calendar: calendar), 0.5)
    }

    func testDeadlineFit() {
        let due = now.addingTimeInterval(3600)

        XCTAssertEqual(RecommendationEngine.deadlineFit(candidate: now, taskDuration: 1800, dueDate: due), 1)
        XCTAssertEqual(RecommendationEngine.deadlineFit(candidate: now, taskDuration: 3600, dueDate: due), 1)
        XCTAssertEqual(RecommendationEngine.deadlineFit(candidate: now.addingTimeInterval(3000), taskDuration: 1800, dueDate: due), 0)
        XCTAssertEqual(RecommendationEngine.deadlineFit(candidate: now, taskDuration: 1800, dueDate: nil), 0.5)
    }

    func testEarliness() {
        XCTAssertEqual(RecommendationEngine.earliness(candidate: now, now: now, horizon: 3 * day), 1)
        XCTAssertEqual(
            RecommendationEngine.earliness(candidate: now.addingTimeInterval(3 * day), now: now, horizon: 3 * day),
            0,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            RecommendationEngine.earliness(candidate: now.addingTimeInterval(6 * day), now: now, horizon: 3 * day),
            0
        )
        XCTAssertEqual(RecommendationEngine.earliness(candidate: now, now: now, horizon: 0), 0)
    }

    func testConfidenceFormula() {
        let taskID = UUID()
        let richTask = makeTask(id: taskID, dueDate: now.addingTimeInterval(day))
        let richAnalysis = makeAnalysis(
            taskID: taskID,
            cycleCount: 4,
            window: .evening,
            windowConfidence: 0.8,
            windowSampleSize: 6
        )
        XCTAssertEqual(
            RecommendationEngine.confidence(for: richAnalysis, task: richTask),
            0.92,
            accuracy: 0.000001
        )

        let sparseTask = makeTask(id: taskID)
        let sparseAnalysis = makeAnalysis(taskID: taskID, cycleCount: 1)
        XCTAssertEqual(
            RecommendationEngine.confidence(for: sparseAnalysis, task: sparseTask),
            0.325,
            accuracy: 0.000001
        )
    }
}
