import XCTest
@testable import PersonalAgent

/// The JSON → typed-arguments path a non-Apple provider uses to call the
/// registered tools.
@MainActor
final class ToolInvokerTests: XCTestCase {
    func testDecodesArgumentsAndRunsTheTool() async throws {
        let environment = try await AgentTestEnvironment.make()

        let output = try await ToolInvoker.invoke(
            toolNamed: "findFreeTime",
            in: environment.registry.tools,
            argumentsJSON: "{\"daysFromToday\":1,\"durationMinutes\":45}"
        )

        XCTAssertTrue(output.contains("Montag, 31.08.2026"))
        XCTAssertTrue(output.contains("mindestens 45 Minuten"))
        XCTAssertTrue(output.contains("18:00–19:30"))
        XCTAssertEqual(environment.calendarService.recordedQueries.count, 1)
        XCTAssertEqual(environment.calendarService.recordedQueries.first?.duration, 2_700)
    }

    func testEmptyObjectSatisfiesAnArgumentlessTool() async throws {
        let environment = try await AgentTestEnvironment.make()

        let output = try await ToolInvoker.invoke(
            toolNamed: "getOpenTasks",
            in: environment.registry.tools,
            argumentsJSON: "{}"
        )

        XCTAssertTrue(output.contains("Offene Aufgaben (3):"))
    }

    func testOmittedOptionalArgumentsFallBackToToolDefaults() async throws {
        let environment = try await AgentTestEnvironment.make()

        let output = try await ToolInvoker.invoke(
            toolNamed: "createReminder",
            in: environment.registry.tools,
            argumentsJSON: "{\"title\":\"Reifen wechseln\"}"
        )

        XCTAssertTrue(output.contains("Vorschlag erstellt"))
        XCTAssertEqual(environment.reminderCreationCenter.pending?.title, "Reifen wechseln")
        XCTAssertNil(environment.reminderCreationCenter.pending?.dueDate)
    }

    func testUnknownToolIsRefused() async throws {
        let environment = try await AgentTestEnvironment.make()

        do {
            _ = try await ToolInvoker.invoke(toolNamed: "searchWeb", in: environment.registry.tools, argumentsJSON: "{}")
            XCTFail("expected an error")
        } catch let error as LanguageModelError {
            XCTAssertEqual(
                error,
                .toolCallFailed(
                    toolName: "searchWeb",
                    details: "Unbekanntes Werkzeug – nur registrierte Werkzeuge dürfen aufgerufen werden."
                )
            )
        }
    }

    func testMalformedJSONNeverReachesTheTool() async throws {
        let environment = try await AgentTestEnvironment.make()

        await assertInvalidArguments(toolNamed: "findFreeTime", json: "daysFromToday=1", in: environment)

        XCTAssertTrue(environment.calendarService.recordedQueries.isEmpty)
    }

    func testMissingRequiredArgumentIsRejected() async throws {
        let environment = try await AgentTestEnvironment.make()

        await assertInvalidArguments(toolNamed: "findFreeTime", json: "{\"durationMinutes\":30}", in: environment)

        XCTAssertTrue(environment.calendarService.recordedQueries.isEmpty)
    }

    func testWrongArgumentTypeIsRejected() async throws {
        let environment = try await AgentTestEnvironment.make()

        await assertInvalidArguments(toolNamed: "findFreeTime", json: "{\"daysFromToday\":\"morgen\"}", in: environment)

        XCTAssertTrue(environment.calendarService.recordedQueries.isEmpty)
    }

    private func assertInvalidArguments(
        toolNamed name: String,
        json: String,
        in environment: AgentTestEnvironment,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            let output = try await ToolInvoker.invoke(toolNamed: name, in: environment.registry.tools, argumentsJSON: json)
            XCTFail("expected rejected arguments, got output: \(output)", file: file, line: line)
        } catch let error as LanguageModelError {
            guard case .toolCallFailed(let toolName, let details) = error else {
                return XCTFail("unexpected error \(error)", file: file, line: line)
            }
            XCTAssertEqual(toolName, name, file: file, line: line)
            XCTAssertTrue(details.hasPrefix("Ungültige Argumente"), details, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
