import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case agent
    }

    let id: UUID
    let role: Role
    let text: String

    init(role: Role, text: String, id: UUID = UUID()) {
        self.id = id
        self.role = role
        self.text = text
    }

    /// Agent replies often contain inline Markdown (`**bold**`); render it
    /// instead of showing the asterisks. Line breaks are kept. User input is
    /// shown exactly as typed.
    var displayText: AttributedString {
        guard role == .agent,
              let parsed = try? AttributedString(
                  markdown: text,
                  options: AttributedString.MarkdownParsingOptions(
                      interpretedSyntax: .inlineOnlyPreservingWhitespace
                  )
              )
        else { return AttributedString(text) }
        return parsed
    }
}
