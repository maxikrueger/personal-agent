import XCTest
@testable import PersonalAgent

final class ChatMessageTests: XCTestCase {
    func testAgentMarkdownIsRenderedWithoutAsterisks() {
        let message = ChatMessage(role: .agent, text: "**Sport** und **Pflanzen gießen**")

        XCTAssertEqual(String(message.displayText.characters), "Sport und Pflanzen gießen")
    }

    func testAgentLineBreaksArePreserved() {
        let message = ChatMessage(role: .agent, text: "Erste Zeile\n\nZweite Zeile")

        XCTAssertEqual(String(message.displayText.characters), "Erste Zeile\n\nZweite Zeile")
    }

    func testUserTextIsShownExactlyAsTyped() {
        let message = ChatMessage(role: .user, text: "**nicht fett**")

        XCTAssertEqual(String(message.displayText.characters), "**nicht fett**")
    }
}
