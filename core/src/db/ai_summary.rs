//! AreaMatrix-owned AI summary metadata storage.

use std::path::Path;

use rusqlite::{params, OptionalExtension};
use serde_json::json;

use crate::{CoreError, CoreResult};

use super::open_repo_connection;

pub(crate) struct AiSummaryMetadataRow {
    pub(crate) summary_text: String,
}

pub(crate) struct AiSummaryUpsert {
    pub(crate) file_id: i64,
    pub(crate) summary_text: String,
    pub(crate) draft_id: Option<String>,
    pub(crate) route: Option<String>,
    pub(crate) model_name: Option<String>,
    pub(crate) generated_at: Option<i64>,
    pub(crate) used_context_json: String,
    pub(crate) privacy_rule_id: Option<String>,
    pub(crate) call_log_id: Option<i64>,
    pub(crate) edited_by_user: bool,
}

pub(crate) struct AiSummarySaveStats {
    pub(crate) saved_at: i64,
}

pub(crate) struct AiSummaryClearStats {
    pub(crate) cleared: bool,
    pub(crate) cleared_at: i64,
}

pub(crate) fn load_ai_summary_metadata(
    repo_path: &Path,
    file_id: i64,
) -> CoreResult<Option<AiSummaryMetadataRow>> {
    let connection = open_repo_connection(repo_path)?;
    if !table_exists(&connection)? {
        return Ok(None);
    }
    connection
        .query_row(
            "SELECT summary_text FROM ai_summaries WHERE file_id = ?1",
            params![file_id],
            |row| {
                Ok(AiSummaryMetadataRow {
                    summary_text: row.get(0)?,
                })
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn upsert_ai_summary_metadata(
    repo_path: &Path,
    record: AiSummaryUpsert,
) -> CoreResult<AiSummarySaveStats> {
    super::ensure_config_storage_writable(repo_path)?;

    let mut connection = open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_active_file(&tx, record.file_id)?;
    ensure_ai_summary_schema(&tx)?;
    let saved_at = current_timestamp(&tx)?;

    tx.execute(
        "INSERT INTO ai_summaries (
            file_id, summary_text, draft_id, route, model_name, generated_at,
            used_context_json, privacy_rule_id, call_log_id, edited_by_user, saved_at
         ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11
         )
         ON CONFLICT(file_id) DO UPDATE SET
            summary_text = excluded.summary_text,
            draft_id = excluded.draft_id,
            route = excluded.route,
            model_name = excluded.model_name,
            generated_at = excluded.generated_at,
            used_context_json = excluded.used_context_json,
            privacy_rule_id = excluded.privacy_rule_id,
            call_log_id = excluded.call_log_id,
            edited_by_user = excluded.edited_by_user,
            saved_at = excluded.saved_at",
        params![
            record.file_id,
            record.summary_text,
            record.draft_id,
            record.route,
            record.model_name,
            record.generated_at,
            record.used_context_json,
            record.privacy_rule_id,
            record.call_log_id,
            bool_to_db(record.edited_by_user),
            saved_at,
        ],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;

    insert_summary_change_log(
        &tx,
        record.file_id,
        saved_at,
        json!({
            "kind": "ai_summary_saved",
            "character_count": record.summary_text.chars().count(),
            "route": record.route,
            "model_name": record.model_name,
            "generated_at": record.generated_at,
            "privacy_rule_id": record.privacy_rule_id,
            "call_log_id": record.call_log_id,
            "edited_by_user": record.edited_by_user,
            "by": "user",
        }),
    )?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(AiSummarySaveStats { saved_at })
}

pub(crate) fn clear_ai_summary_metadata(
    repo_path: &Path,
    file_id: i64,
) -> CoreResult<AiSummaryClearStats> {
    super::ensure_config_storage_writable(repo_path)?;

    let mut connection = open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_active_file(&tx, file_id)?;
    ensure_ai_summary_schema(&tx)?;
    let cleared_at = current_timestamp(&tx)?;
    let deleted = tx
        .execute(
            "DELETE FROM ai_summaries WHERE file_id = ?1",
            params![file_id],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if deleted > 0 {
        insert_summary_change_log(
            &tx,
            file_id,
            cleared_at,
            json!({
                "kind": "ai_summary_cleared",
                "by": "user",
            }),
        )?;
    }
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(AiSummaryClearStats {
        cleared: deleted > 0,
        cleared_at,
    })
}

fn ensure_ai_summary_schema(tx: &rusqlite::Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS ai_summaries (
            file_id INTEGER PRIMARY KEY,
            summary_text TEXT NOT NULL,
            draft_id TEXT,
            route TEXT CHECK (route IS NULL OR route IN ('local', 'remote')),
            model_name TEXT,
            generated_at INTEGER,
            used_context_json TEXT NOT NULL,
            privacy_rule_id TEXT,
            call_log_id INTEGER,
            edited_by_user INTEGER NOT NULL DEFAULT 0 CHECK (edited_by_user IN (0, 1)),
            saved_at INTEGER NOT NULL,
            FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
         );",
    )
    .map_err(|error| CoreError::db(error.to_string()))
}

fn table_exists(connection: &rusqlite::Connection) -> CoreResult<bool> {
    connection
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'ai_summaries'",
            [],
            |_| Ok(true),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
        .map(|value| value.unwrap_or(false))
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

fn insert_summary_change_log(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    occurred_at: i64,
    detail: serde_json::Value,
) -> CoreResult<()> {
    let detail_json =
        serde_json::to_string(&detail).map_err(|error| CoreError::internal(error.to_string()))?;
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, ?3)",
        params![file_id, detail_json, occurred_at],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(())
}

fn current_timestamp(tx: &rusqlite::Transaction<'_>) -> CoreResult<i64> {
    tx.query_row("SELECT CAST(strftime('%s', 'now') AS INTEGER)", [], |row| {
        row.get(0)
    })
    .map_err(|error| CoreError::db(error.to_string()))
}

fn bool_to_db(value: bool) -> i64 {
    if value {
        1
    } else {
        0
    }
}
