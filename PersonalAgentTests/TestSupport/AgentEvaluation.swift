import Foundation
@testable import PersonalAgent

/// One scenario list, run unchanged against every provider. A scenario
/// states what the user asks, which registered tools a correct answer needs,
/// what the answer must mention, and which confirmation gate must be armed
/// afterwards. `referenceScript` is what an ideal model does — replayed by
/// the scripted provider only; a real provider ignores it.
struct AgentEvaluationScenario: Sendable {
    let name: String
    let message: String
    /// Tools a correct answer requires (any order; extra read-only calls are fine).
    let expectedTools: [String]
    /// A correct answer mentions at least one of these (case-insensitive); empty = no constraint.
    let answerContainsAny: [String]
    let expectsPendingReminderCreation: Bool
    let expectsPendingNotification: Bool
    let referenceScript: [ScriptedLanguageModel.Step]

    init(
        name: String,
        message: String,
        expectedTools: [String],
        answerContainsAny: [String] = [],
        expectsPendingReminderCreation: Bool = false,
        expectsPendingNotification: Bool = false,
        referenceScript: [ScriptedLanguageModel.Step]
    ) {
        self.name = name
        self.message = message
        self.expectedTools = expectedTools
        self.answerContainsAny = answerContainsAny
        self.expectsPendingReminderCreation = expectsPendingReminderCreation
        self.expectsPendingNotification = expectsPendingNotification
        self.referenceScript = referenceScript
    }
}

/// Fixed scenarios over `AgentTestData` / `AgentTestEnvironment`'s seeded data (Sunday
/// 2026-08-30 14:00; three open tasks; tomorrow 18:00–19:30 free).
enum AgentEvaluationScenarios {
    static let all: [AgentEvaluationScenario] = [
        AgentEvaluationScenario(
            name: "openTasks",
            message: "Welche offenen Aufgaben habe ich?",
            expectedTools: ["getOpenTasks"],
            answerContainsAny: [AgentTestData.overdueTitle],
            referenceScript: [
                .callTool(name: "getOpenTasks", argumentsJSON: "{}"),
                .replyWithToolOutputs,
            ]
        ),
        AgentEvaluationScenario(
            name: "statistics",
            message: "Welche Aufgabe schiebe ich am häufigsten auf?",
            expectedTools: ["getTaskStatistics"],
            answerContainsAny: [
                AgentTestData.overdueTitle,
                AgentTestData.dueTomorrowTitle,
                AgentTestData.undatedTitle,
            ],
            referenceScript: [
                .callTool(name: "getTaskStatistics", argumentsJSON: "{}"),
                .replyWithToolOutputs,
            ]
        ),
        AgentEvaluationScenario(
            name: "freeTime",
            message: "Wann habe ich morgen Zeit?",
            expectedTools: ["findFreeTime"],
            answerContainsAny: ["18:00"],
            referenceScript: [
                .callTool(name: "findFreeTime", argumentsJSON: "{\"daysFromToday\":1}"),
                .replyWithToolOutputs,
            ]
        ),
        AgentEvaluationScenario(
            name: "recommendation",
            message: "Wann sollte ich die Steuererklärung am besten erledigen?",
            expectedTools: ["getReminderRecommendation"],
            answerContainsAny: ["Steuererklärung"],
            referenceScript: [
                .callTool(name: "getReminderRecommendation", argumentsJSON: "{\"taskTitle\":\"Steuererklärung\"}"),
                .replyWithToolOutputs,
            ]
        ),
        AgentEvaluationScenario(
            name: "createReminder",
            message: "Lege eine neue Aufgabe „Reifen wechseln“ für morgen um 10 Uhr an.",
            expectedTools: ["createReminder"],
            answerContainsAny: ["Reifen wechseln"],
            expectsPendingReminderCreation: true,
            referenceScript: [
                .callTool(
                    name: "createReminder",
                    argumentsJSON: "{\"title\":\"Reifen wechseln\",\"dueDaysFromToday\":1,\"dueHour\":10}"
                ),
                .replyWithToolOutputs,
            ]
        ),
        AgentEvaluationScenario(
            name: "scheduleNotification",
            message: "Erinnere mich morgen um 18 Uhr daran, den Müll rauszubringen.",
            expectedTools: ["scheduleNotification"],
            answerContainsAny: ["18:00"],
            expectsPendingNotification: true,
            referenceScript: [
                .callTool(
                    name: "scheduleNotification",
                    argumentsJSON: "{\"message\":\"Müll rausbringen\",\"daysFromToday\":1,\"hour\":18}"
                ),
                .replyWithToolOutputs,
            ]
        ),
    ]
}

struct AgentEvaluationResult: Sendable {
    let scenario: String
    let answer: String
    let error: String?
    let calledTools: [String]
    let latency: TimeInterval
    /// Every expected tool was called and no unexpected mutation tool was.
    let toolSelectionCorrect: Bool
    let answerAcceptable: Bool
    /// Exactly the expected confirmation gates are armed after the turn.
    let confirmationCorrect: Bool
    /// invariant: nothing was created or scheduled without the user's confirmation.
    let noUnconfirmedSideEffects: Bool

    var passed: Bool {
        error == nil && toolSelectionCorrect && answerAcceptable && confirmationCorrect && noUnconfirmedSideEffects
    }
}

struct AgentEvaluationReport: Sendable {
    let provider: LanguageModelDescriptor
    let results: [AgentEvaluationResult]

    var toolSelectionAccuracy: Double { rate(\.toolSelectionCorrect) }
    var answerAcceptanceRate: Double { rate(\.answerAcceptable) }
    var confirmationAccuracy: Double { rate(\.confirmationCorrect) }

    var medianLatency: TimeInterval {
        let latencies = results.map(\.latency).sorted()
        guard !latencies.isEmpty else { return 0 }
        return latencies[latencies.count / 2]
    }

    /// Markdown table for test logs and evaluation reports.
    var text: String {
        var lines = [
            "Provider evaluation: \(provider.displayName) [\(provider.id)]",
            "| Scenario | Called tools | Tools ok | Answer ok | Confirmation ok | No side effects | Latency |",
            "|---|---|---|---|---|---|---|",
        ]
        for result in results {
            lines.append(
                "| \(result.scenario) | \(result.calledTools.joined(separator: ", ")) | \(mark(result.toolSelectionCorrect)) | \(mark(result.answerAcceptable)) | \(mark(result.confirmationCorrect)) | \(mark(result.noUnconfirmedSideEffects)) | \(String(format: "%.2f s", result.latency)) |"
            )
            if let error = result.error {
                lines.append("|   error | \(error) | | | | | |")
            }
        }
        lines.append(
            "Tool selection \(percent(toolSelectionAccuracy)) · answers \(percent(answerAcceptanceRate)) · confirmation \(percent(confirmationAccuracy)) · median latency \(String(format: "%.2f s", medianLatency))"
        )
        return lines.joined(separator: "\n")
    }

    private func rate(_ predicate: (AgentEvaluationResult) -> Bool) -> Double {
        guard !results.isEmpty else { return 0 }
        return Double(results.filter(predicate).count) / Double(results.count)
    }

    private func mark(_ value: Bool) -> String {
        value ? "yes" : "NO"
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }
}

/// Runs every scenario in a fresh conversation against one provider and
/// measures what asks for; the same runner serves every provider.
enum AgentEvaluationRunner {
    @MainActor
    static func run(
        scenarios: [AgentEvaluationScenario],
        model: any LanguageModel,
        environment: AgentTestEnvironment,
        prepare: (AgentEvaluationScenario) -> Void = { _ in }
    ) async -> AgentEvaluationReport {
        let mutationTools = Set(environment.registry.mutationToolNames)
        var results: [AgentEvaluationResult] = []
        for scenario in scenarios {
            prepare(scenario)
            let createdBefore = environment.reminders.createdReminders.count
            let scheduledBefore = environment.notifications.scheduled.count
            // Scenarios are independent: each one starts a fresh conversation.
            let controller = environment.makeController(model: model)

            let start = Date()
            var answer = ""
            var errorText: String?
            do {
                answer = try await controller.send(scenario.message)
            } catch {
                errorText = AgentViewModel.errorText(for: error)
            }
            let latency = Date().timeIntervalSince(start)
            let calledTools = await controller.lastCalledToolNames

            let unexpectedMutations = calledTools.filter { mutationTools.contains($0) && !scenario.expectedTools.contains($0) }
            let toolSelectionCorrect = scenario.expectedTools.allSatisfy(calledTools.contains) && unexpectedMutations.isEmpty
            let answerAcceptable = scenario.answerContainsAny.isEmpty
                || scenario.answerContainsAny.contains { answer.localizedCaseInsensitiveContains($0) }
            let confirmationCorrect = (environment.reminderCreationCenter.pending != nil) == scenario.expectsPendingReminderCreation
                && (environment.notificationCenter.pending != nil) == scenario.expectsPendingNotification
            let noUnconfirmedSideEffects = environment.reminders.createdReminders.count == createdBefore
                && environment.notifications.scheduled.count == scheduledBefore

            results.append(
                AgentEvaluationResult(
                    scenario: scenario.name,
                    answer: answer,
                    error: errorText,
                    calledTools: calledTools,
                    latency: latency,
                    toolSelectionCorrect: toolSelectionCorrect,
                    answerAcceptable: answerAcceptable,
                    confirmationCorrect: confirmationCorrect,
                    noUnconfirmedSideEffects: noUnconfirmedSideEffects
                )
            )
            await environment.declinePendingProposals()
        }
        return AgentEvaluationReport(provider: model.descriptor, results: results)
    }
}
