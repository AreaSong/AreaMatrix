//! Repository config-table storage for C4-12 watcher health metadata.

use std::path::Path;

use rusqlite::params;

use crate::{CoreError, CoreResult};

const PLATFORM_WATCHER_HEALTH_KEY: &str = "platform_watcher_health";

pub(crate) fn upsert_platform_watcher_health(
    repo_path: &Path,
    serialized_snapshot: &str,
) -> CoreResult<()> {
    super::ensure_config_storage_writable(repo_path)?;

    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    tx.execute(
        "INSERT INTO repo_config (key, value, updated_at) \
         VALUES (?1, ?2, strftime('%s', 'now')) \
         ON CONFLICT(key) DO UPDATE SET \
             value = excluded.value, updated_at = excluded.updated_at",
        params![PLATFORM_WATCHER_HEALTH_KEY, serialized_snapshot],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}
