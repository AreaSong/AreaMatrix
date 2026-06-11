use std::path::Path;

use rusqlite::{params, OptionalExtension, Row};
use serde_json::Value;

use crate::{CoreError, CoreResult, FileOrigin, StorageMode};

use super::{open_repo_connection, origin_from_db, storage_mode_from_db};

pub(crate) struct MissingFileRecoveryEntry {
    pub(crate) id: i64,
    pub(crate) path: String,
    pub(crate) category: String,
    pub(crate) hash_sha256: String,
    pub(crate) storage_mode: StorageMode,
    pub(crate) origin: FileOrigin,
    pub(crate) source_path: Option<String>,
    pub(crate) updated_at: i64,
}

pub(crate) struct MissingFileRelinkUpdate<'a> {
    pub(crate) relative_path: &'a str,
    pub(crate) current_name: &'a str,
    pub(crate) category: &'a str,
    pub(crate) source_path: Option<&'a str>,
    pub(crate) size_bytes: i64,
    pub(crate) detail: &'a Value,
}

pub(crate) fn load_missing_file_recovery_entry(
    repo_path: &Path,
    file_id: i64,
) -> CoreResult<MissingFileRecoveryEntry> {
    let connection = open_repo_connection(repo_path).map_err(map_recovery_open_error)?;
    connection
        .query_row(
            "SELECT id, path, category, hash_sha256,
                    storage_mode, origin, source_path, updated_at
             FROM files
             WHERE id = ?1 AND status = 'active'",
            params![file_id],
            recovery_entry_from_row,
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::file_not_found("missing file record"))
}

pub(crate) fn relink_missing_file_record(
    repo_path: &Path,
    entry: &MissingFileRecoveryEntry,
    update: MissingFileRelinkUpdate<'_>,
) -> CoreResult<()> {
    let detail_json = detail_json(update.detail)?;
    let mut connection = open_repo_connection(repo_path).map_err(map_recovery_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let changed = tx
        .execute(
            "UPDATE files
             SET path = ?2,
                 current_name = ?3,
                 category = ?4,
                 size_bytes = ?5,
                 source_path = ?6,
                 updated_at = strftime('%s', 'now')
             WHERE id = ?1 AND status = 'active'",
            params![
                entry.id,
                update.relative_path,
                update.current_name,
                update.category,
                update.size_bytes,
                update.source_path,
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::file_not_found("missing file record"));
    }
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, strftime('%s', 'now'))",
        params![entry.id, detail_json],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn mark_missing_file_record_removed(
    repo_path: &Path,
    entry: &MissingFileRecoveryEntry,
    detail: &Value,
) -> CoreResult<()> {
    let detail_json = detail_json(detail)?;
    let mut connection = open_repo_connection(repo_path).map_err(map_recovery_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let changed = tx
        .execute(
            "UPDATE files
             SET deleted_at = strftime('%s', 'now'),
                 updated_at = strftime('%s', 'now'),
                 status = 'deleted'
             WHERE id = ?1 AND status = 'active'",
            params![entry.id],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::file_not_found("missing file record"));
    }
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'removed_from_index', ?2, strftime('%s', 'now'))",
        params![entry.id, detail_json],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn recovery_entry_from_row(row: &Row<'_>) -> rusqlite::Result<MissingFileRecoveryEntry> {
    let storage_mode_value: String = row.get(4)?;
    let origin_value: String = row.get(5)?;
    Ok(MissingFileRecoveryEntry {
        id: row.get(0)?,
        path: row.get(1)?,
        category: row.get(2)?,
        hash_sha256: row.get(3)?,
        storage_mode: storage_mode_from_db(&storage_mode_value)
            .map_err(|_| rusqlite::Error::InvalidQuery)?,
        origin: origin_from_db(&origin_value).map_err(|_| rusqlite::Error::InvalidQuery)?,
        source_path: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

fn detail_json(detail: &Value) -> CoreResult<String> {
    serde_json::to_string(detail).map_err(|error| CoreError::internal(error.to_string()))
}

fn map_recovery_open_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => {
            CoreError::db("missing file recovery metadata unavailable")
        }
        other => other,
    }
}
