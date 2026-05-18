//! SQLite helpers for repository metadata.

use std::{
    fs::{File, Metadata},
    io::Read,
    path::{Path, PathBuf},
};

use rusqlite::{params, Connection, OptionalExtension, Rows, Transaction};

use crate::{
    config, CoreError, CoreResult, FileEntry, FileFilter, FileOrigin, OverviewOutput, RepoConfig,
    StorageMode,
};

mod change_log;
mod command_index;
mod delete;
mod icloud_conflicts;
mod import;
mod move_to_category;
mod note;
mod overview;
mod rename;
mod saved_search;
mod scan;
mod staging_recovery;
mod sync;
mod tags;
mod undo;
pub(crate) use change_log::list_changes;
pub(crate) use command_index::{
    count_active_command_selection_files, list_command_file_candidate_rows,
    list_recent_command_rows,
};
pub(crate) use delete::{
    insert_batch_delete_undo_action, remove_batch_delete_index_entry_row, remove_index_entry_row,
    rollback_deleted_repo_owned_file, rollback_removed_index_entry_row,
    soft_delete_batch_repo_owned_file, soft_delete_repo_owned_file, BatchDeleteUndoItem,
};
pub(crate) use icloud_conflicts::{
    list_icloud_conflict_statuses, record_icloud_conflict_resolution,
};
pub(crate) use import::{
    delete_file_row, find_active_file_by_hash, find_active_file_by_path, get_active_file_by_id,
    insert_active_indexed_import, insert_import_staging, insert_replacing_active_indexed_import,
    promote_imported_file, promote_replacing_imported_file, rollback_replacing_imported_file,
    NewImportRow, ReplacementImportRow,
};
pub(crate) use move_to_category::{
    batch_update_category_metadata_only_in_tx, batch_update_category_repo_owned_in_tx,
    correct_file_category_metadata_only, correct_repo_owned_file_category,
    insert_batch_category_undo_action_in_tx, load_batch_category_active_file,
    move_indexed_file_to_category, move_repo_owned_file_to_category,
    with_batch_category_transaction, BatchCategoryUndoItem,
};
pub(crate) use note::{read_note_content, upsert_note_and_log};
pub(crate) use overview::{
    list_overview_node_files, list_overview_node_summaries, list_overview_recent_changes,
    OverviewChangeRow, OverviewFileRow, OverviewNodeSummary,
};
pub(crate) use rename::{
    batch_update_rename_indexed_in_tx, batch_update_rename_repo_owned_in_tx,
    insert_batch_rename_undo_action_in_tx, load_batch_rename_active_file, rename_active_file,
    rename_indexed_display_name, rollback_renamed_active_file, with_batch_rename_transaction,
    BatchRenameUndoItem,
};
pub(crate) use saved_search::{
    create_saved_search_row, delete_saved_search_row, get_saved_search_row, list_saved_search_rows,
    update_saved_search_row,
};
pub(crate) use scan::*;
pub(crate) use staging_recovery::{
    delete_staging_file_row, list_protected_staging_paths, list_staging_file_rows, StagingFileRow,
};
pub(crate) use sync::*;
pub(crate) use tags::{add_tag_row, batch_add_tags_rows, list_tag_set, remove_tag_row};
pub(crate) use undo::{
    execute_undo_action_row, list_undo_action_rows, update_delete_undo_trash_path,
};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const INDEX_DB_FILE: &str = "index.db";
const SQLITE_HEADER: &[u8; 16] = b"SQLite format 3\0";

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
    'deleted','removed_from_index','restored','external_modified'
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

CREATE TABLE IF NOT EXISTS undo_actions (
  token TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  summary_json TEXT NOT NULL,
  inverse_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'executed', 'expired', 'blocked')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_undo_actions_status_time
  ON undo_actions(status, created_at DESC);

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

CREATE TABLE IF NOT EXISTS saved_searches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL COLLATE NOCASE UNIQUE,
  query_json TEXT NOT NULL,
  icon TEXT,
  color TEXT,
  pinned INTEGER NOT NULL DEFAULT 0 CHECK (pinned IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_saved_searches_sidebar
  ON saved_searches(pinned DESC, updated_at DESC, name COLLATE NOCASE ASC);

INSERT OR IGNORE INTO schema_version (version, applied_at, applied_by)
VALUES (1, strftime('%s', 'now'), 'area_matrix_core');
"#;

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

    let connection = open_repo_connection(&repo)?;
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

pub(crate) fn list_files(repo_path: String, filter: FileFilter) -> CoreResult<Vec<FileEntry>> {
    let repo = PathBuf::from(repo_path);
    let connection = open_repo_connection(&repo)?;
    let limit = filter.limit.clamp(0, 1000);
    let offset = filter.offset.max(0);
    let status_clause = list_files_status_clause(filter.include_deleted);
    let sql = format!(
        "SELECT id, path, original_name, current_name, category, size_bytes, \
         hash_sha256, storage_mode, origin, source_path, imported_at, updated_at \
         FROM files \
         WHERE {status_clause} \
           AND (?3 IS NULL OR category = ?3) \
           AND (?4 IS NULL OR imported_at >= ?4) \
           AND (?5 IS NULL OR imported_at < ?5) \
         ORDER BY imported_at DESC LIMIT ?1 OFFSET ?2"
    );
    let mut statement = connection
        .prepare(&sql)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut rows = statement
        .query(params![
            limit,
            offset,
            filter.category,
            filter.imported_after,
            filter.imported_before,
        ])
        .map_err(|error| CoreError::db(error.to_string()))?;
    collect_file_entries(&mut rows)
}

fn list_files_status_clause(include_deleted: Option<bool>) -> &'static str {
    if include_deleted.unwrap_or(false) {
        "status != 'staging'"
    } else {
        "status = 'active'"
    }
}

fn collect_file_entries(rows: &mut Rows<'_>) -> CoreResult<Vec<FileEntry>> {
    let mut files = Vec::new();
    while let Some(row) = rows
        .next()
        .map_err(|error| CoreError::db(error.to_string()))?
    {
        let storage_mode_value: String = row
            .get(7)
            .map_err(|error| CoreError::db(error.to_string()))?;
        let origin_value: String = row
            .get(8)
            .map_err(|error| CoreError::db(error.to_string()))?;
        files.push(FileEntry {
            id: row
                .get(0)
                .map_err(|error| CoreError::db(error.to_string()))?,
            path: row
                .get(1)
                .map_err(|error| CoreError::db(error.to_string()))?,
            original_name: row
                .get(2)
                .map_err(|error| CoreError::db(error.to_string()))?,
            current_name: row
                .get(3)
                .map_err(|error| CoreError::db(error.to_string()))?,
            category: row
                .get(4)
                .map_err(|error| CoreError::db(error.to_string()))?,
            size_bytes: row
                .get(5)
                .map_err(|error| CoreError::db(error.to_string()))?,
            hash_sha256: row
                .get(6)
                .map_err(|error| CoreError::db(error.to_string()))?,
            storage_mode: storage_mode_from_db(&storage_mode_value)?,
            origin: origin_from_db(&origin_value)?,
            source_path: row
                .get(9)
                .map_err(|error| CoreError::db(error.to_string()))?,
            imported_at: row
                .get(10)
                .map_err(|error| CoreError::db(error.to_string()))?,
            updated_at: row
                .get(11)
                .map_err(|error| CoreError::db(error.to_string()))?,
        });
    }
    Ok(files)
}

pub(crate) fn ensure_initialized(repo_path: &Path) -> CoreResult<()> {
    if path_exists(&db_path(repo_path))? {
        Ok(())
    } else {
        Err(CoreError::repo_not_initialized(
            "repository not initialized",
        ))
    }
}

pub(crate) fn ensure_initialized_readable(repo_path: &Path) -> CoreResult<()> {
    ensure_initialized(repo_path)?;
    let mut file =
        File::open(db_path(repo_path)).map_err(|error| CoreError::db(error.to_string()))?;
    let mut header = [0_u8; 16];
    file.read_exact(&mut header)
        .map_err(|error| CoreError::db(error.to_string()))?;
    if &header == SQLITE_HEADER {
        Ok(())
    } else {
        Err(CoreError::db("database error"))
    }
}

pub(super) fn open_repo_connection(repo_path: &Path) -> CoreResult<Connection> {
    ensure_initialized(repo_path)?;
    let connection =
        Connection::open(db_path(repo_path)).map_err(|error| CoreError::db(error.to_string()))?;
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
        locale: config_value(connection, "locale")?.unwrap_or(default.locale),
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

fn validate_config_payload(repo_path: &str, config: &RepoConfig) -> CoreResult<()> {
    if config.repo_path != repo_path || config.locale.trim().is_empty() {
        return Err(CoreError::config("configuration error"));
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

fn map_update_open_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => CoreError::config("configuration error"),
        other => other,
    }
}

fn db_path(repo_path: &Path) -> PathBuf {
    repo_path.join(AREA_MATRIX_DIR).join(INDEX_DB_FILE)
}

fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(|error| match error.kind() {
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
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
        _ => Err(CoreError::config("configuration error")),
    }
}

pub(super) fn origin_from_db(value: &str) -> CoreResult<FileOrigin> {
    match value {
        "imported" | "Imported" => Ok(FileOrigin::Imported),
        "adopted" | "Adopted" => Ok(FileOrigin::Adopted),
        "external" | "External" => Ok(FileOrigin::External),
        _ => Err(CoreError::db("database error")),
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
        _ => Err(CoreError::config("configuration error")),
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
        _ => Err(CoreError::config("configuration error")),
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
