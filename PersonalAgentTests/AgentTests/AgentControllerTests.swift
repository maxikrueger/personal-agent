import XCTest
@testable import PersonalAgent

/// Agent tests with a deterministic provider: tool
/// selection, tool arguments, invalid tool calls and confirmation requirements
/// run through the real `AgentController` and the real registered tools —
/// only the model is scripted.
@MainActor
final class AgentControllerTests: XCTestCase {
    private static let expectedPrefix =
        "[Kontext: Heute ist Sonntag, 30.08.2026, 14:00 Uhr. Offene Aufgaben: 3, davon überfällig: Steuererklärung abgeben.]"

    private struct Subject {
        let controller: AgentController
        let model: ScriptedLanguageModel
        let environment: AgentTestEnvironment
    }

    private func makeSubject(turns: [[ScriptedLanguageModel.Step]] = []) async throws -> Subject {
        let environment = try await AgentTestEnvironment.make()
        let model = ScriptedLanguageModel()
        model.turns = turns
        return Subject(controller: environment.makeController(model: model), model: model, environment: environment)
    }

    // MARK: - Provider seam

    func testUnavailableModelFailsBeforeAnyConversation() async throws {
        let subject = try await makeSubject()
        subject.model.availabilityValue = .unavailable(reason: "Testgrund")

        await assertSendFails(subject.controller, "Hallo", equals: .modelUnavailable(reason: "Testgrund"))

        XCTAssertTrue(subject.model.conversations.isEmpty)
        XCTAssertEqual(subject.controller.availability(), .unavailable(reason: "Testgrund"))
    }

    func testAvailabilityIsDelegatedToTheProvider() async throws {
        let subject = try await makeSubject()

        XCTAssertEqual(subject.controller.availability(), .available)
    }

    func testContextPrefixInstructionsAndRegistryReachTheProvider() async throws {
        let subject = try await makeSubject(turns: [[.reply("Heute ist Sonntag.")]])

        let reply = try await subject.controller.send("Welcher Tag ist heute?")

        XCTAssertEqual(reply, "Heute ist Sonntag.")
        XCTAssertEqual(subject.model.receivedPrompts, [Self.expectedPrefix + "\nWelcher Tag ist heute?"])
        XCTAssertEqual(subject.model.conversations.first?.instructions, AgentInstructions.text)
        XCTAssertEqual(subject.model.conversations.first?.toolNames, subject.environment.registry.toolNames)
    }

    func testConversationPersistsAcrossTurns() async throws {
        let subject = try await makeSubject(turns: [[.reply("Eins")], [.reply("Zwei")]])

        _ = try await subject.controller.send("Erste Frage")
        _ = try await subject.controller.send("Zweite Frage")

        XCTAssertEqual(subject.model.conversations.count, 1)
        XCTAssertEqual(subject.model.conversations[0].prompts.count, 2)
    }

    // MARK: - Tool selection and arguments

    func testToolSelectionRunsTheRegisteredTool() async throws {
        let subject = try await makeSubject(turns: [[
            .callTool(name: "getOpenTasks", argumentsJSON: "{}"),
            .replyWithToolOutputs,
        ]])

        let reply = try await subject.controller.send("Welche offenen Aufgaben habe ich?")

        XCTAssertTrue(reply.contains("Offene Aufgaben (3):"))
        XCTAssertTrue(reply.contains("Steuererklärung abgeben"))
        XCTAssertTrue(reply.contains("ÜBERFÄLLIG"))
        XCTAssertEqual(subject.environment.reminders.fetchCallCount, 1)
        let calledTools = await subject.controller.lastCalledToolNames
        XCTAssertEqual(calledTools, ["getOpenTasks"])
    }

    func testToolArgumentsAreDecodedAndValidatedByTheTool() async throws {
        // Well-formed JSON with a value outside the tool's range: the tool's own
        // validation answers and no calendar query happens.
        let subject = try await makeSubject(turns: [[
            .callTool(name: "findFreeTime", argumentsJSON: "{\"daysFromToday\":45}"),
            .replyWithToolOutputs,
        ]])

        let reply = try await subject.controller.send("Wann habe ich in 45 Tagen Zeit?")

        XCTAssertTrue(reply.contains("Ungültiger Tag"))
        XCTAssertTrue(subject.environment.calendarService.recordedQueries.isEmpty)
    }

    func testUnregisteredToolIsRefusedAndDropsTheConversation() async throws {
        let subject = try await makeSubject(turns: [
            [.callTool(name: "searchWeb", argumentsJSON: "{}")],
            [.reply("Weiter")],
        ])

        do {
            _ = try await subject.controller.send("Such im Netz nach Reifen.")
            XCTFail("expected an error")
        } catch let error as AgentError {
            guard case .toolFailed(let toolName, _) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(toolName, "searchWeb")
        }

        // A failed turn drops the conversation; the next message starts a new one.
        let reply = try await subject.controller.send("Weiter?")
        XCTAssertEqual(reply, "Weiter")
        XCTAssertEqual(subject.model.conversations.count, 2)
    }

    func testMalformedArgumentsNeverReachTheTool() async throws {
        let subject = try await makeSubject(turns: [[
            .callTool(name: "scheduleNotification", argumentsJSON: "{\"message\": "),
        ]])

        do {
            _ = try await subject.controller.send("Erinnere mich.")
            XCTFail("expected an error")
        } catch let error as AgentError {
            guard case .toolFailed(let toolName, let details) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(toolName, "scheduleNotification")
            XCTAssertTrue(details.contains("Ungültige Argumente"))
        }
        XCTAssertNil(subject.environment.notificationCenter.pending)
    }

    // MARK: - Confirmation requirements

    func testMutationDepositsProposalAndWaitsForConfirmation() async throws {
        let subject = try await makeSubject(turns: [[
            .callTool(
                name: "createReminder",
                argumentsJSON: "{\"title\":\"Reifen wechseln\",\"dueDaysFromToday\":1,\"dueHour\":10}"
            ),
            .replyWithToolOutputs,
        ]])

        let reply = try await subject.controller.send("Lege „Reifen wechseln“ für morgen 10 Uhr an.")

        XCTAssertTrue(reply.contains("noch nichts angelegt"))
        XCTAssertEqual(subject.environment.reminderCreationCenter.pending?.title, "Reifen wechseln")
        XCTAssertTrue(subject.environment.reminders.createdReminders.isEmpty)

        let status = await subject.environment.reminderCreationCenter.confirmPending()

        XCTAssertTrue(status.contains("angelegt"))
        XCTAssertEqual(subject.environment.reminders.createdReminders.count, 1)
    }

    func testNotificationProposalIsNotScheduledWithoutConfirmation() async throws {
        let subject = try await makeSubject(turns: [[
            .callTool(
                name: "scheduleNotification",
                argumentsJSON: "{\"message\":\"Müll rausbringen\",\"daysFromToday\":1,\"hour\":18}"
            ),
            .replyWithToolOutputs,
        ]])

        let reply = try await subject.controller.send("Erinnere mich morgen um 18 Uhr an den Müll.")

        XCTAssertTrue(reply.contains("noch nichts geplant"))
        XCTAssertEqual(subject.environment.notificationCenter.pending?.body, "Müll rausbringen")
        XCTAssertTrue(subject.environment.notifications.scheduled.isEmpty)
    }

    // MARK: - Error taxonomy

    func testGenericFailureMapsToResponseFailedAndResetsTheConversation() async throws {
        let subject = try await makeSubject(turns: [
            [.fail(.generationFailed(details: "Kaputt"))],
            [.reply("Wieder da")],
        ])

        await assertSendFails(subject.controller, "Hallo", equals: .responseFailed(details: "Kaputt"))
        XCTAssertEqual(
            AgentError.responseFailed(details: "Kaputt").errorDescription,
            "Die Anfrage konnte nicht beantwortet werden: Kaputt"
        )

        let reply = try await subject.controller.send("Nochmal")
        XCTAssertEqual(reply, "Wieder da")
        XCTAssertEqual(subject.model.conversations.count, 2)
    }

    func testBusyRefusedAndUnavailableAreMapped() async throws {
        let subject = try await makeSubject(turns: [
            [.fail(.busy)],
            [.fail(.refused(reason: "Abgelehnt."))],
            [.fail(.unavailable(reason: "Modelldaten fehlen."))],
        ])

        await assertSendFails(subject.controller, "A", equals: .modelBusy)
        await assertSendFails(subject.controller, "B", equals: .requestRefused(reason: "Abgelehnt."))
        await assertSendFails(subject.controller, "C", equals: .modelUnavailable(reason: "Modelldaten fehlen."))

        XCTAssertTrue(AgentError.modelBusy.errorDescription?.contains("ausgelastet") ?? false)
        XCTAssertEqual(AgentError.requestRefused(reason: "Abgelehnt.").errorDescription, "Abgelehnt.")
    }

    func testContextOverflowRetriesOnceWithAFreshConversation() async throws {
        let subject = try await makeSubject(turns: [
            [.reply("Erste Antwort")],
            [.fail(.contextWindowExceeded)],
            [.reply("Neu gestartet")],
        ])
        _ = try await subject.controller.send("Erste Frage")

        let reply = try await subject.controller.send("Lange Frage")

        XCTAssertEqual(reply, "Neu gestartet")
        XCTAssertEqual(subject.model.conversations.count, 2)
        XCTAssertEqual(subject.model.conversations[1].prompts, [Self.expectedPrefix + "\nLange Frage"])
    }

    func testRepeatedContextOverflowSurfacesAsMessageTooLong() async throws {
        let subject = try await makeSubject(turns: [
            [.fail(.contextWindowExceeded)],
            [.fail(.contextWindowExceeded)],
        ])

        await assertSendFails(subject.controller, "Riesige Nachricht", equals: .messageTooLong)

        XCTAssertEqual(subject.model.conversations.count, 2)
        XCTAssertTrue(AgentError.messageTooLong.errorDescription?.contains("zu lang") ?? false)
    }

    func testUnknownProviderErrorBecomesResponseFailed() {
        struct Boom: Error {}

        guard case .responseFailed = AgentError(providerError: Boom()) else {
            return XCTFail("expected responseFailed")
        }
    }

    // MARK: - Helpers

    private func assertSendFails(
        _ controller: AgentController,
        _ message: String,
        equals expected: AgentError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            let reply = try await controller.send(message)
            XCTFail("expected \(expected), got reply \(reply)", file: file, line: line)
        } catch let error as AgentError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
