import Foundation
import FoundationModels

/// Apple Foundation Models provider. The only code that creates a
/// `LanguageModelSession`.
struct FoundationModelsLanguageModel: LanguageModel {
    static let descriptor = LanguageModelDescriptor(
        id: "apple.foundation-models",
        displayName: "Apple Intelligence (auf dem Gerät)"
    )

    var descriptor: LanguageModelDescriptor { Self.descriptor }

    func availability() -> AgentModelAvailability {
        Self.availability(for: SystemLanguageModel.default.availability)
    }

    /// Pure mapping (unit-tested): framework availability → user-facing German reason.
    static func availability(for availability: SystemLanguageModel.Availability) -> AgentModelAvailability {
        switch availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "Dieses Gerät unterstützt Apple Intelligence nicht.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence ist nicht aktiviert. Bitte aktiviere es in den iOS-Einstellungen.")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "Das Sprachmodell wird noch vorbereitet. Bitte versuche es in ein paar Minuten erneut.")
        case .unavailable:
            return .unavailable(reason: "Das Sprachmodell ist derzeit nicht verfügbar.")
        @unknown default:
            return .unavailable(reason: "Das Sprachmodell ist derzeit nicht verfügbar.")
        }
    }

    func makeConversation(instructions: String, tools: [any Tool]) -> any LanguageModelConversation {
        FoundationModelsConversation(instructions: instructions, tools: tools)
    }
}

/// Wraps one `LanguageModelSession`. The session runs the tool-calling loop
/// itself; this actor only translates results and errors into the
/// provider-neutral types.
actor FoundationModelsConversation: LanguageModelConversation {
    private let session: LanguageModelSession

    init(instructions: String, tools: [any Tool]) {
        session = LanguageModelSession(tools: tools, instructions: instructions)
    }

    func respond(to prompt: String) async throws -> LanguageModelResponse {
        let entriesBefore = session.transcript.count
        do {
            let response = try await session.respond(to: prompt)
            let newEntries = Array(session.transcript).dropFirst(entriesBefore)
            return LanguageModelResponse(
                text: response.content,
                calledToolNames: Self.calledToolNames(in: newEntries)
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapped(error)
        } catch let error as LanguageModelSession.ToolCallError {
            throw LanguageModelError.toolCallFailed(
                toolName: error.tool.name,
                details: error.underlyingError.localizedDescription
            )
        } catch {
            throw Self.mappedUntyped(error)
        }
    }

    /// Some generation failures (code −1 while Apple Intelligence has no model
    /// assets) arrive as a bridged `NSError` that does not cast to
    /// `GenerationError`. They get the same German message instead of raw text.
    static func mappedUntyped(_ error: Error) -> LanguageModelError {
        let nsError = error as NSError
        if nsError.domain.contains("GenerationError") {
            return unknownGenerationFailure(code: nsError.code)
        }
        return .generationFailed(details: error.localizedDescription)
    }

    private static func unknownGenerationFailure(code: Int) -> LanguageModelError {
        .generationFailed(
            details: "Das Sprachmodell hat einen unbekannten Fehler gemeldet (Code \(code)). Falls Apple Intelligence noch Modelle lädt, versuche es später erneut."
        )
    }

    /// Tool names recorded in the transcript entries of one turn.
    static func calledToolNames(in entries: some Sequence<Transcript.Entry>) -> [String] {
        entries.flatMap { entry -> [String] in
            guard case .toolCalls(let calls) = entry else { return [] }
            return calls.map(\.toolName)
        }
    }

    static func mapped(_ error: LanguageModelSession.GenerationError) -> LanguageModelError {
        switch error {
        case .exceededContextWindowSize:
            return .contextWindowExceeded
        case .assetsUnavailable:
            return .unavailable(reason: "Das Sprachmodell ist derzeit nicht verfügbar. Bitte versuche es später erneut.")
        case .rateLimited, .concurrentRequests:
            return .busy
        case .guardrailViolation:
            return .refused(reason: "Das Sprachmodell hat diese Anfrage aus Sicherheitsgründen abgelehnt.")
        case .refusal:
            return .refused(reason: "Das Sprachmodell hat diese Anfrage abgelehnt.")
        case .unsupportedLanguageOrLocale:
            return .generationFailed(details: "Diese Sprache wird vom Sprachmodell nicht unterstützt.")
        case .decodingFailure:
            return .generationFailed(details: "Das Sprachmodell hat eine ungültige Antwort erzeugt. Bitte versuche es noch einmal.")
        case .unsupportedGuide:
            return .generationFailed(details: "Das Sprachmodell unterstützt diese Anfrageform nicht.")
        @unknown default:
            // Seen in practice while Apple Intelligence was still downloading its
            // models: availability reports "available", generation fails with an
            // unlisted case. Keep the code for diagnosis, but no raw English text.
            return unknownGenerationFailure(code: (error as NSError).code)
        }
    }
}
