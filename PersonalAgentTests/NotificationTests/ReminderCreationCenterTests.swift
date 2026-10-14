import XCTest
@testable import PersonalAgent

@MainActor
final class ReminderCreationCenterTests: XCTestCase {
    private let calendar = utcCalendar()
    private var dueDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 18))!
    }

    private struct Environment {
        let center: ReminderCreationCenter
        let reminders: FakeReminderService
    }

    private func makeEnvironment(authorized: Bool = true) async throws -> Environment {
        let reminders = FakeReminderService()
        reminders.fullAccess = authorized
        let database = SQLiteDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        _ = try await provider.preparedDatabase()
        let syncService = TaskSyncService(reminderService: reminders, databaseProvider: provider)
        let center = ReminderCreationCenter(
            reminderService: reminders,
            syncService: syncService,
            calendar: calendar
        )
        return Environment(center: center, reminders: reminders)
    }

    private func makeProposal(dueDate: Date? = nil) -> ReminderCreationProposal {
        ReminderCreationProposal(id: UUID(), title: "Steuer 2027", notes: "Ordner", dueDate: dueDate)
    }

    func testProposeStoresPendingAndRejectsSecond() async throws {
        let environment = try await makeEnvironment()
        let first = makeProposal()

        XCTAssertTrue(environment.center.propose(first))
        XCTAssertFalse(environment.center.propose(makeProposal()))
        XCTAssertEqual(environment.center.pending, first)
    }

    func testDeclineCreatesNothing() async throws {
        let environment = try await makeEnvironment()
        _ = environment.center.propose(makeProposal())

        let status = environment.center.declinePending()

        XCTAssertNil(environment.center.pending)
        XCTAssertTrue(status.contains("keine Aufgabe"))
        XCTAssertTrue(environment.reminders.createdReminders.isEmpty)
    }

    func testConfirmWithoutPendingExplainsItself() async throws {
        let environment = try await makeEnvironment()

        let status = await environment.center.confirmPending()

        XCTAssertTrue(status.contains("kein Aufgaben-Vorschlag"))
    }

    func testConfirmCreatesReminderAndSyncs() async throws {
        let environment = try await makeEnvironment(authorized: true)
        _ = environment.center.propose(makeProposal(dueDate: dueDate))

        let status = await environment.center.confirmPending()

        XCTAssertNil(environment.center.pending)
        XCTAssertEqual(environment.reminders.createdReminders.count, 1)
        XCTAssertEqual(environment.reminders.createdReminders[0].title, "Steuer 2027")
        XCTAssertEqual(environment.reminders.createdReminders[0].notes, "Ordner")
        XCTAssertEqual(environment.reminders.createdReminders[0].dueDate, dueDate)
        // The new reminder is pulled into the local history right away.
        XCTAssertEqual(environment.reminders.fetchAllCallCount, 1)
        XCTAssertTrue(status.contains("Steuer 2027"))
        XCTAssertTrue(status.contains("angelegt"))
        XCTAssertTrue(status.contains("Freitag, 04.09.2026"))
    }

    func testCreationFailureProducesFactualError() async throws {
        let environment = try await makeEnvironment()
        environment.reminders.createResult = .failure(ReminderServiceError.creationFailed)
        _ = environment.center.propose(makeProposal())

        let status = await environment.center.confirmPending()

        XCTAssertTrue(status.contains("konnte nicht angelegt werden"))
        XCTAssertTrue(environment.reminders.createdReminders.isEmpty)
        XCTAssertEqual(environment.reminders.fetchAllCallCount, 0)
        XCTAssertNil(environment.center.pending)
    }
}
