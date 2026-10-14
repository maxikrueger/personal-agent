import Foundation
import FoundationModels
@testable import PersonalAgent

/// Deterministic model provider for agent tests.
/// Each turn replays a script: tool calls with JSON arguments, then a reply.
/// Tool calls run the real registered tools through `ToolInvoker` — the exact
/// path a future non-Apple provider takes — so tool selection, arguments,
/// invalid calls and confirmation requirements are tested end to end without
/// a real model. Tests drive it single-threaded.
final class ScriptedLanguageModel: LanguageModel, @unchecked Sendable {
    enum Step: Sendable {
        /// Invoke a registered tool; its output is collected for `replyWithToolOutputs`.
        case callTool(name: String, argumentsJSON: String)
        /// End the turn with this text.
        case reply(String)
        /// End the turn with the collected tool outputs (tests assert on real tool text).
        case replyWithToolOutputs
        /// The provider fails this turn.
        case fail(LanguageModelError)
    }

    let descriptor = LanguageModelDescriptor(id: "test.scripted", displayName: "Skript-Modell (Test)")
    var availabilityValue: AgentModelAvailability = .available
    /// Scripts, consumed one per `respond` call across all conversations. An
    /// exhausted queue replies "OK".
    var turns: [[Step]] = []
    private(set) var conversations: [ScriptedConversation] = []

    func availability() -> AgentModelAvailability {
        availabilityValue
    }

    func makeConversation(instructions: String, tools: [any Tool]) -> any LanguageModelConversation {
        let conversation = ScriptedConversation(instructions: instructions, tools: tools) { [unowned self] in
            self.nextScript()
        }
        conversations.append(conversation)
        return conversation
    }

    /// Prompts received by all conversations, in order.
    var receivedPrompts: [String] {
        conversations.flatMap(\.prompts)
    }

    private func nextScript() -> [Step] {
        turns.isEmpty ? [.reply("OK")] : turns.removeFirst()
    }
}

final class ScriptedConversation: LanguageModelConversation, @unchecked Sendable {
    let instructions: String
    let tools: [any Tool]
    private(set) var prompts: [String] = []
    private let nextScript: @Sendable () -> [ScriptedLanguageModel.Step]

    init(
        instructions: String,
        tools: [any Tool],
        nextScript: @escaping @Sendable () -> [ScriptedLanguageModel.Step]
    ) {
        self.instructions = instructions
        self.tools = tools
        self.nextScript = nextScript
    }

    var toolNames: [String] {
        tools.map { $0.name }
    }

    func respond(to prompt: String) async throws -> LanguageModelResponse {
        prompts.append(prompt)
        var calledToolNames: [String] = []
        var toolOutputs: [String] = []
        for step in nextScript() {
            switch step {
            case .callTool(let name, let argumentsJSON):
                calledToolNames.append(name)
                toolOutputs.append(
                    try await ToolInvoker.invoke(toolNamed: name, in: tools, argumentsJSON: argumentsJSON)
                )
            case .reply(let text):
                return LanguageModelResponse(text: text, calledToolNames: calledToolNames)
            case .replyWithToolOutputs:
                return LanguageModelResponse(
                    text: toolOutputs.joined(separator: "\n"),
                    calledToolNames: calledToolNames
                )
            case .fail(let error):
                throw error
            }
        }
        return LanguageModelResponse(text: toolOutputs.joined(separator: "\n"), calledToolNames: calledToolNames)
    }
}
