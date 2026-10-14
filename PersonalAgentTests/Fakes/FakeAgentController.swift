import Foundation
@testable import PersonalAgent

final class FakeAgentController: AgentControllerProtocol, @unchecked Sendable {
    var result: Result<String, Error> = .success("OK")
    private(set) var receivedMessages: [String] = []

    func send(_ message: String) async throws -> String {
        receivedMessages.append(message)
        return try result.get()
    }
}
