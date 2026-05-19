use std::path::Path;

use rusqlite::params;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{CoreError, CoreResult};

use super::{clear_redo_stack_in_tx, open_repo_connection, undo};

pub(crate) fn soft_delete_repo_owned_file(
    repo_path: &Path,
    file_id: i64,
    detail: &Value,
) -> CoreResult<String> {
    update_file_status_and_log(
        repo_path,
        file_id,
        "deleted",
        repo_owned_clause(),
        detail,
        true,
    )
}

pub(crate) fn soft_delete_batch_repo_owned_file(
    repo_path: &Path,
    file_id: i64,
    detail: &Value,
) -> CoreResult<()> {
    update_file_status_and_log(
        repo_path,
        file_id,
        "deleted",
        repo_owned_clause(),
        detail,
        false,
    )
    .map(|_| ())
}

pub(crate) fn remove_index_entry_row(
    repo_path: &Path,
    file_id: i64,
    detail: &Value,
) -> CoreResult<()> {
    update_file_status_and_log(
        repo_path,
        file_id,
        "removed_from_index",
        index_entry_clause(),
        detail,
        false,
    )
    .map(|_| ())
}

pub(crate) fn remove_batch_delete_index_entry_row(
    repo_path: &Path,
    file_id: i64,
    detail: &Value,
) -> CoreResult<()> {
    update_file_status_and_log(
        repo_path,
        file_id,
        "removed_from_index",
        "1 = 1",
        detail,
        false,
    )
    .map(|_| ())
}

#[derive(Clone, Debug)]
pub(crate) struct BatchDeleteUndoItem {
    pub(crate) file_id: i64,
    pub(crate) affected_file_name: String,
    pub(crate) trash_path: String,
    pub(crate) restore_path: String,
    pub(crate) restore_name: String,
    pub(crate) restore_category: String,
}

pub(crate) fn insert_batch_delete_undo_action(
    repo_path: &Path,
    items: &[BatchDeleteUndoItem],
) -> CoreResult<String> {
    if items.is_empty() {
        return Err(CoreError::internal("internal error"));
    }
    let connection = open_repo_connection(repo_path)?;
    let occurred_at = chrono::Utc::now().timestamp();
    clear_redo_stack_in_tx(&connection, occurred_at)?;
    let token = format!("undo:batch-trash-delete:{}", Uuid::new_v4());
    let summary = json!({
        "kind": "trash_delete",
        "operation": "batch_delete",
        "affected_count": items.len(),
        "affected_file_names": items
            .iter()
            .map(|item| item.affected_file_name.as_str())
            .collect::<Vec<_>>(),
    });
    let inverse = json!({
        "kind": "restore_batch_deleted_files",
        "operation": "batch_delete",
        "items": items
            .iter()
            .map(|item| {
                json!({
                    "file_id": item.file_id,
                    "trash_path": item.trash_path,
                    "restore_path": item.restore_path,
                    "restore_name": item.restore_name,
                    "restore_category": item.restore_category,
                })
            })
            .collect::<Vec<_>>(),
    });
    let summary_json = detail_json(&summary)?;
    let inverse_json = detail_json(&inverse)?;
    connection
        .execute(
            "INSERT INTO undo_actions (
                 token, kind, summary_json, inverse_json, status, created_at, updated_at
             ) VALUES (?1, 'trash_delete', ?2, ?3, 'pending', ?4, ?4)",
            params![token, summary_json, inverse_json, occurred_at],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(token)
}

pub(crate) fn rollback_deleted_repo_owned_file(
    repo_path: &Path,
    file_id: i64,
    detail: &Value,
    undo_token: Option<&str>,
) -> CoreResult<()> {
    let detail_json = detail_json(detail)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let changed = tx
        .execute(
            "UPDATE files
             SET deleted_at = NULL,
                 updated_at = strftime('%s', 'now'),
                 status = 'active'
             WHERE id = ?1 AND status = 'deleted' AND storage_mode IN ('copied', 'moved')",
            params![file_id],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    tx.execute(
        "DELETE FROM change_log
         WHERE file_id = ?1 AND action = 'deleted' AND detail_json = ?2",
        params![file_id, detail_json],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    if let Some(token) = undo_token {
        undo::delete_undo_action(&tx, token)?;
    }
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn rollback_removed_index_entry_row(
    repo_path: &Path,
    file_id: i64,
    detail: &Value,
) -> CoreResult<()> {
    let detail_json = detail_json(detail)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let changed = tx
        .execute(
            "UPDATE files
             SET deleted_at = NULL,
                 updated_at = strftime('%s', 'now'),
                 status = 'active'
             WHERE id = ?1 AND status = 'deleted'",
            params![file_id],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    tx.execute(
        "DELETE FROM change_log
         WHERE file_id = ?1 AND action = 'removed_from_index' AND detail_json = ?2",
        params![file_id, detail_json],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn update_file_status_and_log(
    repo_path: &Path,
    file_id: i64,
    action: &str,
    row_clause: &str,
    detail: &Value,
    insert_undo: bool,
) -> CoreResult<String> {
    let detail_json = detail_json(detail)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let before = if insert_undo {
        Some(undo::load_active_file_undo_snapshot(&tx, file_id)?)
    } else {
        None
    };
    let occurred_at = chrono::Utc::now().timestamp();
    let update_sql = format!(
        "UPDATE files
         SET deleted_at = strftime('%s', 'now'),
             updated_at = strftime('%s', 'now'),
             status = 'deleted'
         WHERE id = ?1 AND status = 'active' AND {row_clause}"
    );
    let changed = tx
        .execute(&update_sql, params![file_id])
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::file_not_found("missing file"));
    }
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, ?2, ?3, strftime('%s', 'now'))",
        params![file_id, action, detail_json],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    clear_redo_stack_in_tx(&tx, occurred_at)?;
    let undo_token = if action == "deleted" && insert_undo {
        let before = before.ok_or_else(|| CoreError::internal("internal error"))?;
        Some(undo::insert_delete_undo_action(
            &tx,
            file_id,
            &before,
            occurred_at,
        )?)
    } else {
        None
    };
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(undo_token.unwrap_or_default())
}

fn repo_owned_clause() -> &'static str {
    "storage_mode IN ('copied', 'moved')"
}

fn index_entry_clause() -> &'static str {
    "(storage_mode = 'indexed' OR origin IN ('adopted', 'external'))"
}

fn detail_json(detail: &Value) -> CoreResult<String> {
    serde_json::to_string(detail).map_err(|error| CoreError::internal(error.to_string()))
}
