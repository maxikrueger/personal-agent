import Foundation

/// Shared conversions between domain values and SQLite column values.
enum SQLiteMapping {
    static func optionalText(_ value: String?) -> SQLiteValue {
        value.map { .text($0) } ?? .null
    }

    static func optionalDate(_ value: Date?) -> SQLiteValue {
        value.map { .real($0.timeIntervalSince1970) } ?? .null
    }

    static func text(_ value: SQLiteValue) -> String? {
        if case .text(let string) = value {
            return string
        }
        return nil
    }

    static func date(_ value: SQLiteValue) -> Date? {
        if case .real(let interval) = value {
            return Date(timeIntervalSince1970: interval)
        }
        return nil
    }
}
