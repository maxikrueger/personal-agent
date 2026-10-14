import SwiftUI

@main
struct PersonalAgentApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            TabView {
                AgentView(viewModel: container.agentViewModel)
                    .tabItem {
                        Label("Agent", systemImage: "bubble.left.and.text.bubble.right")
                    }
                InsightsView(viewModel: container.insightsViewModel)
                    .tabItem {
                        Label("Einblicke", systemImage: "chart.bar.xaxis")
                    }
            }
            .task {
                container.synchronizeHistory()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                container.synchronizeHistory()
            }
        }
    }
}
