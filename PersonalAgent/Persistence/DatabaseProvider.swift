import Foundation

/// Shared owner of the app database: opens and migrates it exactly once, then
/// hands out the ready instance to sync and tools.
actor DatabaseProvider {
    private let database: SQLiteDatabase
    private let path: String
    private var isPrepared = false

    init(database: SQLiteDatabase = SQLiteDatabase(), path: String) {
        self.database = database
        self.path = path
    }

    func preparedDatabase() async throws -> SQLiteDatabase {
        if !isPrepared {
            try await database.open(at: path)
            try await database.migrate(SchemaMigrations.all)
            isPrepared = true
        }
        return database
    }
}
