import Foundation

/// Resolves a model-provided task title against the stored tasks — the 
/// validation step shared by all title-addressed tools.
enum TaskTitleResolver {
    /// Exact (case-insensitive) title matches win; otherwise substring matches.
    static func matches(for query: String, in tasks: [Task]) -> [Task] {
        let exact = tasks.filter { $0.title.caseInsensitiveCompare(query) == .orderedSame }
        if !exact.isEmpty {
            return exact
        }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}
