# Architecture

PersonalAgent is not primarily a chatbot. The core is a deterministic pipeline; the language
model sits at the end of it and only talks to the user.

```
Apple Reminders / Calendar → task history → analytics → recommendations → language model → confirmed actions
```

## Layers and boundaries

| Layer | Folder | May import |
|---|---|---|
| Domain | `Domain/` | Foundation only: plain value types (`Task`, `TaskEvent`, `ReminderRecommendation`, …) |
| Analytics & recommendations | `Analytics/`, `Recommendations/` | Domain; pure functions, same input → same output |
| Persistence | `Persistence/` | SQLite3; repositories, versioned append-only migrations |
| Services | `Services/` | the Apple frameworks, each in its own folder |
| Agent | `Agent/` | Domain, services via protocols, `FoundationModels` for tool definitions |
| UI | `UI/` | SwiftUI and view models; no framework types from the services |
| Composition | `App/` | wires everything in `AppContainer`, owns the confirmation gates |

Framework rules are enforced by convention and review: `EventKit` appears only in
`Services/Reminders` and `Services/Calendar`, `UserNotifications` only in
`Services/Notifications`, `FoundationModels` only in `Agent/` and `Services/Model/`. Every
service sits behind a protocol, so tests replace it with a fake.

## Task history

`TaskSyncService` reads all reminders, compares them with the last stored state
(`TaskChangeDetector`) and records the differences as `TaskEvent`s: created, modified,
completed, reopened, postponed, overdue, plus reminder and recommendation events. Reminders deleted in Apple Reminders keep their history.

Recurring reminders need special handling: completing one in Apple Reminders does not mark it
completed. It stays open and its due date jumps to the next occurrence. The sync therefore
reads the repeat rule (`TaskRecurrence`) and treats a forward move by whole recurrence steps as
a completion, not a postponement. Any other move of a recurring reminder is still a
postponement.
The analytics work exclusively on this event history, which is why they can answer "how
often was this postponed?", something EventKit itself cannot.

## Analytics

Each analyser answers one question and reports its sample size:

- `CompletionAnalyzer`: completion rate and delays relative to the due date
- `PostponementAnalyzer`: how often and by how much tasks are pushed back
- `RecurrenceAnalyzer`: behavioural recurrence (for example "every Monday") without an explicit repeat rule
- `TimeWindowAnalyzer`: preferred time of day for completing a task
- `ProcrastinationScorer`: weighted score from the above, with configurable weights
- `ReminderEffectivenessAnalyzer`: which reminders were followed by a completion

Below a minimum sample size an analyser returns "insufficient data" instead of a guess. The
Insights screen and the tools show exactly these values; the model is never asked to compute
statistics.

## Recommendations

`RecommendationEngine` combines a task's analysis with free calendar slots
(`ReminderTimingEngine`) into scored candidate reminder times, each with machine-readable
reasons such as `frequently_postponed` or `historically_successful_time`. Recommendations are persisted;
`OutcomeSweeper` later links them to what happened (accepted, ignored, completed, …) and
`RecommendationEvaluator` uses those outcomes to adjust confidence for the next suggestion.

## Agent turn

1. `AgentController` checks model availability and prepends a compact context block (current
   date and time, number of open tasks, up to three overdue titles) to the user's message. The
   model never sees the whole database.
2. The model decides which tools to call. Every tool is registered in `ToolRegistry` with an
   access level: read-only or mutation.
3. Tool arguments arrive as typed `@Generable` structures and are validated again in the tool:
   titles are resolved against stored tasks (`TaskTitleResolver`), dates must be in range,
   unknown values are rejected with a German message the model can relay.
4. The model phrases the tool output as the answer.

### Confirmation gate

Mutation tools (`createReminder`, `scheduleNotification`) never perform the action inside the
tool call. They deposit a proposal in `ReminderCreationCenter` or `NotificationProposalCenter`
and tell the model that the user still has to confirm. The chat shows the proposal as a card;
only the user's tap executes it. Because the gate lives in the app rather than in the prompt,
no model or provider can bypass it.

## Model providers

The agent depends only on the `LanguageModel` protocol (`Services/Model/LanguageModel.swift`):

| Requirement | Meaning |
|---|---|
| `availability()` | cheap check with a German reason when the model cannot be used |
| `makeConversation(instructions:tools:)` | new conversation with the registered tools |
| `respond(to:)` | one turn including the provider's own tool-calling loop |
| errors | mapped to `LanguageModelError` (`contextWindowExceeded`, `unavailable`, `busy`, `refused`, …) |

`FoundationModelsLanguageModel` is the only provider today. A provider without native tool
calling would render the tool schemas into its prompt and execute calls through `ToolInvoker`,
which refuses unregistered tools and arguments that do not decode into the declared types.

### Provider evaluation

`AgentProviderEvaluationTests` defines a fixed set of scenarios; each provider is a subclass and
runs them unchanged. The report measures tool-selection accuracy, answer acceptance (does the
reply contain the facts the tools returned?) and latency, and **asserts** that no scenario
produced an unconfirmed side effect. A scripted model provides a deterministic reference run;
the Foundation Models run is skipped where Apple Intelligence is unavailable.

```bash
xcodebuild -project PersonalAgent.xcodeproj -scheme PersonalAgent \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PersonalAgentTests/ScriptedProviderEvaluationTests test
```

## Privacy

- No network code, no analytics SDKs, no third-party dependencies.
- The database stores tasks, task events, recommendations and their outcomes. It does not store
  prompts, model replies or model reasoning.
- Reminders and Calendar access use the iOS permission dialogs; the app explains in German that
  all data stays on the device.
