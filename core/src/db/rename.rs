use std::path::Path;

use rusqlite::{params, OptionalExtension, Row};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{CoreError, CoreResult, FileEntry};

use super::{open_repo_connection, origin_from_db, storage_mode_from_db, undo};

pub(crate) fn rename_active_file(
    repo_path: &Path,
    file_id: i64,
    final_path: &str,
    final_name: &str,
    detail: &Value,
) -> CoreResult<()> {
    let detail_json = rename_detail_json(detail)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let before = undo::load_active_file_undo_snapshot(&tx, file_id)?;
    let occurred_at = chrono::Utc::now().timestamp();
    let changed = tx
        .execute(
            "UPDATE files
             SET path = ?2,
                 current_name = ?3,
                 updated_at = strftime('%s', 'now')
             WHERE id = ?1 AND status = 'active'",
            params![file_id, final_path, final_name],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    insert_renamed_change(&tx, file_id, &detail_json)?;
    undo::insert_rename_undo_action(
        &tx,
        file_id,
        &before,
        final_path,
        final_name,
        false,
        occurred_at,
    )?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn rename_indexed_display_name(
    repo_path: &Path,
    file_id: i64,
    final_name: &str,
    detail: &Value,
) -> CoreResult<()> {
    let detail_json = rename_detail_json(detail)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let before = undo::load_active_file_undo_snapshot(&tx, file_id)?;
    let occurred_at = chrono::Utc::now().timestamp();
    let changed = tx
        .execute(
            "UPDATE files
             SET current_name = ?2,
                 updated_at = strftime('%s', 'now')
             WHERE id = ?1 AND status = 'active' AND storage_mode = 'indexed'",
            params![file_id, final_name],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    insert_renamed_change(&tx, file_id, &detail_json)?;
    undo::insert_rename_undo_action(
        &tx,
        file_id,
        &before,
        &before.path,
        final_name,
        true,
        occurred_at,
    )?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn rollback_renamed_active_file(
    repo_path: &Path,
    file_id: i64,
    original_path: &str,
    original_name: &str,
    forward_detail: &Value,
) -> CoreResult<()> {
    let forward_detail_json = rename_detail_json(forward_detail)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let changed = tx
        .execute(
            "UPDATE files
             SET path = ?2,
                 current_name = ?3,
                 updated_at = strftime('%s', 'now')
             WHERE id = ?1 AND status = 'active'",
            params![file_id, original_path, original_name],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    tx.execute(
        "DELETE FROM change_log
         WHERE file_id = ?1 AND action = 'renamed' AND detail_json = ?2",
        params![file_id, forward_detail_json],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn with_batch_rename_transaction<T>(
    repo_path: &Path,
    run: impl FnOnce(&mut rusqlite::Transaction<'_>) -> CoreResult<T>,
) -> CoreResult<T> {
    let mut connection = open_repo_connection(repo_path)?;
    let mut tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let result = run(&mut tx)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(result)
}

pub(crate) fn batch_update_rename_repo_owned_in_tx(
    connection: &rusqlite::Connection,
    file_id: i64,
    final_path: &str,
    final_name: &str,
    detail: &Value,
) -> CoreResult<()> {
    batch_update_rename_in_tx(
        connection,
        file_id,
        Some(final_path),
        final_name,
        "storage_mode IN ('copied', 'moved')",
        detail,
    )
}

pub(crate) fn batch_update_rename_indexed_in_tx(
    connection: &rusqlite::Connection,
    file_id: i64,
    final_name: &str,
    detail: &Value,
) -> CoreResult<()> {
    batch_update_rename_in_tx(
        connection,
        file_id,
        None,
        final_name,
        "storage_mode = 'indexed'",
        detail,
    )
}

pub(crate) fn load_batch_rename_active_file(
    connection: &rusqlite::Connection,
    file_id: i64,
) -> CoreResult<FileEntry> {
    connection
        .query_row(
            "SELECT id, path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path, imported_at, updated_at
               FROM files
              WHERE id = ?1 AND status = 'active'",
            params![file_id],
            batch_rename_file_entry_from_row,
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{file_id}")))
}

#[derive(Clone, Debug)]
pub(crate) struct BatchRenameUndoItem {
    pub(crate) file_id: i64,
    pub(crate) affected_file_name: String,
    pub(crate) expected_path: String,
    pub(crate) expected_name: String,
    pub(crate) expected_category: String,
    pub(crate) restore_path: String,
    pub(crate) restore_name: String,
    pub(crate) restore_category: String,
    pub(crate) index_only: bool,
}

impl BatchRenameUndoItem {
    pub(crate) fn from_file_states(
        before: &FileEntry,
        after: &FileEntry,
        index_only: bool,
    ) -> Self {
        Self {
            file_id: before.id,
            affected_file_name: before.current_name.clone(),
            expected_path: after.path.clone(),
            expected_name: after.current_name.clone(),
            expected_category: after.category.clone(),
            restore_path: before.path.clone(),
            restore_name: before.current_name.clone(),
            restore_category: before.category.clone(),
            index_only,
        }
    }
}

pub(crate) fn insert_batch_rename_undo_action_in_tx(
    connection: &rusqlite::Connection,
    items: &[BatchRenameUndoItem],
) -> CoreResult<String> {
    if items.is_empty() {
        return Err(CoreError::internal("internal error"));
    }
    let occurred_at = chrono::Utc::now().timestamp();
    let token = format!("undo:rename-files:{}", Uuid::new_v4());
    let summary = json!({
        "kind": "rename_files",
        "operation": "batch_rename",
        "affected_count": items.len(),
        "affected_file_names": items
            .iter()
            .map(|item| item.affected_file_name.as_str())
            .collect::<Vec<_>>(),
    });
    let inverse = json!({
        "kind": "restore_batch_file_state",
        "operation": "batch_rename",
        "items": items
            .iter()
            .map(|item| {
                json!({
                    "file_id": item.file_id,
                    "expected_path": item.expected_path,
                    "expected_name": item.expected_name,
                    "expected_category": item.expected_category,
                    "restore_path": item.restore_path,
                    "restore_name": item.restore_name,
                    "restore_category": item.restore_category,
                    "index_only": item.index_only,
                })
            })
            .collect::<Vec<_>>(),
    });
    let summary_json = rename_detail_json(&summary)?;
    let inverse_json = rename_detail_json(&inverse)?;
    connection
        .execute(
            "INSERT INTO undo_actions (
                 token, kind, summary_json, inverse_json, status, created_at, updated_at
             ) VALUES (?1, 'rename_files', ?2, ?3, 'pending', ?4, ?4)",
            params![token, summary_json, inverse_json, occurred_at],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(token)
}

fn batch_update_rename_in_tx(
    connection: &rusqlite::Connection,
    file_id: i64,
    final_path: Option<&str>,
    final_name: &str,
    row_clause: &str,
    detail: &Value,
) -> CoreResult<()> {
    let detail_json = rename_detail_json(detail)?;
    let update_sql = batch_rename_update_sql(final_path.is_some(), row_clause);
    let changed = match final_path {
        Some(final_path) => {
            connection.execute(&update_sql, params![file_id, final_path, final_name])
        }
        None => connection.execute(&update_sql, params![file_id, final_name]),
    }
    .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    insert_renamed_change(connection, file_id, &detail_json)
}

fn insert_renamed_change(
    connection: &rusqlite::Connection,
    file_id: i64,
    detail_json: &str,
) -> CoreResult<()> {
    connection
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'renamed', ?2, strftime('%s', 'now'))",
            params![file_id, detail_json],
        )
        .map(|_| ())
        .map_err(|error| CoreError::db(error.to_string()))
}

fn rename_detail_json(detail: &Value) -> CoreResult<String> {
    serde_json::to_string(detail).map_err(|error| CoreError::internal(error.to_string()))
}

fn batch_rename_update_sql(include_path: bool, row_clause: &str) -> String {
    if include_path {
        return format!(
            "UPDATE files
             SET path = ?2,
                 current_name = ?3,
                 updated_at = strftime('%s', 'now')
             WHERE id = ?1 AND status = 'active' AND {row_clause}"
        );
    }

    format!(
        "UPDATE files
         SET current_name = ?2,
             updated_at = strftime('%s', 'now')
         WHERE id = ?1 AND status = 'active' AND {row_clause}"
    )
}

fn batch_rename_file_entry_from_row(row: &Row<'_>) -> rusqlite::Result<FileEntry> {
    let storage_mode_value: String = row.get(7)?;
    let origin_value: String = row.get(8)?;
    Ok(FileEntry {
        id: row.get(0)?,
        path: row.get(1)?,
        original_name: row.get(2)?,
        current_name: row.get(3)?,
        category: row.get(4)?,
        size_bytes: row.get(5)?,
        hash_sha256: row.get(6)?,
        storage_mode: storage_mode_from_db(&storage_mode_value)
            .map_err(|_| rusqlite::Error::InvalidQuery)?,
        origin: origin_from_db(&origin_value).map_err(|_| rusqlite::Error::InvalidQuery)?,
        source_path: row.get(9)?,
        imported_at: row.get(10)?,
        updated_at: row.get(11)?,
    })
}
