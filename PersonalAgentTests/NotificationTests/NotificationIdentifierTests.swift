import XCTest
@testable import PersonalAgent

final class NotificationIdentifierTests: XCTestCase {
    func testTaskIdentifierRoundtrip() {
        let taskID = UUID()
        let identifier = NotificationIdentifier.forTask(taskID)

        XCTAssertEqual(NotificationIdentifier.taskID(from: identifier), taskID)
    }

    func testAdhocIdentifierCarriesNoTask() {
        let identifier = NotificationIdentifier.adhoc(UUID())

        XCTAssertNil(NotificationIdentifier.taskID(from: identifier))
    }

    func testGarbageIdentifiersYieldNil() {
        XCTAssertNil(NotificationIdentifier.taskID(from: "task-not-a-uuid"))
        XCTAssertNil(NotificationIdentifier.taskID(from: "something-else"))
        XCTAssertNil(NotificationIdentifier.taskID(from: ""))
    }
}
