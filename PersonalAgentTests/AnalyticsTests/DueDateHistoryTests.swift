import XCTest
@testable import PersonalAgent

final class DueDateHistoryTests: XCTestCase {
    private let taskID = UUID()
    private let dueA = Date(timeIntervalSince1970: 1_800_100_000)
    private let dueB = Date(timeIntervalSince1970: 1_800_400_000)

    private func changeEvent(
        at timestamp: Date,
        old: Date?,
        new: Date?,
        type: TaskEventType = .postponed
    ) -> TaskEvent {
        var metadata = ["field": "dueDate"]
        if let old { metadata["oldDueDate"] = old.formatted(.iso8601) }
        if let new { metadata["newDueDate"] = new.formatted(.iso8601) }
        return makeEvent(taskID: taskID, type: type, timestamp: timestamp, metadata: metadata)
    }

    func testWithoutChangesCurrentDueDateApplies() {
        let history = DueDateHistory(currentDueDate: dueA, events: [
            makeEvent(taskID: taskID, type: .created, timestamp: Date(timeIntervalSince1970: 1_799_000_000))
        ])

        XCTAssertEqual(history.dueDate(at: Date(timeIntervalSince1970: 1_800_000_000)), dueA)
    }

    func testBeforeFirstChangeOldDueDateApplies() {
        let changeTime = Date(timeIntervalSince1970: 1_800_200_000)
        let history = DueDateHistory(currentDueDate: dueB, events: [
            changeEvent(at: changeTime, old: dueA, new: dueB)
        ])

        XCTAssertEqual(history.dueDate(at: changeTime.addingTimeInterval(-60)), dueA)
        XCTAssertEqual(history.dueDate(at: changeTime.addingTimeInterval(60)), dueB)
    }

    func testDueDateAddedLater() {
        let changeTime = Date(timeIntervalSince1970: 1_800_200_000)
        let history = DueDateHistory(currentDueDate: dueB, events: [
            changeEvent(at: changeTime, old: nil, new: dueB, type: .modified)
        ])

        XCTAssertNil(history.dueDate(at: changeTime.addingTimeInterval(-60)))
        XCTAssertEqual(history.dueDate(at: changeTime.addingTimeInterval(60)), dueB)
    }

    func testDueDateRemovedLater() {
        let changeTime = Date(timeIntervalSince1970: 1_800_200_000)
        let history = DueDateHistory(currentDueDate: nil, events: [
            changeEvent(at: changeTime, old: dueA, new: nil, type: .modified)
        ])

        XCTAssertEqual(history.dueDate(at: changeTime.addingTimeInterval(-60)), dueA)
        XCTAssertNil(history.dueDate(at: changeTime.addingTimeInterval(60)))
    }

    func testMultipleChangesUseLatestBeforeQuery() {
        let firstChange = Date(timeIntervalSince1970: 1_800_200_000)
        let secondChange = Date(timeIntervalSince1970: 1_800_300_000)
        let dueC = Date(timeIntervalSince1970: 1_800_500_000)
        let history = DueDateHistory(currentDueDate: dueC, events: [
            changeEvent(at: secondChange, old: dueB, new: dueC),
            changeEvent(at: firstChange, old: dueA, new: dueB),
        ])

        XCTAssertEqual(history.dueDate(at: firstChange.addingTimeInterval(-60)), dueA)
        XCTAssertEqual(history.dueDate(at: firstChange.addingTimeInterval(60)), dueB)
        XCTAssertEqual(history.dueDate(at: secondChange.addingTimeInterval(60)), dueC)
    }

    func testNextOccurrenceChangeAppliesOnlyAfterTheCompletionItFollows() {
        let rollover = Date(timeIntervalSince1970: 1_800_200_000)
        var metadata = [
            "field": "dueDate",
            "oldDueDate": dueA.formatted(.iso8601),
            "newDueDate": dueB.formatted(.iso8601),
        ]
        metadata["reason"] = TaskChangeDetector.nextOccurrenceReason
        let history = DueDateHistory(currentDueDate: dueB, events: [
            makeEvent(taskID: taskID, type: .completed, timestamp: rollover),
            makeEvent(taskID: taskID, type: .modified, timestamp: rollover, metadata: metadata),
        ])

        XCTAssertEqual(history.dueDate(at: rollover), dueA)
        XCTAssertEqual(history.dueDate(at: rollover.addingTimeInterval(1)), dueB)
    }

    func testRegularChangeAtTheSameInstantStillAppliesImmediately() {
        let changeTime = Date(timeIntervalSince1970: 1_800_200_000)
        let history = DueDateHistory(currentDueDate: dueB, events: [
            changeEvent(at: changeTime, old: dueA, new: dueB)
        ])

        XCTAssertEqual(history.dueDate(at: changeTime), dueB)
    }
}
