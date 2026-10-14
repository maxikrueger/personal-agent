import XCTest
@testable import PersonalAgent

/// Identical agent tests for every provider. The base class owns the
/// scenarios and the checks; each provider is a subclass that supplies its
/// model. A deterministic provider must pass every check (it proves the
/// harness); a real model is *evaluated* — tool-selection accuracy, answer
/// quality and latency are reported in the test log — while the safety
/// invariant (no side effect without confirmation) is asserted for all.
@MainActor
class AgentProviderEvaluationTests: XCTestCase {
    /// Subclasses return their provider or throw `XCTSkip`.
    func makeModel() throws -> any LanguageModel {
        throw XCTSkip("Abstract base class — the provider subclasses run the scenarios.")
    }

    /// Deterministic providers must satisfy every check; real models are evaluated.
    var isDeterministic: Bool { true }

    /// Hook for a scripted provider to load its reference script for a scenario.
    func prepare(for scenario: AgentEvaluationScenario) {}

    func testAllScenarios() async throws {
        let model = try makeModel()
        let environment = try await AgentTestEnvironment.make()

        let report = await AgentEvaluationRunner.run(
            scenarios: AgentEvaluationScenarios.all,
            model: model,
            environment: environment
        ) { scenario in
            self.prepare(for: scenario)
        }
        print(report.text)

        XCTAssertEqual(report.results.count, AgentEvaluationScenarios.all.count)
        for result in report.results {
            // holds for every provider: nothing created or scheduled without confirmation.
            XCTAssertTrue(result.noUnconfirmedSideEffects, "\(result.scenario): unconfirmed side effect")
            XCTAssertNil(result.error, "\(result.scenario): \(result.error ?? "")")
            if isDeterministic {
                XCTAssertTrue(result.toolSelectionCorrect, "\(result.scenario): called \(result.calledTools)")
                XCTAssertTrue(result.answerAcceptable, "\(result.scenario): \(result.answer)")
                XCTAssertTrue(result.confirmationCorrect, "\(result.scenario): confirmation gate state")
            } else {
                XCTAssertFalse(result.answer.isEmpty, "\(result.scenario): empty answer")
            }
        }
        if isDeterministic {
            XCTAssertEqual(report.toolSelectionAccuracy, 1)
            XCTAssertEqual(report.confirmationAccuracy, 1)
        }
    }
}

/// Deterministic provider: proves the scenarios and the harness.
final class ScriptedProviderEvaluationTests: AgentProviderEvaluationTests {
    private let model = ScriptedLanguageModel()

    override func makeModel() throws -> any LanguageModel {
        model
    }

    override func prepare(for scenario: AgentEvaluationScenario) {
        model.turns = [scenario.referenceScript]
    }
}

/// Apple Foundation Models: runs only where the model is available (iPhone 16e
/// with Apple Intelligence, or a Mac/simulator with it enabled) and is skipped
/// elsewhere, so the regular suite stays model-free.
final class FoundationModelsProviderEvaluationTests: AgentProviderEvaluationTests {
    override var isDeterministic: Bool { false }

    override func makeModel() throws -> any LanguageModel {
        let model = FoundationModelsLanguageModel()
        if case .unavailable(let reason) = model.availability() {
            throw XCTSkip("Apple Foundation Models nicht verfügbar: \(reason)")
        }
        return model
    }
}
