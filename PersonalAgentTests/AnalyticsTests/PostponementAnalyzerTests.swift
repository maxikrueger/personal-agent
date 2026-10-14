import XCTest
@testable import PersonalAgent

final class PostponementAnalyzerTests: XCTestCase {
    private let taskID = UUID()

    private func postponedEvent(at timestamp: Date, old: Date? = nil, new: Date? = nil) -> TaskEvent {
        var metadata = ["field": "dueDate"]
        if let old { metadata["oldDueDate"] = old.formatted(.iso8601) }
        if let new { metadata["newDueDate"] = new.formatted(.iso8601) }
        return makeEvent(taskID: taskID, type: .postponed, timestamp: timestamp, metadata: metadata)
    }

    func testNoEventsMeansNoPostponements() {
        let analysis = PostponementAnalyzer.analyze(events: [], completionCount: 0)

        XCTAssertEqual(analysis.postponementCount, 0)
        XCTAssertEqual(analysis.postponementRate, 0)
        XCTAssertNil(analysis.averagePostponementDelay)
        XCTAssertEqual(analysis.consecutivePostponements, 0)
    }

    func testCountAndRate() {
        let events = [
            postponedEvent(at: Date(timeIntervalSince1970: 1_800_000_000)),
            postponedEvent(at: Date(timeIntervalSince1970: 1_800_100_000)),
        ]

        let analysis = PostponementAnalyzer.analyze(events: events, completionCount: 1)

        XCTAssertEqual(analysis.postponementCount, 2)
        XCTAssertEqual(analysis.postponementRate, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testAveragePostponementDelayFromMetadata() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [
            postponedEvent(at: base, old: base, new: base.addingTimeInterval(7 * 86_400)),
            postponedEvent(
                at: base.addingTimeInterval(86_400),
                old: base.addingTimeInterval(7 * 86_400),
                new: base.addingTimeInterval(10 * 86_400)
            ),
        ]

        let analysis = PostponementAnalyzer.analyze(events: events, completionCount: 0)

        XCTAssertEqual(analysis.averagePostponementDelay ?? 0, 5 * 86_400, accuracy: 0.001)
    }

    func testPostponementWithoutDatesCountsButAddsNoDelay() {
        let events = [postponedEvent(at: Date(timeIntervalSince1970: 1_800_000_000))]

        let analysis = PostponementAnalyzer.analyze(events: events, completionCount: 0)

        XCTAssertEqual(analysis.postponementCount, 1)
        XCTAssertNil(analysis.averagePostponementDelay)
    }

    func testConsecutiveCountsOnlyAfterLastCompletion() {
        let events = [
            postponedEvent(at: Date(timeIntervalSince1970: 1_800_000_000)),
            makeEvent(taskID: taskID, type: .completed, timestamp: Date(timeIntervalSince1970: 1_800_100_000)),
            postponedEvent(at: Date(timeIntervalSince1970: 1_800_200_000)),
            postponedEvent(at: Date(timeIntervalSince1970: 1_800_300_000)),
        ]

        let analysis = PostponementAnalyzer.analyze(events: events, completionCount: 1)

        XCTAssertEqual(analysis.postponementCount, 3)
        XCTAssertEqual(analysis.consecutivePostponements, 2)
    }
}
