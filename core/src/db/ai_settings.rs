//! Repository config-table storage for C3-01 AI settings.

use std::{fs::Metadata, path::Path};

use rusqlite::{params, OptionalExtension};

use crate::{CoreError, CoreResult};

const AI_CONFIG_KEY: &str = "ai_config";
const AI_ENABLED_KEY: &str = "ai_enabled";

pub(crate) fn load_ai_config_record(repo_path: &Path) -> CoreResult<Option<(String, i64)>> {
    let db_path = super::db_path(repo_path);
    if !super::path_exists(&db_path)? {
        return Ok(None);
    }
    ensure_readable_path(&repo_path.join(super::AREA_MATRIX_DIR))?;
    ensure_readable_path(&db_path)?;

    let connection = super::open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT value, updated_at FROM repo_config WHERE key = ?1",
            params![AI_CONFIG_KEY],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn update_ai_config_record(
    repo_path: &Path,
    serialized_config: &str,
    ai_enabled: bool,
) -> CoreResult<i64> {
    super::ensure_config_storage_writable(repo_path)?;

    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let updated_at = current_timestamp(&tx)?;

    upsert_repo_config(&tx, AI_CONFIG_KEY, serialized_config, updated_at)?;
    upsert_repo_config(
        &tx,
        AI_ENABLED_KEY,
        super::bool_to_db(ai_enabled),
        updated_at,
    )?;

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

fn upsert_repo_config(
    tx: &rusqlite::Transaction<'_>,
    key: &str,
    value: &str,
    updated_at: i64,
) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO repo_config (key, value, updated_at) \
         VALUES (?1, ?2, ?3) \
         ON CONFLICT(key) DO UPDATE SET \
         value = excluded.value, updated_at = excluded.updated_at",
        params![key, value, updated_at],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(())
}

fn ensure_readable_path(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(map_metadata_error)?;
    if metadata_allows_read(&metadata) {
        Ok(())
    } else {
        Err(CoreError::permission_denied("permission denied"))
    }
}

fn map_metadata_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}

#[cfg(unix)]
fn metadata_allows_read(metadata: &Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt;

    metadata.permissions().mode() & 0o444 != 0
}

#[cfg(not(unix))]
fn metadata_allows_read(metadata: &Metadata) -> bool {
    !metadata.permissions().readonly()
}
