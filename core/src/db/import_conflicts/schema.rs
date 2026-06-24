use std::path::Path;

use crate::{CoreError, CoreResult};

use super::super::open_repo_connection;

pub(crate) fn ensure_import_conflict_schema(repo_path: &Path) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS import_sessions (
               import_session_id TEXT PRIMARY KEY,
               status TEXT NOT NULL DEFAULT 'pending' CHECK (
                 status IN ('pending', 'partially_resolved', 'resolved')
               ),
               created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
               updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
             );
             CREATE TABLE IF NOT EXISTS import_conflicts (
               conflict_id TEXT PRIMARY KEY,
               import_session_id TEXT NOT NULL,
               conflict_type TEXT NOT NULL CHECK (
                 conflict_type IN ('duplicate_hash', 'same_name_different_content')
               ),
               staging_file_id INTEGER NOT NULL,
               existing_file_id INTEGER,
               incoming_path TEXT NOT NULL,
               target_path TEXT NOT NULL,
               status TEXT NOT NULL DEFAULT 'pending' CHECK (
                 status IN ('pending', 'queued_for_per_item', 'resolved', 'failed')
               ),
               decision TEXT,
               failure_reason TEXT,
               created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
               updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
               FOREIGN KEY (import_session_id) REFERENCES import_sessions(import_session_id)
                 ON DELETE CASCADE,
               FOREIGN KEY (staging_file_id) REFERENCES files(id) ON DELETE CASCADE,
               FOREIGN KEY (existing_file_id) REFERENCES files(id) ON DELETE SET NULL
             );
             CREATE INDEX IF NOT EXISTS idx_import_conflicts_session_status
               ON import_conflicts(import_session_id, status, conflict_type);",
        )
        .map_err(|error| CoreError::db(error.to_string()))
}
