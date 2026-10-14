import XCTest
@testable import PersonalAgent

final class InterventionPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let horizon: TimeInterval = 7 * 86_400

    func testPriorityCombinesProcrastinationAndUrgency() {
        let taskID = UUID()
        let task = makeTask(id: taskID, dueDate: now.addingTimeInterval(-3600))
        let analysis = makeAnalysis(taskID: taskID, procrastinationScore: 0.5, isCurrentlyOverdue: true)

        let priority = InterventionPlanner.priority(
            task: task, analysis: analysis, now: now, urgencyHorizon: horizon
        )

        // 0.6·0.5 + 0.4·1 (overdue).
        XCTAssertEqual(priority, 0.7, accuracy: 0.000001)
    }

    func testCalmTaskScoresLow() {
        let taskID = UUID()
        let priority = InterventionPlanner.priority(
            task: makeTask(id: taskID),
            analysis: makeAnalysis(taskID: taskID),
            now: now,
            urgencyHorizon: horizon
        )

        // 0.6·0 + 0.4·0.3 (no due date).
        XCTAssertEqual(priority, 0.12, accuracy: 0.000001)
        XCTAssertLessThan(priority, InterventionPlanner.interventionThreshold)
    }

    func testRankOrdersByPriorityDescending() {
        let calmID = UUID()
        let urgentID = UUID()
        let ranked = InterventionPlanner.rank(
            [
                (makeTask(id: calmID, title: "Ruhig"), makeAnalysis(taskID: calmID)),
                (
                    makeTask(id: urgentID, title: "Zappelig", dueDate: now.addingTimeInterval(-3600)),
                    makeAnalysis(taskID: urgentID, procrastinationScore: 0.8, isCurrentlyOverdue: true)
                ),
            ],
            now: now,
            urgencyHorizon: horizon
        )

        XCTAssertEqual(ranked.map { $0.task.title }, ["Zappelig", "Ruhig"])
    }

    func testTieBreaksAlphabetically() {
        let firstID = UUID()
        let secondID = UUID()
        let ranked = InterventionPlanner.rank(
            [
                (makeTask(id: secondID, title: "Beta"), makeAnalysis(taskID: secondID)),
                (makeTask(id: firstID, title: "Alpha"), makeAnalysis(taskID: firstID)),
            ],
            now: now,
            urgencyHorizon: horizon
        )

        XCTAssertEqual(ranked.map { $0.task.title }, ["Alpha", "Beta"])
    }
}
