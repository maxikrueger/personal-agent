import Foundation

struct PostponementAnalysis: Equatable, Sendable {
    let postponementCount: Int
    /// Of all "resolving" moves (postponements + completions), the share that
    /// were postponements — bounded 0…1. 0 when there were neither.
    let postponementRate: Double
    /// Mean of (new due date − old due date) over postponements carrying both dates.
    let averagePostponementDelay: TimeInterval?
    /// Postponements since the most recent completion (all, if never completed).
    let consecutivePostponements: Int
}

enum PostponementAnalyzer {
    static func analyze(events: [TaskEvent], completionCount: Int) -> PostponementAnalysis {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        let postponements = sorted.filter { $0.type == .postponed }
        let postponementCount = postponements.count

        let moves = postponementCount + completionCount
        let postponementRate = moves > 0 ? Double(postponementCount) / Double(moves) : 0

        let shifts = postponements.compactMap { event -> TimeInterval? in
            guard let old = parse(event.metadata["oldDueDate"]),
                  let new = parse(event.metadata["newDueDate"]) else { return nil }
            return new.timeIntervalSince(old)
        }

        let lastCompletion = sorted.last(where: { $0.type == .completed })?.timestamp
        let consecutive = postponements.filter { event in
            guard let lastCompletion else { return true }
            return event.timestamp > lastCompletion
        }.count

        return PostponementAnalysis(
            postponementCount: postponementCount,
            postponementRate: postponementRate,
            averagePostponementDelay: CompletionAnalyzer.average(of: shifts),
            consecutivePostponements: consecutive
        )
    }

    private static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return try? Date(iso, strategy: Date.ISO8601FormatStyle())
    }
}
