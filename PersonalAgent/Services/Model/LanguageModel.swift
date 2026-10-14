import Foundation
import FoundationModels

/// Model-provider seam. The agent layer talks only to
/// this protocol and never learns which model answers: Apple Foundation Models
/// is the first provider; a future Core AI/Gemma provider conforms to the same
/// contract and adapts the registered tools itself (tools, analytics,
/// database, recommendations and EventKit services stay untouched).
///
/// `LanguageModel` is the abstraction.
/// The Apple branch is `FoundationModelsLanguageModel` because the framework
/// already owns the name `SystemLanguageModel`.
protocol LanguageModel: Sendable {
    var descriptor: LanguageModelDescriptor { get }

    /// Cheap, synchronous check performed before every request.
    func availability() -> AgentModelAvailability

    /// Starts a fresh conversation with the agent's instructions and the
    /// registered tools. The conversation owns the transcript; the agent keeps
    /// it across turns and drops it on failure.
    func makeConversation(instructions: String, tools: [any Tool]) -> any LanguageModelConversation
}

/// One multi-turn conversation with a provider. A turn runs the provider's
/// complete tool-calling loop; only the final answer comes back.
protocol LanguageModelConversation: Sendable {
    func respond(to prompt: String) async throws -> LanguageModelResponse
}

/// Identifies a provider for settings and evaluation reports.
struct LanguageModelDescriptor: Equatable, Sendable {
    let id: String
    let displayName: String
}

struct LanguageModelResponse: Equatable, Sendable {
    let text: String
    /// Names of the tools the provider invoked during this turn, in call order.
    /// Names only — no arguments, no outputs — so it is privacy-safe to keep.
    let calledToolNames: [String]
}

enum AgentModelAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

/// Provider-neutral failure taxonomy: every provider maps its own errors
/// onto these cases so the agent reacts uniformly — retry once with a fresh
/// conversation on `contextWindowExceeded`, explain `busy`, and so on.
enum LanguageModelError: Error, Equatable, Sendable {
    /// Instructions + tool schemas + transcript no longer fit the model's window.
    case contextWindowExceeded
    /// The model or its assets cannot be used right now (German reason for the user).
    case unavailable(reason: String)
    /// Rate-limited or already serving another request.
    case busy
    /// The model declined to answer (guardrails, refusal).
    case refused(reason: String)
    /// A registered tool could not be invoked or failed while running.
    case toolCallFailed(toolName: String, details: String)
    /// Any other generation failure.
    case generationFailed(details: String)
}
