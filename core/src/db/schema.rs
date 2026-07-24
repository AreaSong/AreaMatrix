use std::{
    collections::HashSet,
    fs::{self, File, OpenOptions},
    io::{self, BufReader, BufWriter, Write},
    path::{Path, PathBuf},
};

use rusqlite::{params, Connection, OptionalExtension, Transaction, TransactionBehavior};

use crate::{CoreError, CoreResult};

use super::connection::{db_path, INDEX_DB_FILE};

pub(super) const LATEST_SCHEMA_VERSION: i64 = 3;
const RECEIPT_INSERT_TRIGGER: &str = "external_sync_receipts_require_locale_insert";
const RECEIPT_UPDATE_TRIGGER: &str = "external_sync_receipts_protect_locale_update";
const BACKUP_COPY_BUFFER_BYTES: usize = 64 * 1024;
const SCAN_SESSION_V2_COLUMNS: &[(&str, &str)] = &[
    ("missing", "missing INTEGER NOT NULL DEFAULT 0"),
    ("conflicts", "conflicts INTEGER NOT NULL DEFAULT 0"),
    ("unreadable", "unreadable INTEGER NOT NULL DEFAULT 0"),
    ("unknown", "unknown INTEGER NOT NULL DEFAULT 0"),
    (
        "operation_id",
        "operation_id TEXT REFERENCES recoverable_operations(operation_id)",
    ),
];
const OVERVIEW_ITEM_V3_COLUMNS: &[(&str, &str)] = &[
    (
        "new_exists",
        "new_exists INTEGER NOT NULL DEFAULT 1 CHECK (new_exists IN (0, 1))",
    ),
    (
        "old_provenance_operation_id",
        "old_provenance_operation_id TEXT",
    ),
    (
        "old_provenance_content_locale",
        "old_provenance_content_locale TEXT",
    ),
    (
        "old_provenance_format_version",
        "old_provenance_format_version INTEGER",
    ),
    (
        "old_provenance_repository_revision",
        "old_provenance_repository_revision INTEGER",
    ),
    (
        "old_provenance_content_sha256",
        "old_provenance_content_sha256 TEXT",
    ),
    (
        "old_provenance_generated_at",
        "old_provenance_generated_at INTEGER",
    ),
];
const RECOVERABLE_OPERATION_V3_COLUMNS: &[(&str, &str)] = &[("error_code", "error_code TEXT")];

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

CREATE TABLE IF NOT EXISTS external_sync_receipts (
  event_id INTEGER NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('created', 'renamed', 'removed', 'modified')),
  path TEXT NOT NULL,
  file_id INTEGER,
  previous_category TEXT,
  current_category TEXT,
  content_locale TEXT CHECK (content_locale IN ('zh-Hans', 'en')),
  applied_at INTEGER NOT NULL,
  PRIMARY KEY (event_id, kind, path)
);

CREATE INDEX IF NOT EXISTS idx_external_sync_receipts_applied
  ON external_sync_receipts(applied_at DESC);

CREATE TRIGGER IF NOT EXISTS external_sync_receipts_require_locale_insert
BEFORE INSERT ON external_sync_receipts
WHEN NEW.content_locale IS NULL
BEGIN
  SELECT RAISE(ABORT, 'external sync receipt locale is required');
END;

CREATE TRIGGER IF NOT EXISTS external_sync_receipts_protect_locale_update
BEFORE UPDATE OF content_locale ON external_sync_receipts
WHEN NEW.content_locale IS NULL
  OR OLD.content_locale IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'external sync receipt locale is immutable');
END;

CREATE TABLE IF NOT EXISTS recoverable_operations (
  operation_id TEXT PRIMARY KEY,
  retry_of_operation_id TEXT,
  operation_code TEXT NOT NULL,
  operation_payload_json TEXT NOT NULL,
  content_locale TEXT CHECK (content_locale IS NULL OR content_locale IN ('zh-Hans', 'en')),
  repository_revision INTEGER NOT NULL CHECK (repository_revision >= 0),
  format_contract_version INTEGER NOT NULL CHECK (format_contract_version >= 1),
  target_set_hash TEXT,
  status TEXT NOT NULL CHECK (status IN (
    'running','staging','ready_to_commit','committing','completed',
    'rollback_required','rolled_back','failed','canceled'
  )),
  run_sequence INTEGER NOT NULL DEFAULT 1 CHECK (run_sequence >= 1),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  finished_at INTEGER,
  error_code TEXT,
  FOREIGN KEY (retry_of_operation_id) REFERENCES recoverable_operations(operation_id)
);

CREATE INDEX IF NOT EXISTS idx_recoverable_operations_status
  ON recoverable_operations(status, updated_at DESC);

CREATE TABLE IF NOT EXISTS overview_regeneration_items (
  operation_id TEXT NOT NULL,
  relative_path TEXT NOT NULL,
  target_kind TEXT NOT NULL CHECK (target_kind IN ('generated','managed_root')),
  old_exists INTEGER NOT NULL CHECK (old_exists IN (0, 1)),
  old_sha256 TEXT,
  new_exists INTEGER NOT NULL DEFAULT 1 CHECK (new_exists IN (0, 1)),
  new_sha256 TEXT NOT NULL,
  staging_relative_path TEXT NOT NULL,
  backup_relative_path TEXT,
  old_provenance_operation_id TEXT,
  old_provenance_content_locale TEXT,
  old_provenance_format_version INTEGER,
  old_provenance_repository_revision INTEGER,
  old_provenance_content_sha256 TEXT,
  old_provenance_generated_at INTEGER,
  state TEXT NOT NULL CHECK (state IN ('planned','staged','applied','restored')),
  PRIMARY KEY (operation_id, relative_path),
  FOREIGN KEY (operation_id) REFERENCES recoverable_operations(operation_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS overview_provenance (
  relative_path TEXT PRIMARY KEY,
  operation_id TEXT NOT NULL,
  content_locale TEXT NOT NULL CHECK (content_locale IN ('zh-Hans', 'en')),
  format_contract_version INTEGER NOT NULL CHECK (format_contract_version >= 1),
  repository_revision INTEGER NOT NULL CHECK (repository_revision >= 0),
  content_sha256 TEXT NOT NULL,
  generated_at INTEGER NOT NULL,
  FOREIGN KEY (operation_id) REFERENCES recoverable_operations(operation_id)
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
  errors_json TEXT NOT NULL DEFAULT '[]',
  operation_id TEXT REFERENCES recoverable_operations(operation_id)
);

CREATE INDEX IF NOT EXISTS idx_scan_sessions_status
  ON scan_sessions(status, updated_at DESC);

CREATE TABLE IF NOT EXISTS repo_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS repo_config_revision (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  revision INTEGER NOT NULL CHECK (revision >= 1)
);

INSERT OR IGNORE INTO repo_config_revision (id, revision) VALUES (1, 1);

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
VALUES (3, strftime('%s', 'now'), 'area_matrix_core');
"#;

pub(super) fn run_schema_migrations(
    connection: &mut Connection,
    repo_path: &Path,
) -> CoreResult<()> {
    let current = current_schema_version(connection)?;
    if current > LATEST_SCHEMA_VERSION {
        return Err(CoreError::db("database schema is newer than this Core"));
    }

    let scan_session_columns = table_columns(connection, "scan_sessions")?;
    let missing_scan_columns = SCAN_SESSION_V2_COLUMNS
        .iter()
        .filter(|(name, _)| !scan_session_columns.contains(*name))
        .copied()
        .collect::<Vec<_>>();
    let receipt_state = receipt_schema_state(connection)?;
    let config_revision_valid = repo_config_revision_is_valid(connection)?;
    let operation_schema_valid = recoverable_operation_schema_is_valid(connection)?;
    let recoverable_operation_columns = table_columns(connection, "recoverable_operations")?;
    let missing_recoverable_operation_columns = if recoverable_operation_columns.is_empty() {
        Vec::new()
    } else {
        RECOVERABLE_OPERATION_V3_COLUMNS
            .iter()
            .filter(|(name, _)| !recoverable_operation_columns.contains(*name))
            .copied()
            .collect::<Vec<_>>()
    };
    let overview_item_columns = table_columns(connection, "overview_regeneration_items")?;
    let missing_overview_item_columns = if overview_item_columns.is_empty() {
        Vec::new()
    } else {
        OVERVIEW_ITEM_V3_COLUMNS
            .iter()
            .filter(|(name, _)| !overview_item_columns.contains(*name))
            .copied()
            .collect::<Vec<_>>()
    };

    if current >= LATEST_SCHEMA_VERSION
        && missing_scan_columns.is_empty()
        && receipt_state.is_valid()
        && config_revision_valid
        && operation_schema_valid
        && missing_recoverable_operation_columns.is_empty()
        && missing_overview_item_columns.is_empty()
    {
        return Ok(());
    }

    checkpoint_wal(connection)?;
    let schema_version_has_applied_by =
        table_columns(connection, "schema_version")?.contains("applied_by");

    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|error| CoreError::db(error.to_string()))?;
    create_pre_migration_backup(repo_path, LATEST_SCHEMA_VERSION)?;
    install_recoverable_operation_schema(&tx)?;
    for (_, definition) in missing_recoverable_operation_columns {
        tx.execute(
            &format!("ALTER TABLE recoverable_operations ADD COLUMN {definition}"),
            [],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    }
    for (_, definition) in missing_overview_item_columns {
        tx.execute(
            &format!("ALTER TABLE overview_regeneration_items ADD COLUMN {definition}"),
            [],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    }
    for (_, definition) in missing_scan_columns {
        tx.execute(
            &format!("ALTER TABLE scan_sessions ADD COLUMN {definition}"),
            [],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    }
    migrate_receipt_schema(&tx, &receipt_state)?;
    install_receipt_locale_triggers(&tx)?;
    install_repo_config_revision(&tx)?;
    insert_schema_version(&tx, LATEST_SCHEMA_VERSION, schema_version_has_applied_by)?;
    validate_receipt_schema(&tx)?;
    validate_repo_config_revision(&tx)?;
    validate_recoverable_operation_schema(&tx)?;
    validate_database_integrity(&tx)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    validate_receipt_schema(connection)?;
    validate_repo_config_revision(connection)?;
    validate_recoverable_operation_schema(connection)?;
    validate_database_integrity(connection)
}

fn install_recoverable_operation_schema(tx: &Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS recoverable_operations (
           operation_id TEXT PRIMARY KEY,
           retry_of_operation_id TEXT,
           operation_code TEXT NOT NULL,
           operation_payload_json TEXT NOT NULL,
           content_locale TEXT CHECK (content_locale IS NULL OR content_locale IN ('zh-Hans', 'en')),
           repository_revision INTEGER NOT NULL CHECK (repository_revision >= 0),
           format_contract_version INTEGER NOT NULL CHECK (format_contract_version >= 1),
           target_set_hash TEXT,
           status TEXT NOT NULL CHECK (status IN (
             'running','staging','ready_to_commit','committing','completed',
             'rollback_required','rolled_back','failed','canceled'
           )),
           run_sequence INTEGER NOT NULL DEFAULT 1 CHECK (run_sequence >= 1),
           created_at INTEGER NOT NULL,
           updated_at INTEGER NOT NULL,
           finished_at INTEGER,
           error_code TEXT,
           FOREIGN KEY (retry_of_operation_id) REFERENCES recoverable_operations(operation_id)
         );
         CREATE INDEX IF NOT EXISTS idx_recoverable_operations_status
           ON recoverable_operations(status, updated_at DESC);
         CREATE TABLE IF NOT EXISTS overview_regeneration_items (
           operation_id TEXT NOT NULL,
           relative_path TEXT NOT NULL,
           target_kind TEXT NOT NULL CHECK (target_kind IN ('generated','managed_root')),
           old_exists INTEGER NOT NULL CHECK (old_exists IN (0, 1)),
           old_sha256 TEXT,
           new_exists INTEGER NOT NULL DEFAULT 1 CHECK (new_exists IN (0, 1)),
           new_sha256 TEXT NOT NULL,
           staging_relative_path TEXT NOT NULL,
           backup_relative_path TEXT,
           old_provenance_operation_id TEXT,
           old_provenance_content_locale TEXT,
           old_provenance_format_version INTEGER,
           old_provenance_repository_revision INTEGER,
           old_provenance_content_sha256 TEXT,
           old_provenance_generated_at INTEGER,
           state TEXT NOT NULL CHECK (state IN ('planned','staged','applied','restored')),
           PRIMARY KEY (operation_id, relative_path),
           FOREIGN KEY (operation_id) REFERENCES recoverable_operations(operation_id) ON DELETE CASCADE
         );
         CREATE TABLE IF NOT EXISTS overview_provenance (
           relative_path TEXT PRIMARY KEY,
           operation_id TEXT NOT NULL,
           content_locale TEXT NOT NULL CHECK (content_locale IN ('zh-Hans', 'en')),
           format_contract_version INTEGER NOT NULL CHECK (format_contract_version >= 1),
           repository_revision INTEGER NOT NULL CHECK (repository_revision >= 0),
           content_sha256 TEXT NOT NULL,
           generated_at INTEGER NOT NULL,
           FOREIGN KEY (operation_id) REFERENCES recoverable_operations(operation_id)
         );",
    )
    .map_err(|error| CoreError::db(error.to_string()))
}

fn recoverable_operation_schema_is_valid(connection: &Connection) -> CoreResult<bool> {
    let required = [
        ("recoverable_operations", "operation_id"),
        ("recoverable_operations", "operation_payload_json"),
        ("recoverable_operations", "content_locale"),
        ("recoverable_operations", "run_sequence"),
        ("recoverable_operations", "error_code"),
        ("overview_regeneration_items", "relative_path"),
        ("overview_regeneration_items", "new_exists"),
        ("overview_regeneration_items", "new_sha256"),
        (
            "overview_regeneration_items",
            "old_provenance_content_sha256",
        ),
        ("overview_provenance", "content_sha256"),
        ("overview_provenance", "format_contract_version"),
    ];
    for (table, column) in required {
        if !table_columns(connection, table)?.contains(column) {
            return Ok(false);
        }
    }
    Ok(true)
}

fn validate_recoverable_operation_schema(connection: &Connection) -> CoreResult<()> {
    if recoverable_operation_schema_is_valid(connection)? {
        Ok(())
    } else {
        Err(CoreError::db("recoverable operation schema is incomplete"))
    }
}

fn install_repo_config_revision(tx: &Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS repo_config_revision (
           id INTEGER PRIMARY KEY CHECK (id = 1),
           revision INTEGER NOT NULL CHECK (revision >= 1)
         );
         INSERT OR IGNORE INTO repo_config_revision (id, revision) VALUES (1, 1);",
    )
    .map_err(|error| CoreError::db(error.to_string()))
}

fn repo_config_revision_is_valid(connection: &Connection) -> CoreResult<bool> {
    if table_columns(connection, "repo_config_revision")?.is_empty() {
        return Ok(false);
    }
    let row: Option<i64> = connection
        .query_row(
            "SELECT revision FROM repo_config_revision WHERE id = 1",
            [],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(row.is_some_and(|revision| revision >= 1))
}

fn validate_repo_config_revision(connection: &Connection) -> CoreResult<()> {
    if repo_config_revision_is_valid(connection)? {
        Ok(())
    } else {
        Err(CoreError::db(
            "repository configuration revision schema is incomplete",
        ))
    }
}

fn validate_database_integrity(connection: &Connection) -> CoreResult<()> {
    let integrity: String = connection
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .map_err(|error| CoreError::db(error.to_string()))?;
    if integrity != "ok" {
        return Err(CoreError::db(format!(
            "database integrity check failed: {integrity}"
        )));
    }

    let foreign_key_violation: Option<String> = connection
        .query_row("PRAGMA foreign_key_check", [], |row| row.get(0))
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    if foreign_key_violation.is_some() {
        return Err(CoreError::db("database foreign key check failed"));
    }
    Ok(())
}

#[derive(Debug)]
struct ReceiptSchemaState {
    columns: HashSet<String>,
    has_locale_check: bool,
    has_insert_trigger: bool,
    has_update_trigger: bool,
}

impl ReceiptSchemaState {
    fn is_valid(&self) -> bool {
        self.columns.contains("content_locale")
            && self.has_locale_check
            && self.has_insert_trigger
            && self.has_update_trigger
    }
}

fn receipt_schema_state(connection: &Connection) -> CoreResult<ReceiptSchemaState> {
    let columns = table_columns(connection, "external_sync_receipts")?;
    let table_sql =
        schema_object_sql(connection, "table", "external_sync_receipts")?.unwrap_or_default();
    Ok(ReceiptSchemaState {
        columns,
        has_locale_check: normalized_sql(&table_sql)
            .contains("check(content_localein('zh-hans','en'))"),
        has_insert_trigger: schema_object_sql(connection, "trigger", RECEIPT_INSERT_TRIGGER)?
            .is_some(),
        has_update_trigger: schema_object_sql(connection, "trigger", RECEIPT_UPDATE_TRIGGER)?
            .is_some(),
    })
}

fn schema_object_sql(
    connection: &Connection,
    object_type: &str,
    name: &str,
) -> CoreResult<Option<String>> {
    connection
        .query_row(
            "SELECT sql FROM sqlite_master WHERE type = ?1 AND name = ?2",
            params![object_type, name],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn normalized_sql(sql: &str) -> String {
    sql.chars()
        .filter(|character| !character.is_whitespace())
        .flat_map(char::to_lowercase)
        .collect()
}

fn migrate_receipt_schema(tx: &Transaction<'_>, state: &ReceiptSchemaState) -> CoreResult<()> {
    if state.columns.is_empty() {
        create_legacy_compatible_receipt_table(tx)?;
    } else if !state.columns.contains("content_locale") {
        tx.execute(
            "ALTER TABLE external_sync_receipts
             ADD COLUMN content_locale TEXT CHECK (content_locale IN ('zh-Hans', 'en'))",
            [],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    } else if !state.has_locale_check {
        rebuild_receipt_table_with_locale_check(tx)?;
    }
    Ok(())
}

fn create_legacy_compatible_receipt_table(tx: &Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "CREATE TABLE external_sync_receipts (
           event_id INTEGER NOT NULL,
           kind TEXT NOT NULL CHECK (kind IN ('created', 'renamed', 'removed', 'modified')),
           path TEXT NOT NULL,
           file_id INTEGER,
           previous_category TEXT,
           current_category TEXT,
           content_locale TEXT CHECK (content_locale IN ('zh-Hans', 'en')),
           applied_at INTEGER NOT NULL,
           PRIMARY KEY (event_id, kind, path)
         );
         CREATE INDEX idx_external_sync_receipts_applied
           ON external_sync_receipts(applied_at DESC);",
    )
    .map_err(|error| CoreError::db(error.to_string()))
}

fn rebuild_receipt_table_with_locale_check(tx: &Transaction<'_>) -> CoreResult<()> {
    let invalid_count: i64 = tx
        .query_row(
            "SELECT COUNT(*) FROM external_sync_receipts
             WHERE content_locale IS NOT NULL
               AND content_locale NOT IN ('zh-Hans', 'en')",
            [],
            |row| row.get(0),
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if invalid_count != 0 {
        return Err(CoreError::db(
            "external sync receipt locale provenance is invalid",
        ));
    }

    tx.execute_batch(
        "ALTER TABLE external_sync_receipts
           RENAME TO external_sync_receipts_before_v3;
         CREATE TABLE external_sync_receipts (
           event_id INTEGER NOT NULL,
           kind TEXT NOT NULL CHECK (kind IN ('created', 'renamed', 'removed', 'modified')),
           path TEXT NOT NULL,
           file_id INTEGER,
           previous_category TEXT,
           current_category TEXT,
           content_locale TEXT CHECK (content_locale IN ('zh-Hans', 'en')),
           applied_at INTEGER NOT NULL,
           PRIMARY KEY (event_id, kind, path)
         );
         INSERT INTO external_sync_receipts (
           event_id, kind, path, file_id, previous_category, current_category,
           content_locale, applied_at
         )
         SELECT event_id, kind, path, file_id, previous_category, current_category,
                content_locale, applied_at
         FROM external_sync_receipts_before_v3;
         DROP TABLE external_sync_receipts_before_v3;
         CREATE INDEX idx_external_sync_receipts_applied
           ON external_sync_receipts(applied_at DESC);",
    )
    .map_err(|error| CoreError::db(error.to_string()))
}

fn install_receipt_locale_triggers(tx: &Transaction<'_>) -> CoreResult<()> {
    tx.execute_batch(
        "DROP TRIGGER IF EXISTS external_sync_receipts_require_locale_insert;
         DROP TRIGGER IF EXISTS external_sync_receipts_protect_locale_update;
         CREATE TRIGGER external_sync_receipts_require_locale_insert
         BEFORE INSERT ON external_sync_receipts
         WHEN NEW.content_locale IS NULL
         BEGIN
           SELECT RAISE(ABORT, 'external sync receipt locale is required');
         END;
         CREATE TRIGGER external_sync_receipts_protect_locale_update
         BEFORE UPDATE OF content_locale ON external_sync_receipts
         WHEN NEW.content_locale IS NULL
           OR OLD.content_locale IS NOT NULL
         BEGIN
           SELECT RAISE(ABORT, 'external sync receipt locale is immutable');
         END;",
    )
    .map_err(|error| CoreError::db(error.to_string()))
}

fn validate_receipt_schema(connection: &Connection) -> CoreResult<()> {
    let state = receipt_schema_state(connection)?;
    if !state.is_valid() {
        return Err(CoreError::db(
            "external sync receipt locale schema is incomplete",
        ));
    }
    let invalid_count: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM external_sync_receipts
             WHERE content_locale IS NOT NULL
               AND content_locale NOT IN ('zh-Hans', 'en')",
            [],
            |row| row.get(0),
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if invalid_count == 0 {
        Ok(())
    } else {
        Err(CoreError::db(
            "external sync receipt locale provenance is invalid",
        ))
    }
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

fn create_pre_migration_backup(repo_path: &Path, target_version: i64) -> CoreResult<PathBuf> {
    let source = db_path(repo_path);
    let metadata =
        fs::symlink_metadata(&source).map_err(|error| CoreError::db(error.to_string()))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(CoreError::db(
            "database backup source is not a regular file",
        ));
    }

    let temp = create_backup_temp_path(&source, target_version)?;
    let result = write_synced_backup_temp(&source, &temp, &metadata)
        .and_then(|()| publish_backup_without_overwrite(&source, &temp, target_version));
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

fn create_backup_temp_path(source: &Path, target_version: i64) -> CoreResult<PathBuf> {
    for attempt in 0..1000_u32 {
        let candidate = source.with_file_name(format!(
            "{INDEX_DB_FILE}.pre-v{target_version}.tmp-{}-{attempt}",
            std::process::id()
        ));
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&candidate)
        {
            Ok(_) => return Ok(candidate),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(CoreError::db(error.to_string())),
        }
    }
    Err(CoreError::db(
        "unable to allocate migration backup temp file",
    ))
}

fn write_synced_backup_temp(source: &Path, temp: &Path, metadata: &fs::Metadata) -> CoreResult<()> {
    let source_file = File::open(source).map_err(|error| CoreError::db(error.to_string()))?;
    let temp_file = OpenOptions::new()
        .write(true)
        .truncate(true)
        .open(temp)
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut reader = BufReader::with_capacity(BACKUP_COPY_BUFFER_BYTES, source_file);
    let mut writer = BufWriter::with_capacity(BACKUP_COPY_BUFFER_BYTES, temp_file);
    io::copy(&mut reader, &mut writer).map_err(|error| CoreError::db(error.to_string()))?;
    writer
        .flush()
        .map_err(|error| CoreError::db(error.to_string()))?;
    writer
        .get_ref()
        .sync_all()
        .map_err(|error| CoreError::db(error.to_string()))?;
    fs::set_permissions(temp, metadata.permissions())
        .map_err(|error| CoreError::db(error.to_string()))
}

fn publish_backup_without_overwrite(
    source: &Path,
    temp: &Path,
    target_version: i64,
) -> CoreResult<PathBuf> {
    for sequence in 0..1000_u32 {
        let suffix = if sequence == 0 {
            String::new()
        } else {
            format!(".{sequence}")
        };
        let target =
            source.with_file_name(format!("{INDEX_DB_FILE}.pre-v{target_version}{suffix}.bak"));
        match fs::hard_link(temp, &target) {
            Ok(()) => {
                fs::remove_file(temp).map_err(|error| CoreError::db(error.to_string()))?;
                sync_parent_directory(source)?;
                return Ok(target);
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(CoreError::db(error.to_string())),
        }
    }
    Err(CoreError::db("unable to allocate migration backup file"))
}

#[cfg(unix)]
fn sync_parent_directory(path: &Path) -> CoreResult<()> {
    let parent = path
        .parent()
        .ok_or_else(|| CoreError::db("database path has no parent"))?;
    File::open(parent)
        .and_then(|directory| directory.sync_all())
        .map_err(|error| CoreError::db(error.to_string()))
}

#[cfg(not(unix))]
fn sync_parent_directory(_path: &Path) -> CoreResult<()> {
    Ok(())
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

#[cfg(test)]
mod tests {
    use std::fs;

    use rusqlite::Connection;

    use super::{
        current_schema_version, receipt_schema_state, run_schema_migrations, table_columns,
        INITIAL_SCHEMA, LATEST_SCHEMA_VERSION,
    };
    use crate::db::{configure_connection, db_path};

    const V2_SCHEMA: &str = r#"
CREATE TABLE schema_version (
  version INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL,
  applied_by TEXT NOT NULL DEFAULT 'area_matrix_core'
);
INSERT INTO schema_version (version, applied_at, applied_by)
VALUES (2, 1, 'area_matrix_core');

CREATE TABLE external_sync_receipts (
  event_id INTEGER NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('created', 'renamed', 'removed', 'modified')),
  path TEXT NOT NULL,
  file_id INTEGER,
  previous_category TEXT,
  current_category TEXT,
  applied_at INTEGER NOT NULL,
  PRIMARY KEY (event_id, kind, path)
);
CREATE INDEX idx_external_sync_receipts_applied
  ON external_sync_receipts(applied_at DESC);

CREATE TABLE scan_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  status TEXT NOT NULL,
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
"#;

    fn v2_repo() -> (tempfile::TempDir, Connection) {
        let repo = tempfile::tempdir().expect("create temporary repository directory");
        fs::create_dir(repo.path().join(".areamatrix")).expect("create metadata directory");
        let connection = Connection::open(db_path(repo.path())).expect("create v2 database");
        configure_connection(&connection).expect("configure v2 database");
        connection
            .execute_batch(V2_SCHEMA)
            .expect("install v2 schema fixture");
        (repo, connection)
    }

    #[test]
    fn v2_to_v3_migration_adds_nullable_checked_locale_after_backup() {
        let (repo, mut connection) = v2_repo();
        connection
            .execute(
                "INSERT INTO external_sync_receipts (
                   event_id, kind, path, applied_at
                 ) VALUES (1, 'created', 'docs/legacy.txt', 1)",
                [],
            )
            .expect("insert legacy receipt");

        run_schema_migrations(&mut connection, repo.path()).expect("migrate schema to v3");

        assert_eq!(
            current_schema_version(&connection).expect("read migrated schema version"),
            LATEST_SCHEMA_VERSION
        );
        assert!(table_columns(&connection, "external_sync_receipts")
            .expect("read migrated receipt columns")
            .contains("content_locale"));
        for table in [
            "recoverable_operations",
            "overview_regeneration_items",
            "overview_provenance",
        ] {
            assert!(
                !table_columns(&connection, table)
                    .expect("read migrated operation table")
                    .is_empty(),
                "{table} must be installed by v3 migration"
            );
        }
        assert!(table_columns(&connection, "scan_sessions")
            .expect("read migrated scan session columns")
            .contains("operation_id"));
        let legacy_locale: Option<String> = connection
            .query_row(
                "SELECT content_locale FROM external_sync_receipts WHERE event_id = 1",
                [],
                |row| row.get(0),
            )
            .expect("read migrated legacy locale");
        assert_eq!(legacy_locale, None);
        assert!(connection
            .execute(
                "INSERT INTO external_sync_receipts (
                   event_id, kind, path, content_locale, applied_at
                 ) VALUES (2, 'created', 'docs/invalid.txt', 'system', 2)",
                [],
            )
            .is_err());
        connection
            .execute(
                "UPDATE external_sync_receipts SET content_locale = 'en' WHERE event_id = 1",
                [],
            )
            .expect("explicitly recover one legacy null receipt locale");
        assert!(connection
            .execute(
                "UPDATE external_sync_receipts SET content_locale = 'zh-Hans' WHERE event_id = 1",
                [],
            )
            .is_err());
        assert!(connection
            .execute(
                "INSERT INTO external_sync_receipts (
                   event_id, kind, path, applied_at
                 ) VALUES (3, 'created', 'docs/missing-locale.txt', 3)",
                [],
            )
            .is_err());
        let integrity: String = connection
            .query_row("PRAGMA integrity_check", [], |row| row.get(0))
            .expect("check migrated database integrity");
        assert_eq!(integrity, "ok");

        let backup = repo.path().join(".areamatrix/index.db.pre-v3.bak");
        assert!(backup.is_file());
        let backup_connection = Connection::open(backup).expect("open pre-v3 backup");
        assert_eq!(
            current_schema_version(&backup_connection).expect("read backup schema version"),
            2
        );
    }

    #[test]
    fn fresh_and_migrated_v3_share_operation_and_nullable_receipt_shape() {
        let (repo, mut migrated) = v2_repo();
        run_schema_migrations(&mut migrated, repo.path()).expect("migrate schema to v3");

        let fresh = Connection::open_in_memory().expect("create fresh database");
        fresh
            .execute_batch(INITIAL_SCHEMA)
            .expect("install fresh v3 schema");

        for table in [
            "external_sync_receipts",
            "scan_sessions",
            "recoverable_operations",
            "overview_regeneration_items",
            "overview_provenance",
        ] {
            assert_eq!(
                table_columns(&fresh, table).expect("read fresh columns"),
                table_columns(&migrated, table).expect("read migrated columns"),
                "fresh and migrated columns differ for {table}"
            );
        }
        assert!(!column_is_not_null(
            &fresh,
            "external_sync_receipts",
            "content_locale"
        ));
        assert!(receipt_schema_state(&fresh)
            .expect("inspect fresh receipt schema")
            .is_valid());
        assert!(receipt_schema_state(&migrated)
            .expect("inspect migrated receipt schema")
            .is_valid());
        for connection in [&fresh, &migrated] {
            assert!(connection
                .execute(
                    "INSERT INTO external_sync_receipts (
                       event_id, kind, path, applied_at
                     ) VALUES (9, 'created', 'docs/no-locale.txt', 9)",
                    [],
                )
                .is_err());
        }
        assert!(!column_is_not_null(
            &migrated,
            "external_sync_receipts",
            "content_locale"
        ));
    }

    fn column_is_not_null(connection: &Connection, table: &str, column: &str) -> bool {
        let mut statement = connection
            .prepare(&format!("PRAGMA table_info({table})"))
            .expect("prepare table info");
        let result = statement
            .query_map([], |row| {
                Ok((row.get::<_, String>(1)?, row.get::<_, i64>(3)?))
            })
            .expect("query table info")
            .map(|row| row.expect("read table info row"))
            .find_map(|(name, not_null)| (name == column).then_some(not_null != 0))
            .expect("column exists");
        result
    }

    #[test]
    fn failed_v3_migration_rolls_back_ddl_and_keeps_v2_recoverable() {
        let (repo, mut connection) = v2_repo();
        connection
            .execute_batch(
                "CREATE TRIGGER reject_schema_v3
                 BEFORE INSERT ON schema_version
                 WHEN NEW.version = 3
                 BEGIN
                   SELECT RAISE(ABORT, 'forced v3 migration failure');
                 END;",
            )
            .expect("install migration failure trigger");

        let error = run_schema_migrations(&mut connection, repo.path())
            .expect_err("forced v3 migration must fail");

        assert!(matches!(error, crate::CoreError::Db { .. }));
        assert_eq!(
            current_schema_version(&connection).expect("read retained schema version"),
            2
        );
        assert!(!table_columns(&connection, "external_sync_receipts")
            .expect("read rolled-back receipt columns")
            .contains("content_locale"));
        assert!(repo
            .path()
            .join(".areamatrix/index.db.pre-v3.bak")
            .is_file());
    }

    #[test]
    fn migration_backup_is_numbered_without_overwrite_and_user_bytes_are_unchanged() {
        let (repo, mut connection) = v2_repo();
        let existing_backup = repo.path().join(".areamatrix/index.db.pre-v3.bak");
        fs::write(&existing_backup, b"preexisting backup bytes")
            .expect("write preexisting backup fixture");
        let user_file = repo.path().join("README.md");
        fs::write(&user_file, b"user-owned readme bytes").expect("write user fixture");

        run_schema_migrations(&mut connection, repo.path()).expect("migrate schema to v3");

        assert_eq!(
            fs::read(&existing_backup).expect("read preserved preexisting backup"),
            b"preexisting backup bytes"
        );
        let numbered = repo.path().join(".areamatrix/index.db.pre-v3.1.bak");
        assert!(numbered.is_file());
        let backup_connection = Connection::open(numbered).expect("open numbered v2 backup");
        assert_eq!(
            current_schema_version(&backup_connection).expect("read numbered backup version"),
            2
        );
        assert_eq!(
            fs::read(user_file).expect("read user fixture after migration"),
            b"user-owned readme bytes"
        );
    }
}
