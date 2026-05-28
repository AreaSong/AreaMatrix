//! Repository config-table storage for C3-03 remote provider metadata.

use std::path::Path;

use rusqlite::{params, OptionalExtension};

use crate::{CoreError, CoreResult};

const REMOTE_PROVIDER_CONFIG_KEY: &str = "remote_provider_config";
const REMOTE_PROVIDER_PENDING_TEST_KEY: &str = "remote_provider_pending_verification";

pub(crate) fn save_remote_provider_test_record(
    repo_path: &Path,
    serialized_pending: &str,
) -> CoreResult<i64> {
    super::ensure_config_storage_writable(repo_path)?;

    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let updated_at = current_timestamp(&tx)?;

    upsert_repo_config(
        &tx,
        REMOTE_PROVIDER_PENDING_TEST_KEY,
        serialized_pending,
        updated_at,
    )?;

    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(updated_at)
}

pub(crate) fn load_remote_provider_test_record(
    repo_path: &Path,
) -> CoreResult<Option<(String, i64)>> {
    load_repo_config_value(repo_path, REMOTE_PROVIDER_PENDING_TEST_KEY)
}

pub(crate) fn load_remote_provider_config_record(
    repo_path: &Path,
) -> CoreResult<Option<(String, i64)>> {
    load_repo_config_value(repo_path, REMOTE_PROVIDER_CONFIG_KEY)
}

pub(crate) fn update_remote_provider_config_record(
    repo_path: &Path,
    serialized_config: &str,
) -> CoreResult<i64> {
    super::ensure_config_storage_writable(repo_path)?;

    let mut connection =
        super::open_repo_connection(repo_path).map_err(super::map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let updated_at = current_timestamp(&tx)?;

    upsert_repo_config(
        &tx,
        REMOTE_PROVIDER_CONFIG_KEY,
        serialized_config,
        updated_at,
    )?;
    tx.execute(
        "DELETE FROM repo_config WHERE key = ?1",
        params![REMOTE_PROVIDER_PENDING_TEST_KEY],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;

    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(updated_at)
}

fn load_repo_config_value(repo_path: &Path, key: &str) -> CoreResult<Option<(String, i64)>> {
    let connection = super::open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT value, updated_at FROM repo_config WHERE key = ?1",
            params![key],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
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
