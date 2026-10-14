import FoundationModels
import XCTest
@testable import PersonalAgent

/// Pure parts of the Apple provider. The session itself needs a device with
/// Apple Intelligence — see `FoundationModelsProviderEvaluationTests`.
final class FoundationModelsLanguageModelTests: XCTestCase {
    func testDescriptorIdentifiesTheAppleProvider() {
        let model = FoundationModelsLanguageModel()

        XCTAssertEqual(model.descriptor.id, "apple.foundation-models")
        XCTAssertEqual(model.descriptor, FoundationModelsLanguageModel.descriptor)
        XCTAssertFalse(model.descriptor.displayName.isEmpty)
    }

    func testAvailabilityMapping() {
        XCTAssertEqual(FoundationModelsLanguageModel.availability(for: .available), .available)
        XCTAssertEqual(
            FoundationModelsLanguageModel.availability(for: .unavailable(.deviceNotEligible)),
            .unavailable(reason: "Dieses Gerät unterstützt Apple Intelligence nicht.")
        )
        XCTAssertEqual(
            FoundationModelsLanguageModel.availability(for: .unavailable(.appleIntelligenceNotEnabled)),
            .unavailable(reason: "Apple Intelligence ist nicht aktiviert. Bitte aktiviere es in den iOS-Einstellungen.")
        )
        XCTAssertEqual(
            FoundationModelsLanguageModel.availability(for: .unavailable(.modelNotReady)),
            .unavailable(reason: "Das Sprachmodell wird noch vorbereitet. Bitte versuche es in ein paar Minuten erneut.")
        )
    }

    func testNoTranscriptEntriesMeansNoToolCalls() {
        XCTAssertEqual(FoundationModelsConversation.calledToolNames(in: [Transcript.Entry]()), [])
    }

    func testBridgedGenerationErrorGetsGermanMessage() {
        let bridged = NSError(domain: "FoundationModels.LanguageModelSession.GenerationError", code: -1)

        let mapped = FoundationModelsLanguageModel.mappedUntyped(bridged)

        guard case .generationFailed(let details) = mapped else {
            XCTFail("Expected generationFailed, got \(mapped)")
            return
        }
        XCTAssertTrue(details.contains("Code -1"))
        XCTAssertTrue(details.contains("Apple Intelligence"))
    }

    func testOtherErrorsKeepTheirDescription() {
        let other = NSError(domain: "SomethingElse", code: 7, userInfo: [NSLocalizedDescriptionKey: "Fehlertext"])

        guard case .generationFailed(let details) = FoundationModelsLanguageModel.mappedUntyped(other) else {
            XCTFail("Expected generationFailed")
            return
        }
        XCTAssertEqual(details, "Fehlertext")
    }
}
