use std::path::Path;

use rusqlite::{params, OptionalExtension, Row};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{CoreError, CoreResult, FileEntry};

use super::{open_repo_connection, origin_from_db, storage_mode_from_db, undo};

pub(crate) fn move_repo_owned_file_to_category(
    repo_path: &Path,
    file_id: i64,
    final_path: &str,
    final_name: &str,
    new_category: &str,
    detail: &Value,
) -> CoreResult<()> {
    update_file_category_and_log(
        repo_path,
        file_id,
        Some((final_path, final_name)),
        new_category,
        "storage_mode IN ('copied', 'moved')",
        detail,
        true,
    )
}

pub(crate) fn move_indexed_file_to_category(
    repo_path: &Path,
    file_id: i64,
    new_category: &str,
    detail: &Value,
) -> CoreResult<()> {
    update_file_category_and_log(
        repo_path,
        file_id,
        None,
        new_category,
        "storage_mode = 'indexed'",
        detail,
        true,
    )
}

pub(crate) fn with_batch_category_transaction<T>(
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

pub(crate) fn batch_update_category_repo_owned_in_tx(
    connection: &rusqlite::Connection,
    file_id: i64,
    final_path: &str,
    final_name: &str,
    new_category: &str,
    detail: &Value,
) -> CoreResult<()> {
    update_file_category_and_log_on_connection(
        connection,
        file_id,
        Some((final_path, final_name)),
        new_category,
        "storage_mode IN ('copied', 'moved')",
        detail,
    )
}

pub(crate) fn batch_update_category_metadata_only_in_tx(
    connection: &rusqlite::Connection,
    file_id: i64,
    new_category: &str,
    detail: &Value,
) -> CoreResult<()> {
    update_file_category_and_log_on_connection(
        connection,
        file_id,
        None,
        new_category,
        "status = 'active'",
        detail,
    )
}

pub(crate) fn load_batch_category_active_file(
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
            batch_category_file_entry_from_row,
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{file_id}")))
}

#[derive(Clone, Debug)]
pub(crate) struct BatchCategoryUndoItem {
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

impl BatchCategoryUndoItem {
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

pub(crate) fn insert_batch_category_undo_action_in_tx(
    connection: &rusqlite::Connection,
    items: &[BatchCategoryUndoItem],
) -> CoreResult<String> {
    if items.is_empty() {
        return Err(CoreError::internal("internal error"));
    }
    let occurred_at = chrono::Utc::now().timestamp();
    insert_batch_category_undo_action_with_connection(connection, items, occurred_at)
}

fn update_file_category_and_log(
    repo_path: &Path,
    file_id: i64,
    final_location: Option<(&str, &str)>,
    new_category: &str,
    row_clause: &str,
    detail: &Value,
    insert_undo: bool,
) -> CoreResult<()> {
    let detail_json = detail_json(detail)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let before = undo::load_active_file_undo_snapshot(&tx, file_id)?;
    let occurred_at = chrono::Utc::now().timestamp();
    let update_sql = update_sql(final_location.is_some(), row_clause);
    let changed = match final_location {
        Some((final_path, final_name)) => tx.execute(
            &update_sql,
            params![file_id, final_path, final_name, new_category],
        ),
        None => tx.execute(&update_sql, params![file_id, new_category]),
    }
    .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'moved', ?2, strftime('%s', 'now'))",
        params![file_id, detail_json],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    if insert_undo {
        let (final_path, final_name, index_only) = match final_location {
            Some((path, name)) => (path, name, false),
            None => (before.path.as_str(), before.current_name.as_str(), true),
        };
        undo::insert_move_undo_action(
            &tx,
            file_id,
            &before,
            undo::FileUndoTarget {
                path: final_path,
                name: final_name,
                category: new_category,
                index_only,
            },
            occurred_at,
        )?;
    }
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn update_file_category_and_log_on_connection(
    connection: &rusqlite::Connection,
    file_id: i64,
    final_location: Option<(&str, &str)>,
    new_category: &str,
    row_clause: &str,
    detail: &Value,
) -> CoreResult<()> {
    let detail_json = detail_json(detail)?;
    let update_sql = update_sql(final_location.is_some(), row_clause);
    let changed = match final_location {
        Some((final_path, final_name)) => connection.execute(
            &update_sql,
            params![file_id, final_path, final_name, new_category],
        ),
        None => connection.execute(&update_sql, params![file_id, new_category]),
    }
    .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    connection
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, 'moved', ?2, strftime('%s', 'now'))",
            params![file_id, detail_json],
        )
        .map(|_| ())
        .map_err(|error| CoreError::db(error.to_string()))
}

fn update_sql(include_path: bool, row_clause: &str) -> String {
    if include_path {
        return format!(
            "UPDATE files
             SET path = ?2,
                 current_name = ?3,
                 category = ?4,
                 updated_at = strftime('%s', 'now')
             WHERE id = ?1 AND status = 'active' AND {row_clause}"
        );
    }

    format!(
        "UPDATE files
         SET category = ?2,
             updated_at = strftime('%s', 'now')
         WHERE id = ?1 AND status = 'active' AND {row_clause}"
    )
}

fn detail_json(detail: &Value) -> CoreResult<String> {
    serde_json::to_string(detail).map_err(|error| CoreError::internal(error.to_string()))
}

fn batch_category_file_entry_from_row(row: &Row<'_>) -> rusqlite::Result<FileEntry> {
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

fn insert_batch_category_undo_action_with_connection(
    connection: &rusqlite::Connection,
    items: &[BatchCategoryUndoItem],
    occurred_at: i64,
) -> CoreResult<String> {
    let token = format!("undo:batch-category:{}", Uuid::new_v4());
    let summary = json!({
        "kind": "batch_change_category",
        "operation": "batch_change_category",
        "affected_count": items.len(),
        "affected_file_names": items
            .iter()
            .map(|item| item.affected_file_name.as_str())
            .collect::<Vec<_>>(),
    });
    let inverse = json!({
        "kind": "restore_batch_file_state",
        "operation": "batch_change_category",
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
    let summary_json =
        serde_json::to_string(&summary).map_err(|error| CoreError::internal(error.to_string()))?;
    let inverse_json =
        serde_json::to_string(&inverse).map_err(|error| CoreError::internal(error.to_string()))?;
    connection
        .execute(
            "INSERT INTO undo_actions (
                 token, kind, summary_json, inverse_json, status, created_at, updated_at
             ) VALUES (?1, 'batch_change_category', ?2, ?3, 'pending', ?4, ?4)",
            params![token, summary_json, inverse_json, occurred_at],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(token)
}
