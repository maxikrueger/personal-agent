import Foundation
@testable import PersonalAgent

/// Shared fixtures for the test target. Whole-second dates roundtrip exactly
/// through SQLite REAL columns, so tests can use plain equality.
func makeTask(
    id: UUID = UUID(),
    externalID: String = UUID().uuidString,
    title: String = "Aufgabe",
    notes: String? = nil,
    dueDate: Date? = nil,
    creationDate: Date? = nil,
    completionDate: Date? = nil,
    isCompleted: Bool = false,
    listName: String? = nil,
    recurrence: TaskRecurrence? = nil
) -> PersonalAgent.Task {
    PersonalAgent.Task(
        id: id,
        externalID: externalID,
        title: title,
        notes: notes,
        dueDate: dueDate,
        creationDate: creationDate,
        completionDate: completionDate,
        isCompleted: isCompleted,
        listName: listName,
        recurrence: recurrence
    )
}

func makeTestDatabase() async throws -> SQLiteDatabase {
    let database = SQLiteDatabase()
    try await database.open(at: ":memory:")
    try await database.migrate(SchemaMigrations.all)
    return database
}

func makeEvent(
    taskID: UUID,
    type: TaskEventType,
    timestamp: Date,
    metadata: [String: String] = [:]
) -> TaskEvent {
    TaskEvent(taskID: taskID, type: type, timestamp: timestamp, metadata: metadata)
}

/// Fixed calendar so hour/weekday-based analytics are deterministic in tests.
func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

func makeStoredRecommendation(
    taskID: UUID,
    recommendedTime: Date,
    createdAt: Date,
    confidence: Double = 0.5,
    reasonCodes: [RecommendationReason] = [.currentlyFree],
    id: UUID = UUID()
) -> StoredRecommendation {
    StoredRecommendation(
        id: id,
        taskID: taskID,
        recommendedTime: recommendedTime,
        confidence: confidence,
        reasonCodes: reasonCodes,
        createdAt: createdAt
    )
}

/// Hand-built analysis for recommendation tests (no event history needed).
func makeAnalysis(
    taskID: UUID,
    procrastinationScore: Double = 0,
    postponementCount: Int = 0,
    postponementRate: Double = 0,
    cycleCount: Int = 1,
    completionCount: Int = 0,
    isCurrentlyOverdue: Bool = false,
    recurrencePattern: RecurrencePattern? = nil,
    recurrenceConfidence: Double = 0,
    window: TimeWindow? = nil,
    windowConfidence: Double = 0,
    windowSampleSize: Int = 0
) -> TaskAnalysis {
    TaskAnalysis(
        taskID: taskID,
        statistics: TaskStatistics(
            completionRate: cycleCount > 0 ? Double(completionCount) / Double(cycleCount) : 0,
            postponementCount: postponementCount,
            postponementRate: postponementRate,
            overdueCount: isCurrentlyOverdue ? 1 : 0,
            averageDelay: nil,
            medianDelay: nil,
            recurrenceConfidence: recurrenceConfidence,
            preferredCompletionWindow: window,
            procrastinationScore: procrastinationScore
        ),
        cycleCount: cycleCount,
        completionCount: completionCount,
        consecutivePostponements: 0,
        averagePostponementDelay: nil,
        recurrence: RecurrenceAnalysis(
            pattern: recurrencePattern,
            confidence: recurrenceConfidence,
            sampleSize: completionCount
        ),
        preferredWindow: PreferredWindowAnalysis(
            window: window,
            confidence: windowConfidence,
            sampleSize: windowSampleSize
        ),
        isCurrentlyOverdue: isCurrentlyOverdue
    )
}
