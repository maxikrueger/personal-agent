import Foundation
@testable import PersonalAgent

final class FakeNotificationService: NotificationService, @unchecked Sendable {
    var accessResult: Result<Void, Error> = .success(())
    var scheduleResult: Result<Void, Error> = .success(())
    private(set) var scheduled: [(id: String, title: String, body: String, date: Date)] = []
    private(set) var cancelled: [String] = []

    func requestAccess() async throws {
        try accessResult.get()
    }

    func schedule(id: String, title: String, body: String, date: Date) async throws {
        try scheduleResult.get()
        scheduled.append((id, title, body, date))
    }

    func cancel(id: String) {
        cancelled.append(id)
    }
}
