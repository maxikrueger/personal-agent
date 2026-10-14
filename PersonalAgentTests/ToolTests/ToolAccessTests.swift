import XCTest
@testable import PersonalAgent

/// Every tool declares read-only or mutation.
final class ToolAccessTests: XCTestCase {
    func testAccessDeclarations() {
        XCTAssertEqual(GetOpenTasksTool.access, .readOnly)
        XCTAssertEqual(GetTaskStatisticsTool.access, .readOnly)
        XCTAssertEqual(FindFreeTimeTool.access, .readOnly)
        XCTAssertEqual(GetReminderRecommendationTool.access, .readOnly)
        XCTAssertEqual(ScheduleNotificationTool.access, .mutation)
    }
}
