use std::path::Path;

use rusqlite::{params, OptionalExtension, Row};
use serde::Deserialize;
use serde_json::Value;

use crate::{CoreError, CoreResult, UndoActionRecord, UndoActionStatus};

use super::{
    file_actions, BATCH_ADD_TAGS_KIND, BATCH_CHANGE_CATEGORY_KIND, CHANGE_CATEGORY_KIND,
    MOVE_FILES_KIND, RENAME_FILES_KIND, TRASH_DELETE_KIND, UNDO_ACTION_LIMIT,
};

#[derive(Debug)]
pub(super) struct StoredUndoAction {
    pub(super) token: String,
    pub(super) kind: String,
    pub(super) inverse_json: String,
}

#[derive(Debug)]
struct StoredUndoActionRow {
    token: String,
    kind: String,
    summary_json: String,
    inverse_json: String,
    status: String,
    created_at: i64,
    updated_at: i64,
}

#[derive(Debug, Deserialize)]
struct UndoSummary {
    added_count: Option<i64>,
    affected_count: Option<i64>,
    affected_file_names: Option<Vec<String>>,
    disabled_reason: Option<String>,
}

pub(super) fn ensure_undo_metadata_ready(connection: &rusqlite::Connection) -> CoreResult<()> {
    for statement in [
        "SELECT token, kind, summary_json, inverse_json, status FROM undo_actions LIMIT 0",
        "SELECT file_id, tag, added_at FROM tags LIMIT 0",
        "SELECT id, current_name, status FROM files LIMIT 0",
        "SELECT file_id, action, detail_json, occurred_at FROM change_log LIMIT 0",
    ] {
        connection
            .prepare(statement)
            .map(|_| ())
            .map_err(|error| CoreError::db(error.to_string()))?;
    }
    Ok(())
}

pub(super) fn load_undo_actions(
    repo_path: &Path,
    connection: &rusqlite::Connection,
) -> CoreResult<Vec<UndoActionRecord>> {
    let mut statement = connection
        .prepare(
            "SELECT token, kind, summary_json, inverse_json, status, created_at, updated_at
               FROM undo_actions
              ORDER BY created_at DESC, token DESC
              LIMIT ?1",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![UNDO_ACTION_LIMIT], stored_action_from_row)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.into_iter()
        .map(|row| undo_record_from_row(repo_path, connection, row))
        .collect()
}

pub(super) fn load_pending_action(
    connection: &rusqlite::Connection,
    action_id: &str,
) -> CoreResult<StoredUndoAction> {
    connection
        .query_row(
            "SELECT token, kind, inverse_json
               FROM undo_actions
              WHERE token = ?1 AND status = 'pending'",
            params![action_id],
            |row| {
                Ok(StoredUndoAction {
                    token: row.get(0)?,
                    kind: row.get(1)?,
                    inverse_json: row.get(2)?,
                })
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found(action_id.to_owned()))
}

fn stored_action_from_row(row: &Row<'_>) -> rusqlite::Result<StoredUndoActionRow> {
    Ok(StoredUndoActionRow {
        token: row.get(0)?,
        kind: row.get(1)?,
        summary_json: row.get(2)?,
        inverse_json: row.get(3)?,
        status: row.get(4)?,
        created_at: row.get(5)?,
        updated_at: row.get(6)?,
    })
}

fn undo_record_from_row(
    repo_path: &Path,
    connection: &rusqlite::Connection,
    row: StoredUndoActionRow,
) -> CoreResult<UndoActionRecord> {
    let status = status_from_db(&row.status)?;
    let summary = parse_summary(&row.summary_json)?;
    let inverse = parse_inverse_value(&row.inverse_json)?;
    let display_summary = display_summary(&row.kind, &summary);
    let affected_count = affected_count(&summary, &inverse);
    let disabled_reason = disabled_reason(
        connection,
        &status,
        &row.kind,
        &inverse,
        summary.disabled_reason.clone(),
        repo_path,
    )?;
    let effective_status = if status == UndoActionStatus::Pending && disabled_reason.is_some() {
        UndoActionStatus::Blocked
    } else {
        status
    };

    Ok(UndoActionRecord {
        action_id: row.token,
        kind: row.kind.clone(),
        summary: display_summary,
        affected_count,
        affected_file_names: summary.affected_file_names.unwrap_or_default(),
        can_undo: effective_status == UndoActionStatus::Pending,
        disabled_reason,
        status: effective_status,
        created_at: row.created_at,
        updated_at: row.updated_at,
    })
}

fn status_from_db(status: &str) -> CoreResult<UndoActionStatus> {
    match status {
        "pending" => Ok(UndoActionStatus::Pending),
        "executed" => Ok(UndoActionStatus::Executed),
        "expired" => Ok(UndoActionStatus::Expired),
        "blocked" => Ok(UndoActionStatus::Blocked),
        _ => Err(CoreError::db("invalid undo action status")),
    }
}

fn parse_summary(summary_json: &str) -> CoreResult<UndoSummary> {
    serde_json::from_str(summary_json).map_err(|error| CoreError::db(error.to_string()))
}

fn parse_inverse_value(inverse_json: &str) -> CoreResult<Value> {
    serde_json::from_str(inverse_json).map_err(|error| CoreError::db(error.to_string()))
}

fn display_summary(kind: &str, summary: &UndoSummary) -> String {
    match kind {
        BATCH_ADD_TAGS_KIND => {
            let count = summary.added_count.or(summary.affected_count).unwrap_or(0);
            format!("Added tags to {count} relation(s).")
        }
        RENAME_FILES_KIND => "Renamed 1 file.".to_owned(),
        MOVE_FILES_KIND => "Moved 1 file.".to_owned(),
        CHANGE_CATEGORY_KIND => "Changed category for 1 file.".to_owned(),
        BATCH_CHANGE_CATEGORY_KIND => {
            let count = summary.affected_count.unwrap_or(0);
            format!("Changed category for {count} file(s).")
        }
        TRASH_DELETE_KIND => trash_delete_summary(summary),
        "icloud_conflict_resolution" => "Resolved 1 iCloud conflict.".to_owned(),
        _ => format!("Undo action: {kind}"),
    }
}

fn trash_delete_summary(summary: &UndoSummary) -> String {
    let count = summary.affected_count.unwrap_or(1);
    if count == 1 {
        "Moved 1 file to Trash.".to_owned()
    } else {
        format!("Moved {count} files to Trash.")
    }
}

fn affected_count(summary: &UndoSummary, inverse: &Value) -> i64 {
    summary
        .added_count
        .or(summary.affected_count)
        .unwrap_or_else(|| inverse_relation_count(inverse))
}

fn inverse_relation_count(inverse: &Value) -> i64 {
    inverse
        .get("relations")
        .and_then(Value::as_array)
        .map(|relations| relations.len() as i64)
        .unwrap_or(0)
}

fn disabled_reason(
    connection: &rusqlite::Connection,
    status: &UndoActionStatus,
    kind: &str,
    inverse: &Value,
    stored_reason: Option<String>,
    repo_path: &Path,
) -> CoreResult<Option<String>> {
    if let Some(reason) = stored_reason {
        return Ok(Some(reason));
    }
    let reason = match status {
        UndoActionStatus::Pending if kind == BATCH_ADD_TAGS_KIND => {
            super::tags::pending_batch_tag_block_reason(connection, inverse)?
        }
        UndoActionStatus::Pending if file_actions::is_file_action_kind(kind) => {
            file_actions::pending_file_block_reason(connection, repo_path, inverse)?
        }
        UndoActionStatus::Pending => Some("Unsupported undo action kind".to_owned()),
        UndoActionStatus::Executed => Some("Already undone".to_owned()),
        UndoActionStatus::Expired => Some("Undo action expired".to_owned()),
        UndoActionStatus::Blocked => Some("Undo action is blocked".to_owned()),
    };
    Ok(reason)
}
