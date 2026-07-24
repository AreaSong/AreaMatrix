use std::{
    fs::Metadata,
    path::{Path, PathBuf},
};

use rusqlite::{params, Connection, OptionalExtension, Transaction};

use crate::{
    config, CoreError, CoreResult, OverviewOutput, RepoConfig, RepoConfigPatch, RepoConfigSnapshot,
};

use super::{
    bool_from_db, bool_to_db, configure_connection, db_path, open_repo_connection,
    open_repo_read_connection, open_repo_snapshot_read_connection, overview_output_from_db,
    overview_output_to_db, path_exists, storage_mode_from_db, storage_mode_to_db, AREA_MATRIX_DIR,
    INITIAL_SCHEMA,
};

pub(crate) fn initialize_repository_db(db_path: &Path, config: &RepoConfig) -> CoreResult<()> {
    let mut connection =
        Connection::open(db_path).map_err(|error| CoreError::db(error.to_string()))?;
    configure_connection(&connection)?;
    connection
        .execute_batch(INITIAL_SCHEMA)
        .map_err(|error| CoreError::db(error.to_string()))?;

    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    upsert_config(&tx, config)?;
    tx.execute(
        "INSERT INTO repo_config_revision (id, revision) VALUES (1, 1)
         ON CONFLICT(id) DO UPDATE SET revision = 1",
        [],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn load_config_or_default(repo_path: String) -> CoreResult<RepoConfig> {
    if repo_path.is_empty() {
        return Err(CoreError::config("configuration error"));
    }

    let repo = PathBuf::from(&repo_path);
    let db_path = db_path(&repo);
    if !path_exists(&db_path)? {
        return Ok(config::default_repo_config(
            repo_path,
            OverviewOutput::GeneratedOnly,
        ));
    }

    let connection = open_repo_read_connection(&repo)?;
    read_config(&connection, repo_path)
}

pub(crate) fn update_config(repo_path: String, new_config: RepoConfig) -> CoreResult<()> {
    if repo_path.is_empty() {
        return Err(CoreError::config("configuration error"));
    }
    validate_config_payload(&repo_path, &new_config)?;

    let repo = PathBuf::from(&repo_path);
    ensure_config_storage_writable(&repo)?;

    let mut connection = open_repo_connection(&repo).map_err(map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    upsert_config(&tx, &new_config)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

/// Reads a revisioned repository configuration snapshot without rewriting the
/// exact persisted locale value.
pub(crate) fn load_repo_config_snapshot_or_default(
    repo_path: String,
) -> CoreResult<RepoConfigSnapshot> {
    if repo_path.is_empty() {
        return Err(CoreError::config("configuration error"));
    }

    let repo = PathBuf::from(&repo_path);
    let db_path = db_path(&repo);
    if !path_exists(&db_path)? {
        return Ok(RepoConfigSnapshot::from_config(
            config::default_repo_config(repo_path, OverviewOutput::GeneratedOnly),
            0,
        ));
    }

    let connection = open_repo_read_connection(&repo)?;
    let config = read_config(&connection, repo_path)?;
    let revision = current_revision(&connection)?.unwrap_or(1);
    Ok(RepoConfigSnapshot::from_config(config, revision))
}

pub(crate) fn ensure_repository_locale_allows_normal_mutation(repo_path: &Path) -> CoreResult<()> {
    if super::has_unsettled_overview_regeneration(repo_path)? {
        return Err(CoreError::conflict(
            "overview regeneration recovery is required",
        ));
    }
    let connection = open_repo_snapshot_read_connection(repo_path)?;
    ensure_canonical_repository_locale(&connection)
}

pub(crate) fn ensure_repository_locale_allows_generation_preview(
    repo_path: &Path,
) -> CoreResult<()> {
    let connection = open_repo_snapshot_read_connection(repo_path)?;
    ensure_canonical_repository_locale(&connection)
}

fn ensure_canonical_repository_locale(connection: &Connection) -> CoreResult<()> {
    let raw_locale = config_value(&connection, "locale")?.unwrap_or_default();
    let snapshot = crate::RepositoryLocalePolicySnapshot::from_raw(raw_locale);
    if !snapshot.is_canonical() {
        Err(CoreError::config(
            "repository locale requires explicit canonical policy save",
        ))
    } else {
        Ok(())
    }
}

/// Applies a field-level compare-and-swap patch and returns the new snapshot.
pub(crate) fn update_repo_config_patch(
    repo_path: String,
    patch: RepoConfigPatch,
) -> CoreResult<RepoConfigSnapshot> {
    if repo_path.is_empty() {
        return Err(CoreError::config("configuration error"));
    }
    if patch.expected_revision < 1 {
        return Err(CoreError::config("configuration revision is invalid"));
    }

    let repo = PathBuf::from(&repo_path);
    ensure_config_storage_writable(&repo)?;
    let mut connection = open_repo_connection(&repo).map_err(map_update_open_error)?;
    let tx = connection
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .map_err(|error| CoreError::db(error.to_string()))?;

    let current_revision = current_revision(&tx)?
        .ok_or_else(|| CoreError::db("repository configuration revision row is missing"))?;
    if current_revision != patch.expected_revision {
        return Err(CoreError::revision_conflict(
            "repo_config",
            patch.expected_revision,
            current_revision,
        ));
    }

    let current_locale = config_value(&tx, "locale")?.unwrap_or_default();
    let locale_snapshot = crate::RepositoryLocalePolicySnapshot::from_raw(current_locale);
    let has_mutations = !patch.is_empty();
    if matches!(
        locale_snapshot.state,
        crate::RepositoryLocalePolicyState::Unsupported
    ) && !patch.is_locale_only()
    {
        return Err(CoreError::config(
            "unsupported repository locale requires explicit canonical policy save",
        ));
    }

    let timestamp = chrono::Utc::now().timestamp();
    if let Some(value) = patch.default_mode {
        upsert_config_value(&tx, "default_mode", storage_mode_to_db(&value), timestamp)?;
    }
    if let Some(value) = patch.overview_output {
        upsert_config_value(
            &tx,
            "overview_output",
            overview_output_to_db(&value),
            timestamp,
        )?;
    }
    if let Some(value) = patch.ai_enabled {
        upsert_config_value(&tx, "ai_enabled", bool_to_db(value), timestamp)?;
    }
    if let Some(value) = patch.locale_policy {
        upsert_config_value(&tx, "locale", value.as_str(), timestamp)?;
    }
    if let Some(value) = patch.icloud_warn {
        upsert_config_value(&tx, "icloud_warn", bool_to_db(value), timestamp)?;
    }
    if let Some(value) = patch.enable_extension_rules {
        upsert_config_value(&tx, "enable_extension_rules", bool_to_db(value), timestamp)?;
    }
    if let Some(value) = patch.enable_keyword_rules {
        upsert_config_value(&tx, "enable_keyword_rules", bool_to_db(value), timestamp)?;
    }
    if let Some(value) = patch.fallback_to_inbox {
        upsert_config_value(&tx, "fallback_to_inbox", bool_to_db(value), timestamp)?;
    }
    if let Some(value) = patch.allow_replace_during_import {
        upsert_config_value(
            &tx,
            "allow_replace_during_import",
            bool_to_db(value),
            timestamp,
        )?;
    }

    if has_mutations {
        tx.execute(
            "UPDATE repo_config_revision SET revision = ?1 WHERE id = 1",
            params![current_revision + 1],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    }
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;

    load_repo_config_snapshot_or_default(repo_path)
}

pub(crate) fn with_write_transaction<T>(
    repo_path: &Path,
    operation: impl FnOnce(&rusqlite::Transaction<'_>) -> CoreResult<T>,
) -> CoreResult<T> {
    ensure_config_storage_writable(repo_path)?;
    let mut connection = open_repo_connection(repo_path).map_err(map_update_open_error)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let result = operation(&tx)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(result)
}

pub(crate) fn load_repo_config_record(
    repo_path: &Path,
    key: &str,
) -> CoreResult<Option<(String, i64)>> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT value, updated_at FROM repo_config WHERE key = ?1",
            params![key],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn upsert_repo_config_record(
    tx: &Transaction<'_>,
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
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn read_config(connection: &Connection, repo_path: String) -> CoreResult<RepoConfig> {
    let default = config::default_repo_config(repo_path, OverviewOutput::GeneratedOnly);
    Ok(RepoConfig {
        repo_path: config_value(connection, "repo_path")?.unwrap_or(default.repo_path),
        default_mode: config_value(connection, "default_mode")?
            .map(|value| storage_mode_from_db(&value))
            .transpose()?
            .unwrap_or(default.default_mode),
        overview_output: config_value(connection, "overview_output")?
            .map(|value| overview_output_from_db(&value))
            .transpose()?
            .unwrap_or(default.overview_output),
        ai_enabled: config_value(connection, "ai_enabled")?
            .map(|value| bool_from_db(&value))
            .transpose()?
            .unwrap_or(default.ai_enabled),
        // An initialized legacy repository without a locale row is unknown.
        // Only an uninitialized path receives the new-repository default.
        locale: config_value(connection, "locale")?.unwrap_or_default(),
        icloud_warn: config_value(connection, "icloud_warn")?
            .map(|value| bool_from_db(&value))
            .transpose()?
            .unwrap_or(default.icloud_warn),
        enable_extension_rules: config_value(connection, "enable_extension_rules")?
            .map(|value| bool_from_db(&value))
            .transpose()?
            .unwrap_or(default.enable_extension_rules),
        enable_keyword_rules: config_value(connection, "enable_keyword_rules")?
            .map(|value| bool_from_db(&value))
            .transpose()?
            .unwrap_or(default.enable_keyword_rules),
        fallback_to_inbox: config_value(connection, "fallback_to_inbox")?
            .map(|value| bool_from_db(&value))
            .transpose()?
            .unwrap_or(default.fallback_to_inbox),
        allow_replace_during_import: config_value(connection, "allow_replace_during_import")?
            .map(|value| bool_from_db(&value))
            .transpose()?
            .unwrap_or(default.allow_replace_during_import),
    })
}

fn upsert_config(tx: &Transaction<'_>, config: &RepoConfig) -> CoreResult<()> {
    let values = [
        ("repo_path", config.repo_path.as_str()),
        ("default_mode", storage_mode_to_db(&config.default_mode)),
        (
            "overview_output",
            overview_output_to_db(&config.overview_output),
        ),
        ("ai_enabled", bool_to_db(config.ai_enabled)),
        ("locale", config.locale.as_str()),
        ("icloud_warn", bool_to_db(config.icloud_warn)),
        (
            "enable_extension_rules",
            bool_to_db(config.enable_extension_rules),
        ),
        (
            "enable_keyword_rules",
            bool_to_db(config.enable_keyword_rules),
        ),
        ("fallback_to_inbox", bool_to_db(config.fallback_to_inbox)),
        (
            "allow_replace_during_import",
            bool_to_db(config.allow_replace_during_import),
        ),
    ];

    for (key, value) in values {
        tx.execute(
            "INSERT INTO repo_config (key, value, updated_at) \
             VALUES (?1, ?2, strftime('%s', 'now')) \
             ON CONFLICT(key) DO UPDATE SET \
             value = excluded.value, updated_at = excluded.updated_at",
            params![key, value],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    }
    Ok(())
}

fn config_value(connection: &Connection, key: &str) -> CoreResult<Option<String>> {
    connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn current_revision(connection: &Connection) -> CoreResult<Option<i64>> {
    connection
        .query_row(
            "SELECT revision FROM repo_config_revision WHERE id = 1",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn upsert_config_value(
    tx: &Transaction<'_>,
    key: &str,
    value: &str,
    updated_at: i64,
) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO repo_config (key, value, updated_at)
         VALUES (?1, ?2, ?3)
         ON CONFLICT(key) DO UPDATE SET
           value = excluded.value,
           updated_at = excluded.updated_at",
        params![key, value, updated_at],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn validate_config_payload(repo_path: &str, config: &RepoConfig) -> CoreResult<()> {
    if config.repo_path != repo_path || config.locale.trim().is_empty() {
        return Err(CoreError::config("configuration error"));
    }
    Ok(())
}

pub(crate) fn ensure_config_storage_writable(repo_path: &Path) -> CoreResult<()> {
    ensure_writable_path(&repo_path.join(AREA_MATRIX_DIR))?;
    ensure_writable_path(&db_path(repo_path))?;
    if super::has_unsettled_overview_regeneration(repo_path)? {
        return Err(CoreError::conflict(
            "overview regeneration recovery is required",
        ));
    }
    Ok(())
}

fn ensure_writable_path(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(map_config_metadata_error)?;
    if metadata_allows_write(&metadata) {
        Ok(())
    } else {
        Err(CoreError::permission_denied("permission denied"))
    }
}

fn map_config_metadata_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::NotFound => CoreError::config("configuration error"),
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}

pub(crate) fn map_update_open_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => CoreError::config("configuration error"),
        other => other,
    }
}

#[cfg(unix)]
fn metadata_allows_write(metadata: &Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt;

    metadata.permissions().mode() & 0o222 != 0
}

#[cfg(not(unix))]
fn metadata_allows_write(metadata: &Metadata) -> bool {
    !metadata.permissions().readonly()
}
