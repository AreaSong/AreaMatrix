use std::path::Path;

use rusqlite::{params, OptionalExtension, Row};
use serde_json::Value;

use crate::{CoreError, CoreResult, FileEntry, FileOrigin, StorageMode};

use super::{open_repo_connection, origin_from_db, storage_mode_from_db, storage_mode_to_db};

pub(crate) struct NewImportRow {
    pub(crate) path: String,
    pub(crate) original_name: String,
    pub(crate) current_name: String,
    pub(crate) category: String,
    pub(crate) size_bytes: i64,
    pub(crate) hash_sha256: String,
    pub(crate) storage_mode: StorageMode,
    pub(crate) origin: FileOrigin,
    pub(crate) source_path: Option<String>,
    pub(crate) imported_at: i64,
}

pub(crate) fn find_active_file_by_hash(
    repo_path: &Path,
    hash_sha256: &str,
) -> CoreResult<Option<FileEntry>> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT id, path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path, imported_at, updated_at
             FROM files
             WHERE hash_sha256 = ?1 AND status = 'active'
             ORDER BY imported_at ASC, id ASC
             LIMIT 1",
            params![hash_sha256],
            file_entry_from_row,
        )
        .optional()
        .map_err(|_| CoreError::Db)
}

pub(crate) fn get_active_file_by_id(repo_path: &Path, file_id: i64) -> CoreResult<FileEntry> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT id, path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path, imported_at, updated_at
             FROM files
             WHERE id = ?1 AND status = 'active'",
            params![file_id],
            file_entry_from_row,
        )
        .optional()
        .map_err(|_| CoreError::Db)?
        .ok_or(CoreError::FileNotFound)
}

pub(crate) fn insert_import_staging(repo_path: &Path, row: NewImportRow) -> CoreResult<i64> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection.transaction().map_err(|_| CoreError::Db)?;
    tx.execute(
        "INSERT INTO files (
            path, original_name, current_name, category, size_bytes,
            hash_sha256, storage_mode, origin, source_path,
            imported_at, updated_at, status
         ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9,
            ?10, ?10, 'staging'
         )",
        params![
            row.path,
            row.original_name,
            row.current_name,
            row.category,
            row.size_bytes,
            row.hash_sha256,
            storage_mode_to_db(&row.storage_mode),
            origin_to_db(&row.origin),
            row.source_path,
            row.imported_at,
        ],
    )
    .map_err(|_| CoreError::Db)?;
    let file_id = tx.last_insert_rowid();
    tx.commit().map_err(|_| CoreError::Db)?;
    Ok(file_id)
}

pub(crate) fn insert_active_indexed_import(
    repo_path: &Path,
    row: NewImportRow,
    detail: &Value,
) -> CoreResult<i64> {
    let detail_json = serde_json::to_string(detail).map_err(|_| CoreError::Internal)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection.transaction().map_err(|_| CoreError::Db)?;
    tx.execute(
        "INSERT INTO files (
            path, original_name, current_name, category, size_bytes,
            hash_sha256, storage_mode, origin, source_path,
            imported_at, updated_at, status
         ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9,
            ?10, ?10, 'active'
         )",
        params![
            row.path,
            row.original_name,
            row.current_name,
            row.category,
            row.size_bytes,
            row.hash_sha256,
            storage_mode_to_db(&row.storage_mode),
            origin_to_db(&row.origin),
            row.source_path,
            row.imported_at,
        ],
    )
    .map_err(|_| CoreError::Db)?;
    let file_id = tx.last_insert_rowid();

    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'imported', ?2, strftime('%s', 'now'))",
        params![file_id, detail_json],
    )
    .map_err(|_| CoreError::Db)?;
    tx.commit().map_err(|_| CoreError::Db)?;
    Ok(file_id)
}

pub(crate) fn promote_imported_file(
    repo_path: &Path,
    file_id: i64,
    final_path: &str,
    final_name: &str,
    detail: &Value,
) -> CoreResult<()> {
    let detail_json = serde_json::to_string(detail).map_err(|_| CoreError::Internal)?;
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection.transaction().map_err(|_| CoreError::Db)?;
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
        .map_err(|_| CoreError::Db)?;
    if changed != 1 {
        return Err(CoreError::Db);
    }

    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'imported', ?2, strftime('%s', 'now'))",
        params![file_id, detail_json],
    )
    .map_err(|_| CoreError::Db)?;
    tx.commit().map_err(|_| CoreError::Db)
}

pub(crate) fn delete_file_row(repo_path: &Path, file_id: i64) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .execute("DELETE FROM files WHERE id = ?1", params![file_id])
        .map(|_| ())
        .map_err(|_| CoreError::Db)
}

fn origin_to_db(origin: &FileOrigin) -> &'static str {
    match origin {
        FileOrigin::Imported => "imported",
        FileOrigin::Adopted => "adopted",
        FileOrigin::External => "external",
    }
}

fn file_entry_from_row(row: &Row<'_>) -> rusqlite::Result<FileEntry> {
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
