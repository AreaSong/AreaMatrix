use std::path::Path;

use rusqlite::{params, OptionalExtension, Transaction};
use serde_json::Value;
use uuid::Uuid;

use crate::{CoreError, CoreResult};

use super::open_repo_connection;

mod status;

#[derive(Clone, Debug)]
pub(crate) struct ImportConflictRow {
    pub(crate) conflict_id: String,
    pub(crate) import_session_id: String,
    pub(crate) conflict_type: ImportConflictKind,
    pub(crate) staging_file_id: i64,
    pub(crate) existing_file_id: Option<i64>,
    pub(crate) incoming_path: String,
    pub(crate) target_path: String,
    pub(crate) status: ImportConflictStatus,
    pub(crate) failure_reason: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum ImportConflictKind {
    DuplicateHash,
    SameNameDifferentContent,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum ImportConflictStatus {
    Pending,
    QueuedForPerItem,
    Resolved,
    Failed,
}

pub(crate) struct ImportConflictApplyItem<'a> {
    pub(crate) conflict: &'a ImportConflictRow,
    pub(crate) final_path: Option<&'a str>,
    pub(crate) final_name: Option<&'a str>,
    pub(crate) change_detail: Option<&'a Value>,
    pub(crate) replaced: Option<ImportConflictReplacement<'a>>,
    pub(crate) decision: &'a str,
}

pub(crate) struct ImportConflictReplacement<'a> {
    pub(crate) archived_path: &'a str,
    pub(crate) deleted_detail: &'a Value,
}

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

pub(crate) fn list_import_conflicts_for_session(
    repo_path: &Path,
    import_session_id: &str,
) -> CoreResult<Vec<ImportConflictRow>> {
    ensure_import_conflict_schema(repo_path)?;
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT conflict_id, import_session_id, conflict_type, staging_file_id,
                    existing_file_id, incoming_path, target_path, status, failure_reason
               FROM import_conflicts
              WHERE import_session_id = ?1
              ORDER BY created_at ASC, conflict_id ASC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![import_session_id], status::import_conflict_from_row)
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn get_import_session_status(
    repo_path: &Path,
    import_session_id: &str,
) -> CoreResult<String> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT status FROM import_sessions WHERE import_session_id = ?1",
            params![import_session_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found("missing import session"))
}

pub(crate) fn get_staging_file_snapshot(
    repo_path: &Path,
    file_id: i64,
) -> CoreResult<Option<crate::FileEntry>> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT id, path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path, imported_at, updated_at
               FROM files
              WHERE id = ?1 AND status = 'staging'",
            params![file_id],
            super::file_entry_from_row,
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn resolve_import_conflict_item(
    repo_path: &Path,
    item: ImportConflictApplyItem<'_>,
) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    if let Some(replacement) = item.replaced {
        let existing_id = item
            .conflict
            .existing_file_id
            .ok_or_else(|| CoreError::db("database error"))?;
        soft_delete_existing(
            &tx,
            existing_id,
            replacement.archived_path,
            replacement.deleted_detail,
        )?;
    }
    if let (Some(final_path), Some(final_name), Some(change_detail)) =
        (item.final_path, item.final_name, item.change_detail)
    {
        promote_staging_file(
            &tx,
            item.conflict.staging_file_id,
            final_path,
            final_name,
            change_detail,
        )?;
    }
    status::update_import_conflict_status_in_tx(
        &tx,
        &item.conflict.import_session_id,
        &item.conflict.conflict_id,
        "resolved",
        item.decision,
        None,
    )?;
    status::refresh_import_session_status(&tx, &item.conflict.import_session_id)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn queue_import_conflict_for_per_item(
    repo_path: &Path,
    conflict: &ImportConflictRow,
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    status::update_import_conflict_status(
        &connection,
        &conflict.import_session_id,
        &conflict.conflict_id,
        "queued_for_per_item",
        "ask_per_item",
        None,
    )?;
    status::refresh_import_session_status_with_connection(&connection, &conflict.import_session_id)
}

pub(crate) fn mark_import_conflict_failed(
    repo_path: &Path,
    conflict: &ImportConflictRow,
    decision: &str,
    reason: &str,
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    status::update_import_conflict_status(
        &connection,
        &conflict.import_session_id,
        &conflict.conflict_id,
        "failed",
        decision,
        Some(reason),
    )
}

pub(crate) fn rollback_import_conflict_decision(
    repo_path: &Path,
    conflict: &ImportConflictRow,
    session_status: &str,
) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    rollback_conflict_status(&tx, conflict, session_status)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn rollback_import_conflict_keep_both(
    repo_path: &Path,
    conflict: &ImportConflictRow,
    final_path: &str,
    staging_path: &str,
    staging_name: &str,
    session_status: &str,
) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    rollback_promoted_staging(
        &tx,
        conflict.staging_file_id,
        staging_path,
        final_path,
        staging_name,
    )?;
    rollback_conflict_status(&tx, conflict, session_status)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn rollback_import_conflict_replace(
    repo_path: &Path,
    conflict: &ImportConflictRow,
    final_path: &str,
    archived_path: &str,
    staging_path: &str,
    staging_name: &str,
    session_status: &str,
) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    rollback_promoted_staging(
        &tx,
        conflict.staging_file_id,
        staging_path,
        final_path,
        staging_name,
    )?;
    rollback_replaced_existing(&tx, conflict, archived_path)?;
    rollback_conflict_status(&tx, conflict, session_status)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn preflight_import_conflict_undo_action(repo_path: &Path) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    insert_import_conflict_undo_action_in_tx(&tx, &["preflight".to_owned()])?;
    tx.rollback()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn insert_import_conflict_undo_action(
    repo_path: &Path,
    affected_names: &[String],
) -> CoreResult<String> {
    let connection = open_repo_connection(repo_path)?;
    insert_import_conflict_undo_action_in_tx(&connection, affected_names)
}

fn insert_import_conflict_undo_action_in_tx(
    connection: &rusqlite::Connection,
    affected_names: &[String],
) -> CoreResult<String> {
    let token = format!("undo:import-conflict:{}", Uuid::new_v4());
    let occurred_at = chrono::Utc::now().timestamp();
    let summary = serde_json::json!({
        "kind": "import_conflict_batch",
        "affected_count": affected_names.len(),
        "affected_file_names": affected_names,
        "disabled_reason": "Import conflict batch undo requires manual review",
    });
    let inverse = serde_json::json!({
        "kind": "manual_import_conflict_batch_review",
        "affected_file_names": affected_names,
    });
    connection
        .execute(
            "INSERT INTO undo_actions (
                 token, kind, summary_json, inverse_json, status, created_at, updated_at
             ) VALUES (?1, 'import_conflict_batch', ?2, ?3, 'blocked', ?4, ?4)",
            params![
                token,
                serialize_json(&summary)?,
                serialize_json(&inverse)?,
                occurred_at,
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(token)
}

fn soft_delete_existing(
    tx: &Transaction<'_>,
    existing_id: i64,
    archived_path: &str,
    detail: &Value,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
                SET path = ?2,
                    deleted_at = strftime('%s', 'now'),
                    updated_at = strftime('%s', 'now'),
                    status = 'deleted'
              WHERE id = ?1 AND status = 'active'",
            params![existing_id, archived_path],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    insert_change(tx, existing_id, "deleted", detail)
}

fn promote_staging_file(
    tx: &Transaction<'_>,
    file_id: i64,
    final_path: &str,
    final_name: &str,
    detail: &Value,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
                SET path = ?2,
                    current_name = ?3,
                    updated_at = strftime('%s', 'now'),
                    status = 'active'
              WHERE id = ?1 AND status = 'staging'",
            params![file_id, final_path, final_name],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    insert_change(tx, file_id, "imported", detail)
}

fn insert_change(
    tx: &Transaction<'_>,
    file_id: i64,
    action: &str,
    detail: &Value,
) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, ?2, ?3, strftime('%s', 'now'))",
        params![file_id, action, serialize_json(detail)?],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn rollback_conflict_status(
    tx: &Transaction<'_>,
    conflict: &ImportConflictRow,
    session_status: &str,
) -> CoreResult<()> {
    tx.execute(
        "UPDATE import_conflicts
            SET status = 'pending',
                decision = NULL,
                failure_reason = NULL,
                updated_at = strftime('%s', 'now')
          WHERE import_session_id = ?1 AND conflict_id = ?2",
        params![conflict.import_session_id, conflict.conflict_id],
    )
    .map_err(|error| CoreError::db(error.to_string()))
    .and_then(|changed| {
        if changed == 1 {
            Ok(())
        } else {
            Err(CoreError::db("database error"))
        }
    })?;
    let changed = tx
        .execute(
            "UPDATE import_sessions
            SET status = ?2,
                updated_at = strftime('%s', 'now')
          WHERE import_session_id = ?1",
            params![conflict.import_session_id, session_status],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::db("database error"))
    }
}

fn rollback_promoted_staging(
    tx: &Transaction<'_>,
    file_id: i64,
    staging_path: &str,
    final_path: &str,
    staging_name: &str,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
                SET path = ?2,
                    current_name = ?4,
                    updated_at = strftime('%s', 'now'),
                    status = 'staging'
              WHERE id = ?1 AND status = 'active' AND path = ?3",
            params![file_id, staging_path, final_path, staging_name],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    tx.execute(
        "DELETE FROM change_log WHERE file_id = ?1 AND action = 'imported'",
        params![file_id],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn rollback_replaced_existing(
    tx: &Transaction<'_>,
    conflict: &ImportConflictRow,
    archived_path: &str,
) -> CoreResult<()> {
    let Some(existing_id) = conflict.existing_file_id else {
        return Err(CoreError::db("database error"));
    };
    let changed = tx
        .execute(
            "UPDATE files
                SET path = ?2,
                    deleted_at = NULL,
                    updated_at = strftime('%s', 'now'),
                    status = 'active'
              WHERE id = ?1 AND status = 'deleted' AND path = ?3",
            params![existing_id, conflict.target_path, archived_path],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    tx.execute(
        "DELETE FROM change_log WHERE file_id = ?1 AND action = 'deleted'",
        params![existing_id],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn serialize_json(value: &Value) -> CoreResult<String> {
    serde_json::to_string(value).map_err(|error| CoreError::internal(error.to_string()))
}
