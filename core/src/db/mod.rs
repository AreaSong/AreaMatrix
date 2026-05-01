//! SQLite helpers for repository metadata.

use std::{
    fs::Metadata,
    path::{Path, PathBuf},
};

use rusqlite::{params, Connection, OptionalExtension, Transaction};

use crate::{
    config, CoreError, CoreResult, FileEntry, FileFilter, FileOrigin, OverviewOutput, RepoConfig,
    StorageMode,
};

mod scan;
pub(crate) use scan::*;

const AREA_MATRIX_DIR: &str = ".areamatrix";
const INDEX_DB_FILE: &str = "index.db";

const INITIAL_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL,
  applied_by TEXT NOT NULL DEFAULT 'area_matrix_core'
);

CREATE TABLE IF NOT EXISTS files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT NOT NULL UNIQUE,
  original_name TEXT NOT NULL,
  current_name TEXT NOT NULL,
  category TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  hash_sha256 TEXT NOT NULL,
  storage_mode TEXT NOT NULL CHECK (storage_mode IN ('moved', 'copied', 'indexed')),
  origin TEXT NOT NULL DEFAULT 'imported'
    CHECK (origin IN ('imported', 'adopted', 'external')),
  source_path TEXT,
  imported_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('staging', 'active', 'deleted'))
);

CREATE INDEX IF NOT EXISTS idx_files_category_active
  ON files(category, imported_at DESC)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_files_hash_active
  ON files(hash_sha256)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_files_status ON files(status);
CREATE INDEX IF NOT EXISTS idx_files_imported_at ON files(imported_at DESC);

CREATE TABLE IF NOT EXISTS change_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_id INTEGER,
  action TEXT NOT NULL CHECK (action IN (
    'imported','adopted','renamed','moved','edited_note',
    'deleted','restored','external_modified'
  )),
  detail_json TEXT NOT NULL,
  occurred_at INTEGER NOT NULL,
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_changelog_time ON change_log(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_changelog_file ON change_log(file_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_changelog_action ON change_log(action, occurred_at DESC);

CREATE TABLE IF NOT EXISTS notes (
  file_id INTEGER PRIMARY KEY,
  content_md TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS tags (
  file_id INTEGER NOT NULL,
  tag TEXT NOT NULL,
  added_at INTEGER NOT NULL,
  PRIMARY KEY (file_id, tag),
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tags_tag ON tags(tag);

CREATE TABLE IF NOT EXISTS fs_event_cursor (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  last_event_id INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS scan_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK (kind IN ('adopt', 'reindex')),
  status TEXT NOT NULL CHECK (status IN (
    'running','completed','paused','failed','interrupted'
  )),
  started_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  finished_at INTEGER,
  last_path TEXT,
  inserted INTEGER NOT NULL DEFAULT 0,
  updated INTEGER NOT NULL DEFAULT 0,
  skipped INTEGER NOT NULL DEFAULT 0,
  errors_json TEXT NOT NULL DEFAULT '[]'
);

CREATE INDEX IF NOT EXISTS idx_scan_sessions_status
  ON scan_sessions(status, updated_at DESC);

CREATE TABLE IF NOT EXISTS repo_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

INSERT OR IGNORE INTO schema_version (version, applied_at, applied_by)
VALUES (1, strftime('%s', 'now'), 'area_matrix_core');
"#;

pub(crate) fn initialize_repository_db(db_path: &Path, config: &RepoConfig) -> CoreResult<()> {
    let mut connection = Connection::open(db_path).map_err(|_| CoreError::Db)?;
    configure_connection(&connection)?;
    connection
        .execute_batch(INITIAL_SCHEMA)
        .map_err(|_| CoreError::Db)?;

    let tx = connection.transaction().map_err(|_| CoreError::Db)?;
    upsert_config(&tx, config)?;
    tx.commit().map_err(|_| CoreError::Db)
}

pub(crate) fn load_config_or_default(repo_path: String) -> CoreResult<RepoConfig> {
    if repo_path.is_empty() {
        return Err(CoreError::Config);
    }

    let repo = PathBuf::from(&repo_path);
    let db_path = db_path(&repo);
    if !path_exists(&db_path)? {
        return Ok(config::default_repo_config(
            repo_path,
            OverviewOutput::GeneratedOnly,
        ));
    }

    let connection = open_repo_connection(&repo)?;
    read_config(&connection, repo_path)
}

pub(crate) fn update_config(repo_path: String, new_config: RepoConfig) -> CoreResult<()> {
    if repo_path.is_empty() {
        return Err(CoreError::Config);
    }
    validate_config_payload(&repo_path, &new_config)?;

    let repo = PathBuf::from(&repo_path);
    ensure_config_storage_writable(&repo)?;

    let mut connection = open_repo_connection(&repo).map_err(map_update_open_error)?;
    let tx = connection.transaction().map_err(|_| CoreError::Db)?;
    upsert_config(&tx, &new_config)?;
    tx.commit().map_err(|_| CoreError::Db)
}

pub(crate) fn list_files(repo_path: String, filter: FileFilter) -> CoreResult<Vec<FileEntry>> {
    let repo = PathBuf::from(repo_path);
    let connection = open_repo_connection(&repo)?;
    let include_deleted = filter.include_deleted.unwrap_or(false);
    let status_clause = if include_deleted {
        "status != 'staging'"
    } else {
        "status = 'active'"
    };
    let limit = filter.limit.clamp(0, 1000);
    let offset = filter.offset.max(0);
    let sql = format!(
        "SELECT id, path, original_name, current_name, category, size_bytes, \
         hash_sha256, storage_mode, origin, source_path, imported_at, updated_at \
         FROM files WHERE {status_clause} ORDER BY imported_at DESC LIMIT ?1 OFFSET ?2"
    );
    let mut statement = connection.prepare(&sql).map_err(|_| CoreError::Db)?;
    let mut rows = statement
        .query(params![limit, offset])
        .map_err(|_| CoreError::Db)?;
    let mut files = Vec::new();
    while let Some(row) = rows.next().map_err(|_| CoreError::Db)? {
        let storage_mode_value: String = row.get(7).map_err(|_| CoreError::Db)?;
        let origin_value: String = row.get(8).map_err(|_| CoreError::Db)?;
        files.push(FileEntry {
            id: row.get(0).map_err(|_| CoreError::Db)?,
            path: row.get(1).map_err(|_| CoreError::Db)?,
            original_name: row.get(2).map_err(|_| CoreError::Db)?,
            current_name: row.get(3).map_err(|_| CoreError::Db)?,
            category: row.get(4).map_err(|_| CoreError::Db)?,
            size_bytes: row.get(5).map_err(|_| CoreError::Db)?,
            hash_sha256: row.get(6).map_err(|_| CoreError::Db)?,
            storage_mode: storage_mode_from_db(&storage_mode_value)?,
            origin: origin_from_db(&origin_value)?,
            source_path: row.get(9).map_err(|_| CoreError::Db)?,
            imported_at: row.get(10).map_err(|_| CoreError::Db)?,
            updated_at: row.get(11).map_err(|_| CoreError::Db)?,
        });
    }
    Ok(files)
}

pub(crate) fn ensure_initialized(repo_path: &Path) -> CoreResult<()> {
    if path_exists(&db_path(repo_path))? {
        Ok(())
    } else {
        Err(CoreError::RepoNotInitialized)
    }
}

pub(super) fn open_repo_connection(repo_path: &Path) -> CoreResult<Connection> {
    ensure_initialized(repo_path)?;
    let connection = Connection::open(db_path(repo_path)).map_err(|_| CoreError::Db)?;
    configure_connection(&connection)?;
    Ok(connection)
}

fn configure_connection(connection: &Connection) -> CoreResult<()> {
    connection
        .execute_batch(
            "PRAGMA journal_mode = WAL;
             PRAGMA foreign_keys = ON;
             PRAGMA synchronous = NORMAL;
             PRAGMA temp_store = MEMORY;
             PRAGMA mmap_size = 268435456;
             PRAGMA cache_size = -65536;
             PRAGMA busy_timeout = 5000;",
        )
        .map_err(|_| CoreError::Db)
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
        locale: config_value(connection, "locale")?.unwrap_or(default.locale),
        icloud_warn: config_value(connection, "icloud_warn")?
            .map(|value| bool_from_db(&value))
            .transpose()?
            .unwrap_or(default.icloud_warn),
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
    ];

    for (key, value) in values {
        tx.execute(
            "INSERT INTO repo_config (key, value, updated_at) \
             VALUES (?1, ?2, strftime('%s', 'now')) \
             ON CONFLICT(key) DO UPDATE SET \
             value = excluded.value, updated_at = excluded.updated_at",
            params![key, value],
        )
        .map_err(|_| CoreError::Db)?;
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
        .map_err(|_| CoreError::Db)
}

fn validate_config_payload(repo_path: &str, config: &RepoConfig) -> CoreResult<()> {
    if config.repo_path != repo_path || config.locale.trim().is_empty() {
        return Err(CoreError::Config);
    }
    Ok(())
}

fn ensure_config_storage_writable(repo_path: &Path) -> CoreResult<()> {
    ensure_writable_path(&repo_path.join(AREA_MATRIX_DIR))?;
    ensure_writable_path(&db_path(repo_path))
}

fn ensure_writable_path(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(map_config_metadata_error)?;
    if metadata_allows_write(&metadata) {
        Ok(())
    } else {
        Err(CoreError::PermissionDenied)
    }
}

fn map_config_metadata_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::NotFound => CoreError::Config,
        std::io::ErrorKind::PermissionDenied => CoreError::PermissionDenied,
        std::io::ErrorKind::InvalidInput => CoreError::InvalidPath,
        _ => CoreError::Io,
    }
}

fn map_update_open_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized => CoreError::Config,
        other => other,
    }
}

fn db_path(repo_path: &Path) -> PathBuf {
    repo_path.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE)
}

fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(|error| match error.kind() {
        std::io::ErrorKind::PermissionDenied => CoreError::PermissionDenied,
        std::io::ErrorKind::InvalidInput => CoreError::InvalidPath,
        _ => CoreError::Io,
    })
}

fn storage_mode_to_db(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

pub(super) fn storage_mode_from_db(value: &str) -> CoreResult<StorageMode> {
    match value {
        "moved" | "Moved" => Ok(StorageMode::Moved),
        "copied" | "Copied" => Ok(StorageMode::Copied),
        "indexed" | "Indexed" => Ok(StorageMode::Indexed),
        _ => Err(CoreError::Config),
    }
}

pub(super) fn origin_from_db(value: &str) -> CoreResult<FileOrigin> {
    match value {
        "imported" | "Imported" => Ok(FileOrigin::Imported),
        "adopted" | "Adopted" => Ok(FileOrigin::Adopted),
        "external" | "External" => Ok(FileOrigin::External),
        _ => Err(CoreError::Db),
    }
}

fn overview_output_to_db(output: &OverviewOutput) -> &'static str {
    match output {
        OverviewOutput::GeneratedOnly => "generated_only",
        OverviewOutput::RootAreaMatrixFile => "root_areamatrix_file",
    }
}

fn overview_output_from_db(value: &str) -> CoreResult<OverviewOutput> {
    match value {
        "generated_only" | "GeneratedOnly" => Ok(OverviewOutput::GeneratedOnly),
        "root_areamatrix_file" | "RootAreaMatrixFile" => Ok(OverviewOutput::RootAreaMatrixFile),
        _ => Err(CoreError::Config),
    }
}

fn bool_to_db(value: bool) -> &'static str {
    if value {
        "true"
    } else {
        "false"
    }
}

fn bool_from_db(value: &str) -> CoreResult<bool> {
    match value {
        "true" => Ok(true),
        "false" => Ok(false),
        _ => Err(CoreError::Config),
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
