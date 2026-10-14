import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}

struct DatabaseError: Error, Equatable, LocalizedError {
    let message: String

    var errorDescription: String? {
        "Datenbankfehler: \(message)"
    }
}

/// Thin wrapper around the system SQLite3 C API (no
/// third-party dependencies). All access is serialized through this actor so
/// queries never run on the main actor.
actor SQLiteDatabase {
    private var handle: OpaquePointer?

    var isOpen: Bool {
        handle != nil
    }

    func open(at path: String) throws {
        guard handle == nil else { return }
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open failed"
            sqlite3_close(db)
            throw DatabaseError(message: message)
        }
        handle = db
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    func close() {
        if let handle {
            sqlite3_close_v2(handle)
        }
        handle = nil
    }

    /// Applies pending migrations in ascending version order, each in its own
    /// transaction, tracked via `PRAGMA user_version`.
    func migrate(_ migrations: [SchemaMigration]) throws {
        let currentVersion = try schemaVersion()
        let pending = migrations
            .filter { $0.version > currentVersion }
            .sorted { $0.version < $1.version }
        for migration in pending {
            try execute("BEGIN")
            do {
                for statement in migration.statements {
                    try execute(statement)
                }
                try execute("PRAGMA user_version = \(migration.version)")
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    func schemaVersion() throws -> Int {
        guard let row = try query("PRAGMA user_version").first,
              case .integer(let version) = row[0] else {
            throw DatabaseError(message: "PRAGMA user_version returned no value")
        }
        return Int(version)
    }

    func beginTransaction() throws {
        try execute("BEGIN IMMEDIATE")
    }

    func commitTransaction() throws {
        try execute("COMMIT")
    }

    func rollbackTransaction() {
        try? execute("ROLLBACK")
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        _ = try run(sql, bindings: bindings)
    }

    func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        try run(sql, bindings: bindings)
    }

    private func run(_ sql: String, bindings: [SQLiteValue]) throws -> [[SQLiteValue]] {
        guard let handle else {
            throw DatabaseError(message: "database is not open")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError(message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, position)
            case .integer(let integer):
                result = sqlite3_bind_int64(statement, position, integer)
            case .real(let real):
                result = sqlite3_bind_double(statement, position, real)
            case .text(let text):
                result = sqlite3_bind_text(statement, position, text, -1, sqliteTransient)
            }
            guard result == SQLITE_OK else {
                throw DatabaseError(message: String(cString: sqlite3_errmsg(handle)))
            }
        }

        var rows: [[SQLiteValue]] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                break
            }
            guard stepResult == SQLITE_ROW else {
                throw DatabaseError(message: String(cString: sqlite3_errmsg(handle)))
            }
            let columnCount = sqlite3_column_count(statement)
            var row: [SQLiteValue] = []
            row.reserveCapacity(Int(columnCount))
            for column in 0..<columnCount {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER:
                    row.append(.integer(sqlite3_column_int64(statement, column)))
                case SQLITE_FLOAT:
                    row.append(.real(sqlite3_column_double(statement, column)))
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, column) {
                        row.append(.text(String(cString: text)))
                    } else {
                        row.append(.null)
                    }
                default:
                    row.append(.null)
                }
            }
            rows.append(row)
        }
        return rows
    }
}
