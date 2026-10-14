import XCTest
@testable import PersonalAgent

@MainActor
final class InsightsViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_098_400)

    private func makeWorkingBuilder(
        reminders: FakeReminderService = FakeReminderService()
    ) async throws -> InsightsBuilder {
        reminders.fullAccess = false
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await provider.preparedDatabase()
        try await TaskRepository(database: database).upsert(makeTask(title: "Offen"), updatedAt: now)
        let syncService = TaskSyncService(reminderService: reminders, databaseProvider: provider)
        let fixedNow = now
        return InsightsBuilder(
            databaseProvider: provider,
            syncService: syncService,
            calendar: utcCalendar(),
            now: { fixedNow }
        )
    }

    func testRefreshLoadsReport() async throws {
        let viewModel = InsightsViewModel(builder: try await makeWorkingBuilder())
        XCTAssertEqual(viewModel.state, .loading)

        await viewModel.refresh()

        guard case .loaded(let report) = viewModel.state else {
            XCTFail("Expected loaded state, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(report.openTaskCount, 1)
    }

    func testRefreshFailureProducesGermanErrorState() async {
        let reminders = FakeReminderService()
        reminders.fullAccess = false
        let provider = DatabaseProvider(path: "/nonexistent-personalagent-dir/insights.sqlite")
        let syncService = TaskSyncService(reminderService: reminders, databaseProvider: provider)
        let viewModel = InsightsViewModel(
            builder: InsightsBuilder(
                databaseProvider: provider,
                syncService: syncService,
                calendar: utcCalendar(),
                now: { Date(timeIntervalSince1970: 1_788_098_400) }
            )
        )

        await viewModel.refresh()

        guard case .failed(let message) = viewModel.state else {
            XCTFail("Expected failed state, got \(viewModel.state)")
            return
        }
        XCTAssertTrue(message.contains("Einblicke"))
    }

    func testOutcomeTextIsReadable() {
        var totals = RecommendationOutcomeSummary()
        totals.accepted = 2
        totals.rejected = 1
        totals.completed = 3

        let text = InsightsView.outcomeText(totals)

        XCTAssertTrue(text.contains("2 angenommen"))
        XCTAssertTrue(text.contains("1 abgelehnt"))
        XCTAssertTrue(text.contains("3 erledigt"))
    }

    // MARK: - Reminders access

    func testMissingAccessIsOfferedWhileHistoryStillLoads() async throws {
        let viewModel = InsightsViewModel(builder: try await makeWorkingBuilder())

        await viewModel.refresh()

        XCTAssertTrue(viewModel.needsReminderAccess)
        guard case .loaded = viewModel.state else {
            XCTFail("Stored history must still be shown, got \(viewModel.state)")
            return
        }
    }

    func testGrantedAccessHidesTheOffer() async throws {
        let reminders = FakeReminderService()
        let builder = try await makeWorkingBuilder(reminders: reminders)
        reminders.fullAccess = true
        let viewModel = InsightsViewModel(builder: builder)

        await viewModel.refresh()

        XCTAssertFalse(viewModel.needsReminderAccess)
    }

    func testRequestingAccessSynchronizesImmediately() async throws {
        let reminders = FakeReminderService()
        let viewModel = InsightsViewModel(builder: try await makeWorkingBuilder(reminders: reminders))
        let fetchesBefore = reminders.fetchAllCallCount

        await viewModel.requestReminderAccess()

        XCTAssertNil(viewModel.accessMessage)
        XCTAssertEqual(reminders.fetchAllCallCount, fetchesBefore + 1)
    }

    func testDeniedAccessExplainsWhereToEnableIt() async throws {
        let reminders = FakeReminderService()
        let viewModel = InsightsViewModel(builder: try await makeWorkingBuilder(reminders: reminders))
        reminders.accessResult = .failure(ReminderServiceError.accessDenied)

        await viewModel.requestReminderAccess()

        XCTAssertEqual(viewModel.accessMessage, ReminderServiceError.accessDenied.errorDescription)
        XCTAssertTrue(viewModel.needsReminderAccess)
    }
}
