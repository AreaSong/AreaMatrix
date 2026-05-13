use std::path::Path;

use rusqlite::{params, OptionalExtension};
use serde_json::json;

use crate::{CoreError, CoreResult};

use super::open_repo_connection;

pub(crate) fn read_note_content(repo_path: &Path, file_id: i64) -> CoreResult<Option<String>> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT content_md FROM notes WHERE file_id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn upsert_note_and_log(
    repo_path: &Path,
    file_id: i64,
    content_md: &str,
    length_before: i64,
    length_after: i64,
) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_active_file(&tx, file_id)?;

    let occurred_at = chrono::Utc::now().timestamp();
    tx.execute(
        "INSERT INTO notes (file_id, content_md, updated_at)
         VALUES (?1, ?2, ?3)
         ON CONFLICT(file_id) DO UPDATE SET
           content_md = excluded.content_md,
           updated_at = excluded.updated_at",
        params![file_id, content_md, occurred_at],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;

    let detail_json = serde_json::to_string(&json!({
        "length_before": length_before,
        "length_after": length_after,
        "by": "user",
    }))
    .map_err(|error| CoreError::internal(error.to_string()))?;
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'edited_note', ?2, ?3)",
        params![file_id, detail_json, occurred_at],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn ensure_active_file(tx: &rusqlite::Transaction<'_>, file_id: i64) -> CoreResult<()> {
    let exists = tx
        .query_row(
            "SELECT 1 FROM files WHERE id = ?1 AND status = 'active'",
            params![file_id],
            |_| Ok(()),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    exists.ok_or_else(|| CoreError::file_not_found("missing file"))
}
