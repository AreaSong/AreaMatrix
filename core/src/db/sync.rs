use std::path::Path;

use rusqlite::{params, OptionalExtension, Transaction};

use crate::{CoreError, CoreResult};

use super::{open_repo_connection, storage_mode_to_db};

pub(crate) struct ExternalCreatedRow {
    pub(crate) path: String,
    pub(crate) original_name: String,
    pub(crate) current_name: String,
    pub(crate) category: String,
    pub(crate) size_bytes: i64,
    pub(crate) hash_sha256: String,
    pub(crate) detail_json: String,
}

pub(crate) fn apply_external_created_batch(
    repo_path: &Path,
    rows: Vec<ExternalCreatedRow>,
    cursor: Option<i64>,
) -> CoreResult<i64> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection.transaction().map_err(|_| CoreError::Db)?;
    let mut inserted = 0_i64;

    for row in rows {
        if insert_external_file(&tx, row)? {
            inserted += 1;
        }
    }
    if let Some(last_event_id) = cursor {
        set_cursor(&tx, last_event_id)?;
    }

    tx.commit().map_err(|_| CoreError::Db)?;
    Ok(inserted)
}

pub(crate) fn get_fs_event_cursor(repo_path: &Path) -> CoreResult<Option<i64>> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT last_event_id FROM fs_event_cursor WHERE id = 1",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(|_| CoreError::Db)
}

pub(crate) fn set_fs_event_cursor(repo_path: &Path, last_event_id: i64) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection.transaction().map_err(|_| CoreError::Db)?;
    set_cursor(&tx, last_event_id)?;
    tx.commit().map_err(|_| CoreError::Db)
}

fn insert_external_file(tx: &Transaction<'_>, row: ExternalCreatedRow) -> CoreResult<bool> {
    let changed = tx
        .execute(
            "INSERT OR IGNORE INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?3, ?4, ?5,
                ?6, ?7, 'external', NULL,
                strftime('%s', 'now'), strftime('%s', 'now'), 'active'
             )",
            params![
                row.path,
                row.original_name,
                row.current_name,
                row.category,
                row.size_bytes,
                row.hash_sha256,
                storage_mode_to_db(&crate::StorageMode::Indexed),
            ],
        )
        .map_err(|_| CoreError::Db)?;
    if changed == 0 {
        return Ok(false);
    }

    let file_id = tx.last_insert_rowid();
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, strftime('%s', 'now'))",
        params![file_id, row.detail_json],
    )
    .map_err(|_| CoreError::Db)?;
    Ok(true)
}

fn set_cursor(tx: &Transaction<'_>, last_event_id: i64) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO fs_event_cursor (id, last_event_id, updated_at)
         VALUES (1, ?1, strftime('%s', 'now'))
         ON CONFLICT(id) DO UPDATE SET
             last_event_id = excluded.last_event_id,
             updated_at = excluded.updated_at",
        params![last_event_id],
    )
    .map(|_| ())
    .map_err(|_| CoreError::Db)
}
