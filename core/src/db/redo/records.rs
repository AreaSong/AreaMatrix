use std::path::Path;

use rusqlite::{params, OptionalExtension, Row};
use serde::Deserialize;
use serde_json::Value;

use crate::{CoreError, CoreResult, RedoActionRecord, RedoActionStatus};

use super::{
    file_actions, tags, StoredRedoAction, BATCH_ADD_TAGS_KIND, BATCH_CHANGE_CATEGORY_KIND,
    CHANGE_CATEGORY_KIND, MOVE_FILES_KIND, REDO_CLEARED_REASON, RENAME_FILES_KIND,
    TRASH_DELETE_KIND,
};

const REDO_ACTION_LIMIT: i64 = 100;

#[derive(Debug, Deserialize)]
struct RedoSummary {
    added_count: Option<i64>,
    affected_count: Option<i64>,
    affected_file_names: Option<Vec<String>>,
    disabled_reason: Option<String>,
}

pub(super) fn ensure_redo_metadata_ready(connection: &rusqlite::Connection) -> CoreResult<()> {
    for statement in [
        "SELECT token, kind, summary_json, inverse_json, status FROM undo_actions LIMIT 0",
        "SELECT file_id, tag, added_at FROM tags LIMIT 0",
        "SELECT id, path, current_name, category, status FROM files LIMIT 0",
        "SELECT file_id, action, detail_json, occurred_at FROM change_log LIMIT 0",
    ] {
        connection
            .prepare(statement)
            .map(|_| ())
            .map_err(|error| CoreError::db(error.to_string()))?;
    }
    Ok(())
}

pub(super) fn load_redo_actions(
    connection: &rusqlite::Connection,
) -> CoreResult<Vec<StoredRedoAction>> {
    let mut statement = connection
        .prepare(
            "SELECT token, kind, summary_json, inverse_json, status, updated_at
               FROM undo_actions
              WHERE status IN ('executed', 'expired', 'blocked')
              ORDER BY updated_at DESC, token DESC
              LIMIT ?1",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![REDO_ACTION_LIMIT], stored_action_from_row)
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn load_executed_action(
    connection: &rusqlite::Connection,
    action_id: &str,
) -> CoreResult<StoredRedoAction> {
    let action = connection
        .query_row(
            "SELECT token, kind, summary_json, inverse_json, status, updated_at
               FROM undo_actions
              WHERE token = ?1",
            params![action_id],
            stored_action_from_row,
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found(action_id.to_owned()))?;
    match action.status.as_str() {
        "executed" => Ok(action),
        "pending" => Err(CoreError::file_not_found(action_id.to_owned())),
        "expired" | "blocked" => Err(CoreError::expired_action(action_id.to_owned())),
        _ => Err(CoreError::db("invalid redo action status")),
    }
}

pub(super) fn redo_record_from_row(
    repo_path: &Path,
    connection: &rusqlite::Connection,
    row: StoredRedoAction,
) -> CoreResult<RedoActionRecord> {
    let summary = parse_summary(&row.summary_json)?;
    let inverse = parse_inverse_value(&row.inverse_json)?;
    let mut status = status_from_db(&row.status)?;
    if status == RedoActionStatus::Expired
        && summary.disabled_reason.as_deref() == Some(REDO_CLEARED_REASON)
    {
        status = RedoActionStatus::Cleared;
    }
    let disabled_reason = disabled_reason(
        connection, &status, &row.kind, &inverse, &summary, repo_path,
    )?;
    if status == RedoActionStatus::Available && disabled_reason.is_some() {
        status = RedoActionStatus::Blocked;
    }

    Ok(RedoActionRecord {
        action_id: row.token.clone(),
        kind: row.kind.clone(),
        summary: redo_display_summary(&row.kind, &summary),
        affected_count: affected_count(&summary, &inverse),
        affected_file_names: summary.affected_file_names.unwrap_or_default(),
        can_redo: status == RedoActionStatus::Available,
        disabled_reason,
        status,
        source_undo_action_id: row.token,
        created_at: row.updated_at,
        updated_at: row.updated_at,
    })
}

pub(super) fn parse_inverse_value(inverse_json: &str) -> CoreResult<Value> {
    serde_json::from_str(inverse_json).map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn redo_cleared_summary_json(summary_json: &str) -> CoreResult<String> {
    let mut value: Value =
        serde_json::from_str(summary_json).map_err(|error| CoreError::db(error.to_string()))?;
    let Value::Object(ref mut object) = value else {
        return Err(CoreError::db("invalid redo summary"));
    };
    object.insert(
        "disabled_reason".to_owned(),
        Value::String(REDO_CLEARED_REASON.to_owned()),
    );
    serde_json::to_string(&value).map_err(|error| CoreError::internal(error.to_string()))
}

fn stored_action_from_row(row: &Row<'_>) -> rusqlite::Result<StoredRedoAction> {
    Ok(StoredRedoAction {
        token: row.get(0)?,
        kind: row.get(1)?,
        summary_json: row.get(2)?,
        inverse_json: row.get(3)?,
        status: row.get(4)?,
        updated_at: row.get(5)?,
    })
}

fn status_from_db(status: &str) -> CoreResult<RedoActionStatus> {
    match status {
        "executed" => Ok(RedoActionStatus::Available),
        "expired" => Ok(RedoActionStatus::Expired),
        "blocked" => Ok(RedoActionStatus::Blocked),
        _ => Err(CoreError::db("invalid redo action status")),
    }
}

fn parse_summary(summary_json: &str) -> CoreResult<RedoSummary> {
    serde_json::from_str(summary_json).map_err(|error| CoreError::db(error.to_string()))
}

fn redo_display_summary(kind: &str, summary: &RedoSummary) -> String {
    match kind {
        BATCH_ADD_TAGS_KIND => {
            let count = summary.added_count.or(summary.affected_count).unwrap_or(0);
            format!("Redo: add {count} tag relation(s).")
        }
        RENAME_FILES_KIND => "Redo: rename 1 file.".to_owned(),
        MOVE_FILES_KIND => "Redo: move 1 file.".to_owned(),
        CHANGE_CATEGORY_KIND => "Redo: change category for 1 file.".to_owned(),
        BATCH_CHANGE_CATEGORY_KIND => {
            let count = summary.affected_count.unwrap_or(0);
            format!("Redo: change category for {count} file(s).")
        }
        TRASH_DELETE_KIND => redo_trash_delete_summary(summary),
        _ => format!("Redo action: {kind}"),
    }
}

fn redo_trash_delete_summary(summary: &RedoSummary) -> String {
    let count = summary.affected_count.unwrap_or(1);
    if count == 1 {
        "Redo: move 1 file to Trash.".to_owned()
    } else {
        format!("Redo: move {count} files to Trash.")
    }
}

fn affected_count(summary: &RedoSummary, inverse: &Value) -> i64 {
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
        .unwrap_or_else(|| {
            inverse
                .get("items")
                .and_then(Value::as_array)
                .map(|items| items.len() as i64)
                .unwrap_or(0)
        })
}

fn disabled_reason(
    connection: &rusqlite::Connection,
    status: &RedoActionStatus,
    kind: &str,
    inverse: &Value,
    summary: &RedoSummary,
    repo_path: &Path,
) -> CoreResult<Option<String>> {
    if let Some(reason) = summary.disabled_reason.clone() {
        return Ok(Some(reason));
    }
    match status {
        RedoActionStatus::Available if kind == BATCH_ADD_TAGS_KIND => {
            tags::batch_tag_redo_block_reason(connection, inverse)
        }
        RedoActionStatus::Available if file_actions::is_file_action_kind(kind) => {
            file_actions::file_redo_block_reason(connection, repo_path, inverse)
        }
        RedoActionStatus::Available => Ok(Some("Unsupported redo action kind".to_owned())),
        RedoActionStatus::Cleared => Ok(Some(REDO_CLEARED_REASON.to_owned())),
        RedoActionStatus::Blocked => Ok(Some("Redo action is blocked".to_owned())),
        RedoActionStatus::Expired => Ok(Some("Redo action expired".to_owned())),
        RedoActionStatus::Executed => Ok(Some("Already redone".to_owned())),
    }
}
