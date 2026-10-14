import Foundation
import Observation

@MainActor
@Observable
final class InsightsViewModel {
    enum State: Equatable {
        case loading
        case loaded(InsightsReport)
        case failed(String)
    }

    private(set) var state: State = .loading
    /// Reminders access has not been granted: the screen offers a button to
    /// ask for it instead of silently showing an empty history.
    private(set) var needsReminderAccess = false
    /// German explanation when the access request failed (e.g. denied).
    private(set) var accessMessage: String?

    private let builder: InsightsBuilder

    init(builder: InsightsBuilder) {
        self.builder = builder
    }

    func refresh() async {
        needsReminderAccess = !(await builder.hasReminderAccess())
        do {
            state = .loaded(try await builder.buildReport())
        } catch {
            state = .failed("Die Einblicke konnten nicht geladen werden. Bitte später erneut versuchen.")
        }
    }

    func requestReminderAccess() async {
        accessMessage = nil
        do {
            try await builder.requestReminderAccess()
        } catch {
            accessMessage = (error as? LocalizedError)?.errorDescription
                ?? "Der Zugriff auf Erinnerungen konnte nicht angefragt werden."
        }
        await refresh()
    }
}
