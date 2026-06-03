//! Repository config-table storage for C4-15 sync conflict metadata.

use std::path::Path;

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
