use std::path::Path;

use rusqlite::{params, OptionalExtension};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{CoreError, CoreResult};

use super::file_actions::{
    CHANGE_CATEGORY_KIND, MOVE_FILES_KIND, RENAME_FILES_KIND, TRASH_DELETE_KIND,
};
use super::open_repo_connection;

pub(super) struct FileUndoAction<'a> {
    pub(super) token_prefix: &'a str,
    pub(super) kind: &'a str,
    pub(super) summary: Value,
    pub(super) inverse: Value,
    pub(super) occurred_at: i64,
}

#[derive(Clone, Debug)]
pub(crate) struct FileUndoSnapshot {
    pub(crate) path: String,
    pub(crate) current_name: String,
    pub(crate) category: String,
}

pub(crate) struct FileUndoTarget<'a> {
    pub(crate) path: &'a str,
    pub(crate) name: &'a str,
    pub(crate) category: &'a str,
    pub(crate) index_only: bool,
}

struct FileUndoOperation<'a> {
    token_prefix: &'a str,
    kind: &'a str,
    operation: &'a str,
}

pub(crate) fn load_active_file_undo_snapshot(
    connection: &rusqlite::Connection,
    file_id: i64,
) -> CoreResult<FileUndoSnapshot> {
    connection
        .query_row(
            "SELECT path, current_name, category
               FROM files
              WHERE id = ?1 AND status = 'active'",
            params![file_id],
            |row| {
                Ok(FileUndoSnapshot {
                    path: row.get(0)?,
                    current_name: row.get(1)?,
                    category: row.get(2)?,
                })
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{file_id}")))
}

pub(crate) fn insert_rename_undo_action(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    before: &FileUndoSnapshot,
    final_path: &str,
    final_name: &str,
    index_only: bool,
    occurred_at: i64,
) -> CoreResult<String> {
    insert_file_state_undo_action(
        tx,
        file_id,
        before,
        FileUndoOperation {
            token_prefix: "rename-files",
            kind: RENAME_FILES_KIND,
            operation: "rename",
        },
        FileUndoTarget {
            path: final_path,
            name: final_name,
            category: &before.category,
            index_only,
        },
        occurred_at,
    )
}

pub(crate) fn insert_move_undo_action(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    before: &FileUndoSnapshot,
    target: FileUndoTarget<'_>,
    occurred_at: i64,
) -> CoreResult<String> {
    let (token_prefix, kind, operation) = if target.index_only {
        ("change-category", CHANGE_CATEGORY_KIND, "change_category")
    } else {
        ("move-files", MOVE_FILES_KIND, "move")
    };
    insert_file_state_undo_action(
        tx,
        file_id,
        before,
        FileUndoOperation {
            token_prefix,
            kind,
            operation,
        },
        target,
        occurred_at,
    )
}

pub(crate) fn insert_delete_undo_action(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    before: &FileUndoSnapshot,
    occurred_at: i64,
) -> CoreResult<String> {
    let summary = json!({
        "kind": TRASH_DELETE_KIND,
        "operation": "delete",
        "affected_count": 1,
        "affected_file_names": [before.current_name.as_str()],
    });
    let inverse = json!({
        "kind": "restore_deleted_file",
        "file_id": file_id,
        "trash_path": null,
        "restore_path": before.path,
        "restore_name": before.current_name,
        "restore_category": before.category,
    });
    insert_file_undo_action(
        tx,
        FileUndoAction {
            token_prefix: "trash-delete",
            kind: TRASH_DELETE_KIND,
            summary,
            inverse,
            occurred_at,
        },
    )
}

pub(crate) fn update_delete_undo_trash_path(
    repo_path: &Path,
    action_id: &str,
    trash_path: &Path,
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    let inverse_json: String = connection
        .query_row(
            "SELECT inverse_json
               FROM undo_actions
              WHERE token = ?1 AND kind = ?2 AND status = 'pending'",
            params![action_id, TRASH_DELETE_KIND],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found(action_id.to_owned()))?;
    let mut inverse: Value =
        serde_json::from_str(&inverse_json).map_err(|error| CoreError::db(error.to_string()))?;
    inverse["trash_path"] = json!(trash_path.to_string_lossy().into_owned());
    let updated_inverse =
        serde_json::to_string(&inverse).map_err(|error| CoreError::internal(error.to_string()))?;
    connection
        .execute(
            "UPDATE undo_actions
                SET inverse_json = ?2, updated_at = strftime('%s', 'now')
              WHERE token = ?1 AND kind = ?3 AND status = 'pending'",
            params![action_id, updated_inverse, TRASH_DELETE_KIND],
        )
        .map_err(|error| CoreError::db(error.to_string()))
        .and_then(|changed| {
            if changed == 1 {
                Ok(())
            } else {
                Err(CoreError::file_not_found(action_id.to_owned()))
            }
        })
}

pub(crate) fn delete_undo_action(
    tx: &rusqlite::Transaction<'_>,
    action_id: &str,
) -> CoreResult<()> {
    tx.execute(
        "DELETE FROM undo_actions WHERE token = ?1",
        params![action_id],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn insert_file_state_undo_action(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    before: &FileUndoSnapshot,
    operation: FileUndoOperation<'_>,
    expected: FileUndoTarget<'_>,
    occurred_at: i64,
) -> CoreResult<String> {
    let summary = json!({
        "kind": operation.kind,
        "operation": operation.operation,
        "affected_count": 1,
        "affected_file_names": [before.current_name.as_str()],
    });
    let inverse = json!({
        "kind": "restore_file_state",
        "file_id": file_id,
        "operation": operation.operation,
        "expected_path": expected.path,
        "expected_name": expected.name,
        "expected_category": expected.category,
        "restore_path": before.path,
        "restore_name": before.current_name,
        "restore_category": before.category,
        "index_only": expected.index_only,
    });
    insert_file_undo_action(
        tx,
        FileUndoAction {
            token_prefix: operation.token_prefix,
            kind: operation.kind,
            summary,
            inverse,
            occurred_at,
        },
    )
}

fn insert_file_undo_action(
    tx: &rusqlite::Transaction<'_>,
    action: FileUndoAction<'_>,
) -> CoreResult<String> {
    let token = format!("undo:{}:{}", action.token_prefix, Uuid::new_v4());
    let summary_json = serde_json::to_string(&action.summary)
        .map_err(|error| CoreError::internal(error.to_string()))?;
    let inverse_json = serde_json::to_string(&action.inverse)
        .map_err(|error| CoreError::internal(error.to_string()))?;
    tx.execute(
        "INSERT INTO undo_actions (
             token, kind, summary_json, inverse_json, status, created_at, updated_at
         ) VALUES (?1, ?2, ?3, ?4, 'pending', ?5, ?5)",
        params![
            token,
            action.kind,
            summary_json,
            inverse_json,
            action.occurred_at
        ],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(token)
}
