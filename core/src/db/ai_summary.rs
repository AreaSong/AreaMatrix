//! AreaMatrix-owned AI summary metadata, ownership, CAS and provenance.

use std::{collections::HashSet, path::Path};

use rusqlite::{params, OptionalExtension, TransactionBehavior};
use serde_json::{json, Value};

use crate::{AiContentOwnership, ContentLocale, CoreError, CoreResult};

use super::open_repo_connection;

pub(crate) struct AiSummaryMetadataRow {
    pub(crate) summary_text: String,
}

pub(crate) struct AiSummaryUpsert {
    pub(crate) file_id: i64,
    pub(crate) expected_content_revision: i64,
    pub(crate) confirm_replace_user_owned: bool,
    pub(crate) summary_text: String,
    pub(crate) draft_id: Option<String>,
    pub(crate) route: Option<String>,
    pub(crate) model_name: Option<String>,
    pub(crate) generated_at: Option<i64>,
    pub(crate) used_context_json: String,
    pub(crate) privacy_rule_id: Option<String>,
    pub(crate) call_log_id: Option<i64>,
    pub(crate) ownership: AiContentOwnership,
    pub(crate) operation_id: String,
    pub(crate) content_locale: ContentLocale,
    pub(crate) format_contract_version: i64,
}

pub(crate) struct AiSummarySaveStats {
    pub(crate) saved_at: i64,
    pub(crate) content_revision: i64,
}

pub(crate) struct AiSummaryClearStats {
    pub(crate) cleared: bool,
    pub(crate) cleared_at: i64,
    pub(crate) content_revision: i64,
}

pub(crate) fn load_ai_summary_metadata(
    repo_path: &Path,
    file_id: i64,
) -> CoreResult<Option<AiSummaryMetadataRow>> {
    let connection = open_repo_connection(repo_path)?;
    if !table_exists(&connection, "ai_summaries")? {
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
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_active_file(&tx, record.file_id)?;
    ensure_ai_summary_schema(&tx)?;
    validate_operation_provenance(&tx, &record)?;
    let current_revision = current_revision(&tx, record.file_id)?;
    if current_revision != record.expected_content_revision {
        return Err(CoreError::revision_conflict(
            "ai_summary_content_revision",
            record.expected_content_revision,
            current_revision,
        ));
    }
    let existing_ownership = current_ownership(&tx, record.file_id)?;
    if existing_ownership == Some(AiContentOwnership::UserOwned)
        && (!record.confirm_replace_user_owned || record.ownership == AiContentOwnership::Generated)
    {
        return Err(CoreError::conflict(
            "ai_summary_user_owned_replacement_required",
        ));
    }
    let saved_at = current_timestamp(&tx)?;
    let next_revision = current_revision + 1;
    tx.execute(
        "INSERT INTO ai_summaries (
           file_id, summary_text, draft_id, route, model_name, generated_at,
           used_context_json, privacy_rule_id, call_log_id, edited_by_user, saved_at,
           ownership, content_revision, operation_id, content_locale, format_contract_version
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
         ON CONFLICT(file_id) DO UPDATE SET
           summary_text = excluded.summary_text, draft_id = excluded.draft_id,
           route = excluded.route, model_name = excluded.model_name,
           generated_at = excluded.generated_at, used_context_json = excluded.used_context_json,
           privacy_rule_id = excluded.privacy_rule_id, call_log_id = excluded.call_log_id,
           edited_by_user = excluded.edited_by_user, saved_at = excluded.saved_at,
           ownership = excluded.ownership, content_revision = excluded.content_revision,
           operation_id = excluded.operation_id, content_locale = excluded.content_locale,
           format_contract_version = excluded.format_contract_version",
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
            i64::from(record.ownership == AiContentOwnership::UserOwned),
            saved_at,
            record.ownership.as_str(),
            next_revision,
            record.operation_id,
            record.content_locale.as_str(),
            record.format_contract_version,
        ],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    set_revision(&tx, record.file_id, next_revision, saved_at)?;
    insert_summary_change_log(
        &tx,
        record.file_id,
        saved_at,
        json!({
            "kind": "ai_summary_saved",
            "character_count": record.summary_text.chars().count(),
            "ownership": record.ownership.as_str(),
            "content_revision": next_revision,
            "operation_id": record.operation_id,
            "content_locale": record.content_locale.as_str(),
            "format_contract_version": record.format_contract_version,
            "by": "user",
        }),
    )?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(AiSummarySaveStats {
        saved_at,
        content_revision: next_revision,
    })
}

pub(crate) fn clear_ai_summary_metadata(
    repo_path: &Path,
    file_id: i64,
    expected_content_revision: i64,
) -> CoreResult<AiSummaryClearStats> {
    super::ensure_config_storage_writable(repo_path)?;
    let mut connection = open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_active_file(&tx, file_id)?;
    ensure_ai_summary_schema(&tx)?;
    let current_revision = current_revision(&tx, file_id)?;
    if current_revision != expected_content_revision {
        return Err(CoreError::revision_conflict(
            "ai_summary_content_revision",
            expected_content_revision,
            current_revision,
        ));
    }
    let cleared_at = current_timestamp(&tx)?;
    let deleted = tx
        .execute(
            "DELETE FROM ai_summaries WHERE file_id = ?1",
            params![file_id],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let next_revision = current_revision + 1;
    set_revision(&tx, file_id, next_revision, cleared_at)?;
    insert_summary_change_log(
        &tx,
        file_id,
        cleared_at,
        json!({
            "kind": "ai_summary_cleared",
            "content_revision": next_revision,
            "by": "user",
        }),
    )?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(AiSummaryClearStats {
        cleared: deleted > 0,
        cleared_at,
        content_revision: next_revision,
    })
}

fn ensure_ai_summary_schema(tx: &rusqlite::Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS ai_summaries (
           file_id INTEGER PRIMARY KEY, summary_text TEXT NOT NULL, draft_id TEXT,
           route TEXT CHECK (route IS NULL OR route IN ('local', 'remote')), model_name TEXT,
           generated_at INTEGER, used_context_json TEXT NOT NULL, privacy_rule_id TEXT,
           call_log_id INTEGER, edited_by_user INTEGER NOT NULL DEFAULT 0 CHECK (edited_by_user IN (0, 1)),
           saved_at INTEGER NOT NULL, ownership TEXT NOT NULL CHECK (ownership IN ('generated','user_owned')),
           content_revision INTEGER NOT NULL CHECK (content_revision >= 1), operation_id TEXT,
           content_locale TEXT CHECK (content_locale IS NULL OR content_locale IN ('zh-Hans','en')),
           format_contract_version INTEGER, FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
         );
         CREATE TABLE IF NOT EXISTS ai_summary_revisions (
           file_id INTEGER PRIMARY KEY, content_revision INTEGER NOT NULL CHECK (content_revision >= 0),
           updated_at INTEGER NOT NULL, FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
         );",
    ).map_err(|error| CoreError::db(error.to_string()))?;
    let columns = table_columns(tx, "ai_summaries")?;
    for (name, definition) in [
        ("ownership", "ownership TEXT NOT NULL DEFAULT 'generated'"),
        (
            "content_revision",
            "content_revision INTEGER NOT NULL DEFAULT 1",
        ),
        ("operation_id", "operation_id TEXT"),
        ("content_locale", "content_locale TEXT"),
        ("format_contract_version", "format_contract_version INTEGER"),
    ] {
        if !columns.contains(name) {
            tx.execute(
                &format!("ALTER TABLE ai_summaries ADD COLUMN {definition}"),
                [],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
        }
    }
    tx.execute(
        "UPDATE ai_summaries SET ownership = CASE WHEN edited_by_user = 1 THEN 'user_owned' ELSE 'generated' END
         WHERE ownership IS NULL OR ownership NOT IN ('generated','user_owned')",
        [],
    ).map_err(|error| CoreError::db(error.to_string()))?;
    tx.execute(
        "INSERT OR IGNORE INTO ai_summary_revisions (file_id, content_revision, updated_at)
         SELECT file_id, COALESCE(content_revision, 1), saved_at FROM ai_summaries",
        [],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(())
}

fn validate_operation_provenance(
    tx: &rusqlite::Transaction<'_>,
    record: &AiSummaryUpsert,
) -> CoreResult<()> {
    let row: Option<(String, Option<String>, i64, String, String)> = tx
        .query_row(
            "SELECT operation_code, content_locale, format_contract_version,
                operation_payload_json, status
         FROM recoverable_operations WHERE operation_id = ?1",
            params![record.operation_id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let Some((code, locale, format_version, payload, status)) = row else {
        return Err(CoreError::conflict(
            "ai_summary_operation_provenance_missing",
        ));
    };
    let payload: Value = serde_json::from_str(&payload)
        .map_err(|_| CoreError::db("AI summary operation payload is invalid"))?;
    let payload_file_id = payload.get("file_id").and_then(Value::as_i64);
    if code != "ai_summary_generation"
        || locale.as_deref() != Some(record.content_locale.as_str())
        || format_version != record.format_contract_version
        || payload_file_id != Some(record.file_id)
        || status != "completed"
    {
        return Err(CoreError::conflict(
            "ai_summary_operation_provenance_mismatch",
        ));
    }
    Ok(())
}

fn current_revision(tx: &rusqlite::Transaction<'_>, file_id: i64) -> CoreResult<i64> {
    tx.query_row(
        "SELECT content_revision FROM ai_summary_revisions WHERE file_id = ?1",
        params![file_id],
        |row| row.get(0),
    )
    .optional()
    .map(|value| value.unwrap_or(0))
    .map_err(|error| CoreError::db(error.to_string()))
}

fn current_ownership(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
) -> CoreResult<Option<AiContentOwnership>> {
    let value: Option<String> = tx
        .query_row(
            "SELECT ownership FROM ai_summaries WHERE file_id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    value
        .map(|value| {
            AiContentOwnership::parse(&value)
                .ok_or_else(|| CoreError::db("AI summary ownership is invalid"))
        })
        .transpose()
}

fn set_revision(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    revision: i64,
    updated_at: i64,
) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO ai_summary_revisions (file_id, content_revision, updated_at)
         VALUES (?1, ?2, ?3) ON CONFLICT(file_id) DO UPDATE SET
         content_revision = excluded.content_revision, updated_at = excluded.updated_at",
        params![file_id, revision, updated_at],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn ensure_active_file(tx: &rusqlite::Transaction<'_>, file_id: i64) -> CoreResult<()> {
    tx.query_row(
        "SELECT 1 FROM files WHERE id = ?1 AND status = 'active'",
        params![file_id],
        |_| Ok(()),
    )
    .optional()
    .map_err(|error| CoreError::db(error.to_string()))?
    .ok_or_else(|| CoreError::file_not_found("missing file"))
}

fn insert_summary_change_log(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    occurred_at: i64,
    detail: Value,
) -> CoreResult<()> {
    let detail_json =
        serde_json::to_string(&detail).map_err(|error| CoreError::internal(error.to_string()))?;
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, ?3)",
        params![file_id, detail_json, occurred_at],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn table_exists(connection: &rusqlite::Connection, table: &str) -> CoreResult<bool> {
    connection
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            params![table],
            |_| Ok(true),
        )
        .optional()
        .map(|value| value.unwrap_or(false))
        .map_err(|error| CoreError::db(error.to_string()))
}

fn table_columns(connection: &rusqlite::Connection, table: &str) -> CoreResult<HashSet<String>> {
    let mut statement = connection
        .prepare(&format!("PRAGMA table_info({table})"))
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<HashSet<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn current_timestamp(tx: &rusqlite::Transaction<'_>) -> CoreResult<i64> {
    tx.query_row("SELECT CAST(strftime('%s', 'now') AS INTEGER)", [], |row| {
        row.get(0)
    })
    .map_err(|error| CoreError::db(error.to_string()))
}
