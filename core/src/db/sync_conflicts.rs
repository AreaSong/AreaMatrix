//! Repository config-table storage for C4-15/C4-16 sync conflict metadata.

use std::path::Path;

use rusqlite::{params, Transaction};

use crate::{CoreError, CoreResult};

const SYNC_CONFLICT_STATE_KEY: &str = "sync_conflict_state";

pub(crate) struct ActiveSyncConflictFile {
    pub(crate) id: i64,
    pub(crate) path: String,
    pub(crate) current_name: String,
    pub(crate) size_bytes: i64,
    pub(crate) hash_sha256: String,
    pub(crate) updated_at: i64,
}

pub(crate) struct SyncConflictCanonicalUpdate<'a> {
    pub(crate) file_id: i64,
    pub(crate) size_bytes: i64,
    pub(crate) hash_sha256: &'a str,
}

pub(crate) struct SyncConflictResolutionRecord<'a> {
    pub(crate) serialized_state: &'a str,
    pub(crate) file_update: Option<SyncConflictCanonicalUpdate<'a>>,
    pub(crate) log_file_id: Option<i64>,
    pub(crate) detail_json: &'a str,
    pub(crate) occurred_at: i64,
}

pub(crate) fn list_active_sync_conflict_files(
    repo_path: &Path,
) -> CoreResult<Vec<ActiveSyncConflictFile>> {
    let connection = super::open_repo_connection(repo_path)?;
    let mut statement = connection
        .prepare(
            "SELECT id, path, current_name, size_bytes, hash_sha256, updated_at
             FROM files
             WHERE status = 'active'
             ORDER BY path ASC, id ASC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], |row| {
            Ok(ActiveSyncConflictFile {
                id: row.get(0)?,
                path: row.get(1)?,
                current_name: row.get(2)?,
                size_bytes: row.get(3)?,
                hash_sha256: row.get(4)?,
                updated_at: row.get(5)?,
            })
        })
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn load_sync_conflict_state(repo_path: &Path) -> CoreResult<Option<(String, i64)>> {
    super::load_repo_config_record(repo_path, SYNC_CONFLICT_STATE_KEY)
}

pub(crate) fn replace_sync_conflict_state(
    repo_path: &Path,
    serialized_state: &str,
    detected_at: i64,
) -> CoreResult<()> {
    super::ensure_config_storage_writable(repo_path)?;
    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    super::upsert_repo_config_record(&tx, SYNC_CONFLICT_STATE_KEY, serialized_state, detected_at)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn preflight_sync_conflict_resolution(repo_path: &Path) -> CoreResult<()> {
    super::ensure_config_storage_writable(repo_path)?;
    let connection = super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let available_tables = connection
        .query_row(
            "SELECT COUNT(*)
             FROM sqlite_master
             WHERE type = 'table'
               AND name IN ('repo_config', 'files', 'change_log')",
            [],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if available_tables == 3 {
        Ok(())
    } else {
        Err(CoreError::db(
            "sync conflict resolution metadata is unavailable",
        ))
    }
}

pub(crate) fn record_sync_conflict_resolution(
    repo_path: &Path,
    record: SyncConflictResolutionRecord<'_>,
) -> CoreResult<()> {
    super::ensure_config_storage_writable(repo_path)?;
    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    if let Some(update) = &record.file_update {
        update_canonical_file_metadata(&tx, update, record.occurred_at)?;
    }
    super::upsert_repo_config_record(
        &tx,
        SYNC_CONFLICT_STATE_KEY,
        record.serialized_state,
        record.occurred_at,
    )?;
    insert_resolution_change(&tx, record)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn update_canonical_file_metadata(
    tx: &Transaction<'_>,
    update: &SyncConflictCanonicalUpdate<'_>,
    updated_at: i64,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET size_bytes = ?2,
                 hash_sha256 = ?3,
                 updated_at = ?4
             WHERE id = ?1 AND status = 'active'",
            params![
                update.file_id,
                update.size_bytes,
                update.hash_sha256,
                updated_at,
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::conflict("sync conflict file record is stale"))
    }
}

fn insert_resolution_change(
    tx: &Transaction<'_>,
    record: SyncConflictResolutionRecord<'_>,
) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, ?3)",
        params![record.log_file_id, record.detail_json, record.occurred_at],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}
