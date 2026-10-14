import Foundation
@testable import PersonalAgent

final class FakeCalendarService: CalendarService, @unchecked Sendable {
    var accessResult: Result<Void, Error> = .success(())
    var eventsResult: Result<[CalendarEvent], Error> = .success([])
    var freeTimeResult: Result<[DateInterval], Error> = .success([])
    /// When non-empty, each findFreeTime call pops the next entry instead of
    /// using `freeTimeResult` (for tools that query multiple day windows).
    var freeTimeResultsQueue: [[DateInterval]] = []
    private(set) var recordedQueries: [(from: Date, to: Date, duration: TimeInterval)] = []

    func requestAccess() async throws {
        try accessResult.get()
    }

    func fetchEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        try accessResult.get()
        return try eventsResult.get()
    }

    func findFreeTime(from: Date, to: Date, duration: TimeInterval) async throws -> [DateInterval] {
        recordedQueries.append((from, to, duration))
        try accessResult.get()
        if !freeTimeResultsQueue.isEmpty {
            return freeTimeResultsQueue.removeFirst()
        }
        return try freeTimeResult.get()
    }
}
