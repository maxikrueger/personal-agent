import SwiftUI

/// Insights screen: every displayed number comes from the
/// deterministic analytics, always with its sample size. Sections with
/// insufficient data say so instead of guessing.
struct InsightsView: View {
    let viewModel: InsightsViewModel

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    ProgressView("Lädt…")
                case .failed(let message):
                    VStack(spacing: 12) {
                        Text(message)
                            .multilineTextAlignment(.center)
                        Button("Erneut versuchen") {
                            _Concurrency.Task {
                                await viewModel.refresh()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                case .loaded(let report):
                    reportList(report)
                }
            }
            .navigationTitle("Einblicke")
            .task {
                await viewModel.refresh()
            }
        }
    }

    private func reportList(_ report: InsightsReport) -> some View {
        List {
            if viewModel.needsReminderAccess {
                Section {
                    Text("PersonalAgent braucht Zugriff auf deine Erinnerungen, um deine Aufgaben auszuwerten. Alle Daten bleiben auf deinem Gerät.")
                    if let message = viewModel.accessMessage {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                    Button("Zugriff erlauben") {
                        _Concurrency.Task {
                            await viewModel.requestReminderAccess()
                        }
                    }
                }
            }

            Section("Überblick") {
                Text("\(report.openTaskCount) offene und \(report.completedTaskCount) erledigte Aufgaben in der Historie")
                if report.outcomeTotals.total > 0 {
                    Text(Self.outcomeText(report.outcomeTotals))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Häufig aufgeschoben") {
                if report.frequentlyPostponed.isEmpty {
                    emptyRow
                } else {
                    ForEach(report.frequentlyPostponed, id: \.title) { insight in
                        row(
                            title: insight.title,
                            detail: "\(insight.postponementCount)× aufgeschoben · Score \(TaskStatisticsFormatter.percentText(insight.procrastinationScore))"
                        )
                    }
                }
            }

            Section("Zuverlässig erledigt") {
                if report.reliablyCompleted.isEmpty {
                    emptyRow
                } else {
                    ForEach(report.reliablyCompleted, id: \.title) { insight in
                        row(
                            title: insight.title,
                            detail: "\(TaskStatisticsFormatter.percentText(insight.completionRate)) erledigt (\(insight.completionCount) von \(insight.cycleCount) Zyklen)"
                        )
                    }
                }
            }

            Section("Beste Erledigungszeiten") {
                if report.bestCompletionWindows.isEmpty {
                    emptyRow
                } else {
                    ForEach(report.bestCompletionWindows, id: \.window) { insight in
                        row(
                            title: "\(TaskStatisticsFormatter.windowText(insight.window.name)) (\(insight.window.startHour)–\(insight.window.endHour) Uhr)",
                            detail: "\(TaskStatisticsFormatter.completionsText(insight.completionCount)) (\(TaskStatisticsFormatter.percentText(insight.share)))"
                        )
                    }
                }
            }

            Section("Wirkung von Erinnerungen") {
                if let effectiveness = report.reminderEffectiveness {
                    row(
                        title: "\(effectiveness.completedAfterCount) von \(effectiveness.firedCount) Erinnerungen",
                        detail: "führten innerhalb eines Tages zur Erledigung (\(TaskStatisticsFormatter.percentText(effectiveness.rate)))"
                    )
                    ForEach(effectiveness.byWindow, id: \.window) { windowEffectiveness in
                        row(
                            title: TaskStatisticsFormatter.windowText(windowEffectiveness.window.name),
                            detail: "\(windowEffectiveness.completedAfterCount) von \(windowEffectiveness.firedCount) erfolgreich (\(TaskStatisticsFormatter.percentText(windowEffectiveness.rate)))"
                        )
                    }
                } else {
                    emptyRow
                }
            }

            Section("Wiederkehrende Muster") {
                if report.recurringPatterns.isEmpty {
                    emptyRow
                } else {
                    ForEach(report.recurringPatterns, id: \.title) { insight in
                        row(
                            title: insight.title,
                            detail: "\(TaskStatisticsFormatter.patternText(insight.pattern)) · Konfidenz \(TaskStatisticsFormatter.percentText(insight.confidence)) · \(TaskStatisticsFormatter.completionsText(insight.sampleSize))"
                        )
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var emptyRow: some View {
        Text("Noch nicht genug Daten.")
            .foregroundStyle(.secondary)
    }

    private func row(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    static func outcomeText(_ totals: RecommendationOutcomeSummary) -> String {
        "Empfehlungen: \(totals.accepted) angenommen, \(totals.rejected) abgelehnt, \(totals.ignored) ignoriert, \(totals.completed) erledigt"
    }
}
