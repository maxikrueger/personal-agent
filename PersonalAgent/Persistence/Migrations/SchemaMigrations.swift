struct SchemaMigration: Sendable {
    let version: Int
    let statements: [String]
}

/// Append-only list: never edit a shipped migration, add a new version instead,
/// so an installed database is never silently modified.
enum SchemaMigrations {
    static let all: [SchemaMigration] = [
        SchemaMigration(
            version: 1,
            statements: [
                // id (PRIMARY KEY) and external_id (UNIQUE) are indexed implicitly.
                """
                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY,
                    external_id TEXT NOT NULL UNIQUE,
                    title TEXT NOT NULL,
                    notes TEXT,
                    due_date REAL,
                    creation_date REAL,
                    completion_date REAL,
                    is_completed INTEGER NOT NULL DEFAULT 0,
                    list_name TEXT,
                    updated_at REAL NOT NULL
                )
                """,
                """
                CREATE TABLE IF NOT EXISTS task_events (
                    id TEXT PRIMARY KEY,
                    task_id TEXT NOT NULL REFERENCES tasks(id),
                    event_type TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    metadata_json TEXT NOT NULL DEFAULT '{}'
                )
                """,
                "CREATE INDEX IF NOT EXISTS idx_task_events_task_id ON task_events(task_id)",
                "CREATE INDEX IF NOT EXISTS idx_task_events_timestamp ON task_events(timestamp)",
                "CREATE INDEX IF NOT EXISTS idx_task_events_event_type ON task_events(event_type)",
            ]
        ),
        SchemaMigration(
            version: 2,
            statements: [
                """
                CREATE TABLE IF NOT EXISTS recommendations (
                    id TEXT PRIMARY KEY,
                    task_id TEXT NOT NULL REFERENCES tasks(id),
                    recommended_time REAL NOT NULL,
                    confidence REAL NOT NULL,
                    reason_codes_json TEXT NOT NULL DEFAULT '[]',
                    created_at REAL NOT NULL
                )
                """,
                "CREATE INDEX IF NOT EXISTS idx_recommendations_task_id ON recommendations(task_id)",
                "CREATE INDEX IF NOT EXISTS idx_recommendations_created_at ON recommendations(created_at)",
                // One outcome per type and recommendation keeps outcome
                // derivation idempotent at the database level.
                """
                CREATE TABLE IF NOT EXISTS recommendation_outcomes (
                    id TEXT PRIMARY KEY,
                    recommendation_id TEXT NOT NULL REFERENCES recommendations(id),
                    outcome_type TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    UNIQUE(recommendation_id, outcome_type)
                )
                """,
                "CREATE INDEX IF NOT EXISTS idx_recommendation_outcomes_recommendation_id ON recommendation_outcomes(recommendation_id)",
            ]
        ),
    ]
}
