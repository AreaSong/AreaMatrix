//! Repository config-table storage for C3-02 local model status snapshots.

use std::path::Path;

use rusqlite::params;

use crate::{CoreError, CoreResult, LocalModelStatusSnapshot};

const LOCAL_MODEL_STATUS_KEY_PREFIX: &str = "local_model_status:";

pub(crate) fn update_local_model_status_record(
    repo_path: &Path,
    snapshot: &LocalModelStatusSnapshot,
) -> CoreResult<i64> {
    super::ensure_config_storage_writable(repo_path)?;

    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let updated_at = current_timestamp(&tx)?;
    let key = status_key(snapshot);
    let value = serde_json::to_string(snapshot)
        .map_err(|_| CoreError::config("local model status metadata is invalid"))?;

    tx.execute(
        "INSERT INTO repo_config (key, value, updated_at) \
         VALUES (?1, ?2, ?3) \
         ON CONFLICT(key) DO UPDATE SET \
         value = excluded.value, updated_at = excluded.updated_at",
        params![key, value, updated_at],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(updated_at)
}

fn current_timestamp(tx: &rusqlite::Transaction<'_>) -> CoreResult<i64> {
    tx.query_row("SELECT CAST(strftime('%s', 'now') AS INTEGER)", [], |row| {
        row.get(0)
    })
    .map_err(|error| CoreError::db(error.to_string()))
}

fn status_key(snapshot: &LocalModelStatusSnapshot) -> String {
    format!("{LOCAL_MODEL_STATUS_KEY_PREFIX}{}", snapshot.model_id)
}
