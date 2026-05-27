//! Minimal insert-only AI call log storage used by Stage 3 AI producers.

use std::path::Path;

use rusqlite::params;

use crate::{CoreError, CoreResult};

pub(crate) struct AiCallLogRecord {
    pub(crate) feature: String,
    pub(crate) file_id: Option<i64>,
    pub(crate) route: Option<String>,
    pub(crate) provider: Option<String>,
    pub(crate) model: Option<String>,
    pub(crate) status: String,
    pub(crate) sent_fields_json: String,
    pub(crate) privacy_rule_id: Option<String>,
    pub(crate) result_summary: String,
    pub(crate) error_code: Option<String>,
}

pub(crate) fn insert_ai_call_log_record(
    repo_path: &Path,
    record: AiCallLogRecord,
) -> CoreResult<i64> {
    super::ensure_config_storage_writable(repo_path)?;

    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_ai_call_log_schema(&tx)?;
    tx.execute(
        "INSERT INTO ai_call_log (
            feature, file_id, route, provider, model, status, sent_fields_json,
            privacy_rule_id, result_summary, error_code, occurred_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
        params![
            record.feature,
            record.file_id,
            record.route,
            record.provider,
            record.model,
            record.status,
            record.sent_fields_json,
            record.privacy_rule_id,
            record.result_summary,
            record.error_code,
            current_timestamp(&tx)?,
        ],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    let id = tx.last_insert_rowid();
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(id)
}

fn ensure_ai_call_log_schema(tx: &rusqlite::Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS ai_call_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            feature TEXT NOT NULL,
            file_id INTEGER,
            route TEXT,
            provider TEXT,
            model TEXT,
            status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'skipped', 'unavailable')),
            sent_fields_json TEXT NOT NULL,
            privacy_rule_id TEXT,
            result_summary TEXT NOT NULL,
            error_code TEXT,
            occurred_at INTEGER NOT NULL,
            FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE SET NULL
         );
         CREATE INDEX IF NOT EXISTS idx_ai_call_log_time ON ai_call_log(occurred_at DESC);
         CREATE INDEX IF NOT EXISTS idx_ai_call_log_feature_time
           ON ai_call_log(feature, occurred_at DESC);",
    )
    .map_err(|error| CoreError::db(error.to_string()))
}

fn current_timestamp(tx: &rusqlite::Transaction<'_>) -> CoreResult<i64> {
    tx.query_row("SELECT CAST(strftime('%s', 'now') AS INTEGER)", [], |row| {
        row.get(0)
    })
    .map_err(|error| CoreError::db(error.to_string()))
}
