import Foundation

/// Seam between UI and the language model.
protocol AgentControllerProtocol: Sendable {
    func send(_ message: String) async throws -> String
}

/// User-facing agent failures. The German texts live here only.
enum AgentError: Error, LocalizedError, Equatable {
    case modelUnavailable(reason: String)
    case modelBusy
    case requestRefused(reason: String)
    /// Even a fresh conversation could not hold the request.
    case messageTooLong
    case toolFailed(toolName: String, details: String)
    case responseFailed(details: String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            return reason
        case .modelBusy:
            return "Das Sprachmodell ist gerade ausgelastet. Bitte versuche es gleich noch einmal."
        case .requestRefused(let reason):
            return reason
        case .messageTooLong:
            return "Die Nachricht ist zu lang für das Sprachmodell. Bitte formuliere sie kürzer."
        case .toolFailed(let toolName, let details):
            return "Das Werkzeug \(toolName) konnte nicht ausgeführt werden: \(details)"
        case .responseFailed(let details):
            return "Die Anfrage konnte nicht beantwortet werden: \(details)"
        }
    }

    /// Maps the provider-neutral taxonomy onto user-facing errors.
    init(providerError error: any Error) {
        guard let providerError = error as? LanguageModelError else {
            self = .responseFailed(details: error.localizedDescription)
            return
        }
        switch providerError {
        case .contextWindowExceeded:
            self = .messageTooLong
        case .unavailable(let reason):
            self = .modelUnavailable(reason: reason)
        case .busy:
            self = .modelBusy
        case .refused(let reason):
            self = .requestRefused(reason: reason)
        case .toolCallFailed(let toolName, let details):
            self = .toolFailed(toolName: toolName, details: details)
        case .generationFailed(let details):
            self = .responseFailed(details: details)
        }
    }
}

/// Provider-agnostic agent: owns the current
/// conversation, prepends the context block, gates on availability and
/// maps provider failures to user-facing errors. It sees only `LanguageModel`
/// (no framework import in this file), so swapping the provider touches
/// `AppContainer` alone.
actor AgentController: AgentControllerProtocol {
    private let model: any LanguageModel
    private let registry: ToolRegistry
    private let instructions: String
    /// Produces the compact per-request context block prepended to each
    /// user message (current date/time, task situation). Nil = no context.
    private let contextPrefix: (@Sendable () async -> String)?
    private var conversation: (any LanguageModelConversation)?
    /// Tools the provider reported for the most recent turn (used by the provider evaluation).
    private(set) var lastCalledToolNames: [String] = []

    init(
        model: any LanguageModel,
        registry: ToolRegistry,
        instructions: String = AgentInstructions.text,
        contextPrefix: (@Sendable () async -> String)? = nil
    ) {
        self.model = model
        self.registry = registry
        self.instructions = instructions
        self.contextPrefix = contextPrefix
    }

    nonisolated func availability() -> AgentModelAvailability {
        model.availability()
    }

    func send(_ message: String) async throws -> String {
        if case .unavailable(let reason) = model.availability() {
            throw AgentError.modelUnavailable(reason: reason)
        }
        var prompt = message
        if let contextPrefix {
            prompt = await contextPrefix() + "\n" + message
        }
        do {
            return try await respond(to: prompt)
        } catch LanguageModelError.contextWindowExceeded {
            // The transcript no longer fits the model's window: start over once
            // with a fresh conversation instead of failing the turn. The
            // user loses the history, not the answer.
            conversation = nil
            do {
                return try await respond(to: prompt)
            } catch {
                conversation = nil
                throw AgentError(providerError: error)
            }
        } catch {
            // Drop the conversation so a corrupted state does not poison every
            // following request.
            conversation = nil
            throw AgentError(providerError: error)
        }
    }

    private func respond(to prompt: String) async throws -> String {
        let conversation = existingOrNewConversation()
        let response = try await conversation.respond(to: prompt)
        lastCalledToolNames = response.calledToolNames
        return AgentContextComposer.strippingEchoedContext(from: response.text)
    }

    private func existingOrNewConversation() -> any LanguageModelConversation {
        if let conversation {
            return conversation
        }
        let newConversation = model.makeConversation(instructions: instructions, tools: registry.tools)
        conversation = newConversation
        return newConversation
    }
}
