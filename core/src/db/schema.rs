use std::{collections::HashSet, fs, path::Path};

use rusqlite::{params, Connection, Transaction};

use crate::{CoreError, CoreResult};

use super::connection::{db_path, path_exists, INDEX_DB_FILE};

pub(super) const LATEST_SCHEMA_VERSION: i64 = 2;
const SCAN_SESSION_V2_COLUMNS: &[(&str, &str)] = &[
    ("missing", "missing INTEGER NOT NULL DEFAULT 0"),
    ("conflicts", "conflicts INTEGER NOT NULL DEFAULT 0"),
    ("unreadable", "unreadable INTEGER NOT NULL DEFAULT 0"),
    ("unknown", "unknown INTEGER NOT NULL DEFAULT 0"),
];

pub(crate) const INITIAL_SCHEMA: &str = r#"
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
  missing INTEGER NOT NULL DEFAULT 0,
  conflicts INTEGER NOT NULL DEFAULT 0,
  unreadable INTEGER NOT NULL DEFAULT 0,
  unknown INTEGER NOT NULL DEFAULT 0,
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
VALUES (2, strftime('%s', 'now'), 'area_matrix_core');
"#;

pub(super) fn run_schema_migrations(
    connection: &mut Connection,
    repo_path: &Path,
) -> CoreResult<()> {
    let current = current_schema_version(connection)?;
    let scan_session_columns = table_columns(connection, "scan_sessions")?;
    let missing_scan_columns = SCAN_SESSION_V2_COLUMNS
        .iter()
        .filter(|(name, _)| !scan_session_columns.contains(*name))
        .copied()
        .collect::<Vec<_>>();

    if current >= LATEST_SCHEMA_VERSION && missing_scan_columns.is_empty() {
        return Ok(());
    }

    checkpoint_wal(connection)?;
    create_pre_migration_backup(repo_path, LATEST_SCHEMA_VERSION)?;
    let schema_version_has_applied_by =
        table_columns(connection, "schema_version")?.contains("applied_by");

    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    for (_, definition) in missing_scan_columns {
        tx.execute(
            &format!("ALTER TABLE scan_sessions ADD COLUMN {definition}"),
            [],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    }
    insert_schema_version(&tx, LATEST_SCHEMA_VERSION, schema_version_has_applied_by)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn current_schema_version(connection: &Connection) -> CoreResult<i64> {
    connection
        .query_row(
            "SELECT COALESCE(MAX(version), 0) FROM schema_version",
            [],
            |row| row.get(0),
        )
        .map_err(|error| CoreError::db(error.to_string()))
}

fn table_columns(connection: &Connection, table_name: &str) -> CoreResult<HashSet<String>> {
    let mut statement = connection
        .prepare(&format!("PRAGMA table_info({table_name})"))
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut columns = HashSet::new();
    for row in rows {
        columns.insert(row.map_err(|error| CoreError::db(error.to_string()))?);
    }
    Ok(columns)
}

fn checkpoint_wal(connection: &Connection) -> CoreResult<()> {
    connection
        .execute_batch("PRAGMA wal_checkpoint(FULL);")
        .map_err(|error| CoreError::db(error.to_string()))
}

fn create_pre_migration_backup(repo_path: &Path, target_version: i64) -> CoreResult<()> {
    let source = db_path(repo_path);
    let backup = source.with_file_name(format!("{INDEX_DB_FILE}.pre-v{target_version}.bak"));
    if path_exists(&backup)? {
        return Ok(());
    }
    fs::copy(&source, &backup)
        .map(|_| ())
        .map_err(|error| CoreError::db(error.to_string()))
}

fn insert_schema_version(
    tx: &Transaction<'_>,
    version: i64,
    has_applied_by: bool,
) -> CoreResult<()> {
    let sql = if has_applied_by {
        "INSERT OR IGNORE INTO schema_version (version, applied_at, applied_by)
         VALUES (?1, strftime('%s', 'now'), 'area_matrix_core')"
    } else {
        "INSERT OR IGNORE INTO schema_version (version, applied_at)
         VALUES (?1, strftime('%s', 'now'))"
    };
    tx.execute(sql, params![version])
        .map(|_| ())
        .map_err(|error| CoreError::db(error.to_string()))
}
