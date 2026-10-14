import XCTest
@testable import PersonalAgent

final class AgentContextTests: XCTestCase {
    private let calendar = utcCalendar()
    /// Thursday 2026-09-03, 14:05 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 14, minute: 5))!
    }

    // MARK: - Pure composition

    func testOpenCountExcludesCompletedTasks() {
        let context = AgentContextComposer.context(
            tasks: [
                makeTask(title: "Offen A"),
                makeTask(title: "Offen B"),
                makeTask(title: "Fertig", completionDate: now, isCompleted: true),
            ],
            now: now
        )

        XCTAssertEqual(context.openTaskCount, 2)
    }

    func testOverdueTitlesSortedByDueDateAndCapped() {
        var tasks: [PersonalAgent.Task] = [
            makeTask(title: "Später überfällig", dueDate: now.addingTimeInterval(-3600)),
            makeTask(title: "Früher überfällig", dueDate: now.addingTimeInterval(-7200)),
            makeTask(title: "Zukunft", dueDate: now.addingTimeInterval(3600)),
            makeTask(title: "Ohne Datum"),
            makeTask(title: "Erledigt überfällig", dueDate: now.addingTimeInterval(-9999), completionDate: now, isCompleted: true),
        ]
        tasks.append(contentsOf: (1...4).map { index in
            makeTask(title: "Alt \(index)", dueDate: now.addingTimeInterval(Double(-index) * 86_400))
        })

        let context = AgentContextComposer.context(tasks: tasks, now: now)

        XCTAssertEqual(context.overdueTitles.count, AgentContextComposer.maxOverdueTitles)
        XCTAssertEqual(context.overdueTitles, ["Alt 4", "Alt 3", "Alt 2"])
    }

    func testPromptPrefixContainsDateTimeAndTasks() {
        let context = AgentContextComposer.context(
            tasks: [
                makeTask(title: "Steuer", dueDate: now.addingTimeInterval(-3600)),
                makeTask(title: "Offen"),
            ],
            now: now
        )

        let prefix = AgentContextComposer.promptPrefix(for: context, calendar: calendar)

        XCTAssertTrue(prefix.hasPrefix("[Kontext:"))
        XCTAssertTrue(prefix.contains("Donnerstag, 03.09.2026"))
        XCTAssertTrue(prefix.contains("14:05 Uhr"))
        XCTAssertTrue(prefix.contains("Offene Aufgaben: 2"))
        XCTAssertTrue(prefix.contains("überfällig: Steuer"))
        XCTAssertTrue(prefix.hasSuffix("]"))
    }

    func testPromptPrefixWithoutOverdueOmitsClause() {
        let context = AgentContextComposer.context(tasks: [], now: now)

        let prefix = AgentContextComposer.promptPrefix(for: context, calendar: calendar)

        XCTAssertTrue(prefix.contains("Offene Aufgaben: 0"))
        XCTAssertFalse(prefix.contains("überfällig"))
    }

    // MARK: - IO shell

    func testBuilderReadsStoredTasks() async throws {
        let database = try await makeTestDatabase()
        let provider = DatabaseProvider(database: database, path: ":memory:")
        let repository = TaskRepository(database: database)
        try await repository.upsert(makeTask(title: "Offen"), updatedAt: now)
        try await repository.upsert(
            makeTask(title: "Überfällig", dueDate: now.addingTimeInterval(-3600)),
            updatedAt: now
        )
        let fixedNow = now
        let builder = AgentContextBuilder(
            databaseProvider: provider,
            calendar: calendar,
            now: { fixedNow }
        )

        let context = await builder.buildContext()

        XCTAssertEqual(context.openTaskCount, 2)
        XCTAssertEqual(context.overdueTitles, ["Überfällig"])
        XCTAssertEqual(context.now, now)
    }

    func testBuilderDegradesToDateOnlyContextOnFailure() async {
        let provider = DatabaseProvider(path: "/nonexistent-personalagent-dir/context.sqlite")
        let fixedNow = now
        let builder = AgentContextBuilder(
            databaseProvider: provider,
            calendar: calendar,
            now: { fixedNow }
        )

        let prefix = await builder.promptPrefix()

        XCTAssertTrue(prefix.contains("Donnerstag, 03.09.2026"))
        XCTAssertTrue(prefix.contains("Offene Aufgaben: 0"))
    }

    // MARK: - Echoed context block

    func testEchoedContextBlockIsRemovedFromAnswer() {
        let answer = "[Kontext: Heute ist Mittwoch, 14.10.2026, 15:47 Uhr. Offene Aufgaben: 12.]\n\nBitte bestätige den Vorschlag."

        XCTAssertEqual(AgentContextComposer.strippingEchoedContext(from: answer), "Bitte bestätige den Vorschlag.")
    }

    func testAnswerWithoutContextBlockIsUnchanged() {
        let answer = "Du hast 3 offene Aufgaben [siehe Liste]."

        XCTAssertEqual(AgentContextComposer.strippingEchoedContext(from: answer), answer)
    }
}
