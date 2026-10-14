import Foundation

/// Notification identifiers encode the task binding, so delegate callbacks can
/// attribute delivered/dismissed events without any lookup table.
enum NotificationIdentifier {
    private static let taskPrefix = "task-"
    private static let adhocPrefix = "adhoc-"

    static func forTask(_ taskID: UUID) -> String {
        taskPrefix + taskID.uuidString
    }

    static func adhoc(_ proposalID: UUID) -> String {
        adhocPrefix + proposalID.uuidString
    }

    static func taskID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(taskPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(taskPrefix.count)))
    }
}
