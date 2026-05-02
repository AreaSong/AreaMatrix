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

pub(crate) struct ExternalRenamedRow {
    pub(crate) file_id: i64,
    pub(crate) path: String,
    pub(crate) current_name: String,
    pub(crate) detail_json: String,
}

pub(crate) struct ExternalRemovedRow {
    pub(crate) file_id: i64,
    pub(crate) detail_json: String,
}

pub(crate) struct ExternalRenameCandidate {
    pub(crate) id: i64,
    pub(crate) path: String,
    pub(crate) current_name: String,
    pub(crate) category: String,
}

pub(crate) struct ExternalSyncApplyResult {
    pub(crate) detected_creates: i64,
    pub(crate) detected_renames: i64,
    pub(crate) detected_deletes: i64,
}

pub(crate) fn apply_external_sync_batch(
    repo_path: &Path,
    created_rows: Vec<ExternalCreatedRow>,
    renamed_rows: Vec<ExternalRenamedRow>,
    removed_rows: Vec<ExternalRemovedRow>,
    cursor: Option<i64>,
) -> CoreResult<ExternalSyncApplyResult> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection.transaction().map_err(|_| CoreError::Db)?;
    let mut detected_creates = 0_i64;
    let mut detected_renames = 0_i64;
    let mut detected_deletes = 0_i64;

    for row in created_rows {
        if insert_external_file(&tx, row)? {
            detected_creates += 1;
        }
    }
    for row in renamed_rows {
        update_external_renamed_file(&tx, row)?;
        detected_renames += 1;
    }
    for row in removed_rows {
        soft_delete_external_removed_file(&tx, row)?;
        detected_deletes += 1;
    }
    if let Some(last_event_id) = cursor {
        set_cursor(&tx, last_event_id)?;
    }

    tx.commit().map_err(|_| CoreError::Db)?;
    Ok(ExternalSyncApplyResult {
        detected_creates,
        detected_renames,
        detected_deletes,
    })
}

pub(crate) fn find_external_rename_candidates_by_hash(
    repo_path: &Path,
    hash_sha256: &str,
    new_path: &str,
) -> CoreResult<Vec<ExternalRenameCandidate>> {
    let connection = open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT id, path, current_name, category
             FROM files
             WHERE hash_sha256 = ?1
               AND path != ?2
               AND status = 'active'
             ORDER BY imported_at ASC, id ASC
             LIMIT 2",
        )
        .map_err(|_| CoreError::Db)?;
    let rows = statement
        .query_map(params![hash_sha256, new_path], |row| {
            Ok(ExternalRenameCandidate {
                id: row.get(0)?,
                path: row.get(1)?,
                current_name: row.get(2)?,
                category: row.get(3)?,
            })
        })
        .map_err(|_| CoreError::Db)?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|_| CoreError::Db)
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

fn update_external_renamed_file(tx: &Transaction<'_>, row: ExternalRenamedRow) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET path = ?2,
                 current_name = ?3,
                 updated_at = strftime('%s', 'now')
             WHERE id = ?1 AND status = 'active'",
            params![row.file_id, row.path, row.current_name],
        )
        .map_err(|_| CoreError::Db)?;
    if changed != 1 {
        return Err(CoreError::FileNotFound);
    }

    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'renamed', ?2, strftime('%s', 'now'))",
        params![row.file_id, row.detail_json],
    )
    .map(|_| ())
    .map_err(|_| CoreError::Db)
}

fn soft_delete_external_removed_file(
    tx: &Transaction<'_>,
    row: ExternalRemovedRow,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET deleted_at = strftime('%s', 'now'),
                 updated_at = strftime('%s', 'now'),
                 status = 'deleted'
             WHERE id = ?1 AND status = 'active'",
            params![row.file_id],
        )
        .map_err(|_| CoreError::Db)?;
    if changed != 1 {
        return Err(CoreError::FileNotFound);
    }

    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'deleted', ?2, strftime('%s', 'now'))",
        params![row.file_id, row.detail_json],
    )
    .map(|_| ())
    .map_err(|_| CoreError::Db)
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
