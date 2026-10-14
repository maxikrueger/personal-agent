import XCTest
@testable import PersonalAgent

final class CompletionAnalyzerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let taskID = UUID()

    func testOpenNeverCompletedTask() {
        let creation = Date(timeIntervalSince1970: 1_799_000_000)
        let task = makeTask(id: taskID, creationDate: creation)
        let events = [makeEvent(taskID: taskID, type: .created, timestamp: creation)]

        let analysis = CompletionAnalyzer.analyze(task: task, events: events, now: now)

        XCTAssertEqual(analysis.completionCount, 0)
        XCTAssertEqual(analysis.cycleCount, 1)
        XCTAssertEqual(analysis.completionRate, 0)
        XCTAssertTrue(analysis.delays.isEmpty)
        XCTAssertNil(analysis.averageDelay)
        XCTAssertNil(analysis.medianDelay)
        XCTAssertFalse(analysis.isCurrentlyOverdue)
        XCTAssertEqual(analysis.currentOpenSince, creation)
    }

    func testCompletedLateComputesPositiveDelay() {
        let due = Date(timeIntervalSince1970: 1_799_900_000)
        let completion = due.addingTimeInterval(7200)
        let task = makeTask(id: taskID, dueDate: due, completionDate: completion, isCompleted: true)
        let events = [makeEvent(taskID: taskID, type: .completed, timestamp: completion)]

        let analysis = CompletionAnalyzer.analyze(task: task, events: events, now: now)

        XCTAssertEqual(analysis.completionCount, 1)
        XCTAssertEqual(analysis.cycleCount, 1)
        XCTAssertEqual(analysis.completionRate, 1)
        XCTAssertEqual(analysis.delays, [7200])
        XCTAssertEqual(analysis.averageDelay, 7200)
        XCTAssertEqual(analysis.medianDelay, 7200)
        XCTAssertNil(analysis.currentOpenSince)
    }

    func testCompletedEarlyComputesNegativeDelay() {
        let due = Date(timeIntervalSince1970: 1_799_900_000)
        let completion = due.addingTimeInterval(-3600)
        let task = makeTask(id: taskID, dueDate: due, completionDate: completion, isCompleted: true)
        let events = [makeEvent(taskID: taskID, type: .completed, timestamp: completion)]

        let analysis = CompletionAnalyzer.analyze(task: task, events: events, now: now)

        XCTAssertEqual(analysis.delays, [-3600])
    }

    func testMultiCycleRate() {
        let firstCompletion = Date(timeIntervalSince1970: 1_799_100_000)
        let reopened = Date(timeIntervalSince1970: 1_799_200_000)
        let task = makeTask(id: taskID)
        let events = [
            makeEvent(taskID: taskID, type: .created, timestamp: Date(timeIntervalSince1970: 1_799_000_000)),
            makeEvent(taskID: taskID, type: .completed, timestamp: firstCompletion),
            makeEvent(taskID: taskID, type: .reopened, timestamp: reopened),
        ]

        let analysis = CompletionAnalyzer.analyze(task: task, events: events, now: now)

        XCTAssertEqual(analysis.completionCount, 1)
        XCTAssertEqual(analysis.cycleCount, 2)
        XCTAssertEqual(analysis.completionRate, 0.5)
        XCTAssertEqual(analysis.currentOpenSince, reopened)
    }

    func testImportedCompletedTaskSynthesizesOneCompletion() {
        let completion = Date(timeIntervalSince1970: 1_799_500_000)
        let task = makeTask(id: taskID, completionDate: completion, isCompleted: true)
        let events = [makeEvent(taskID: taskID, type: .created, timestamp: Date(timeIntervalSince1970: 1_799_000_000))]

        let analysis = CompletionAnalyzer.analyze(task: task, events: events, now: now)

        XCTAssertEqual(analysis.completionCount, 1)
        XCTAssertEqual(analysis.cycleCount, 1)
        XCTAssertEqual(analysis.completionRate, 1)
        XCTAssertEqual(analysis.completionDates, [completion])
    }

    func testCurrentlyOverdueFlag() {
        let task = makeTask(id: taskID, dueDate: now.addingTimeInterval(-60))

        let analysis = CompletionAnalyzer.analyze(task: task, events: [], now: now)

        XCTAssertTrue(analysis.isCurrentlyOverdue)
    }

    func testDelayUsesDueDateInEffectAtCompletionTime() {
        // Completed against due date A; afterwards the due date moved to B.
        let dueA = Date(timeIntervalSince1970: 1_799_000_000)
        let dueB = Date(timeIntervalSince1970: 1_799_900_000)
        let completion = dueA.addingTimeInterval(3600)
        let changeAfterCompletion = completion.addingTimeInterval(3600)
        let task = makeTask(id: taskID, dueDate: dueB, completionDate: completion, isCompleted: true)
        let events = [
            makeEvent(taskID: taskID, type: .completed, timestamp: completion),
            makeEvent(
                taskID: taskID,
                type: .postponed,
                timestamp: changeAfterCompletion,
                metadata: [
                    "field": "dueDate",
                    "oldDueDate": dueA.formatted(.iso8601),
                    "newDueDate": dueB.formatted(.iso8601),
                ]
            ),
        ]

        let analysis = CompletionAnalyzer.analyze(task: task, events: events, now: now)

        XCTAssertEqual(analysis.delays, [3600])
    }

    func testMedianOfEvenAndOddCounts() {
        XCTAssertEqual(CompletionAnalyzer.median(of: [10, 2, 6]), 6)
        XCTAssertEqual(CompletionAnalyzer.median(of: [10, 2, 6, 4]), 5)
        XCTAssertNil(CompletionAnalyzer.median(of: []))
        XCTAssertEqual(CompletionAnalyzer.average(of: [10, 2, 6, 4]), 5.5)
    }
}
