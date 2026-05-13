use std::path::Path;

use rusqlite::params;
use serde_json::Value;

use crate::{CoreError, CoreResult};

use super::open_repo_connection;

pub(crate) fn soft_delete_repo_owned_file(
    repo_path: &Path,
    file_id: i64,
    detail: &Value,
) -> CoreResult<()> {
    update_file_status_and_log(repo_path, file_id, "deleted", repo_owned_clause(), detail)
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
    )
}

pub(crate) fn rollback_deleted_repo_owned_file(
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
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn update_file_status_and_log(
    repo_path: &Path,
    file_id: i64,
    action: &str,
    row_clause: &str,
    detail: &Value,
) -> CoreResult<()> {
    let detail_json = detail_json(detail)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
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
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
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
