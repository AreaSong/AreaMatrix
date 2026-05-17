use std::path::Path;

use rusqlite::params;
use serde_json::Value;

use crate::{CoreError, CoreResult};

use super::{open_repo_connection, undo};

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

fn insert_renamed_change(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    detail_json: &str,
) -> CoreResult<()> {
    tx.execute(
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
