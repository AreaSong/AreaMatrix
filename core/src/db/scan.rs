use std::path::Path;

use rusqlite::{params, types::Type, OptionalExtension, Row};
use serde_json::json;

use crate::{
    CoreError, CoreResult, FileOrigin, ScanSession, ScanSessionKind, ScanSessionStatus, StorageMode,
};

use super::{
    open_repo_connection, open_repo_read_connection, origin_from_db, storage_mode_from_db,
};

#[derive(Debug)]
pub(crate) struct FileIndexInput {
    pub path: String,
    pub original_name: String,
    pub current_name: String,
    pub category: String,
    pub size_bytes: i64,
    pub hash_sha256: String,
}

#[derive(Debug)]
pub(crate) struct ScanFileSnapshot {
    pub path: String,
    pub original_name: String,
    pub current_name: String,
    pub category: String,
    pub size_bytes: i64,
    pub hash_sha256: String,
    pub storage_mode: StorageMode,
    pub origin: FileOrigin,
    pub source_path: Option<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ScanFileChange {
    Inserted,
    Updated,
    Missing,
    Conflict,
    Unreadable,
    Unknown,
    Skipped,
}

pub(crate) fn create_scan_session(repo_path: &Path, kind: ScanSessionKind) -> CoreResult<i64> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .execute(
            "INSERT INTO scan_sessions (
                kind, status, started_at, updated_at, inserted, updated,
                missing, conflicts, unreadable, unknown, skipped, errors_json
             ) VALUES (
                ?1, 'running', strftime('%s', 'now'), strftime('%s', 'now'),
                0, 0, 0, 0, 0, 0, 0, '[]'
             )",
            params![kind_to_db(&kind)],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(connection.last_insert_rowid())
}

pub(crate) fn has_running_reindex_session(repo_path: &Path) -> CoreResult<bool> {
    let connection = open_repo_connection(repo_path)?;
    has_running_reindex_session_on_connection(&connection, None)
}

pub(crate) fn has_running_reindex_session_excluding(
    repo_path: &Path,
    excluded_session_id: Option<i64>,
) -> CoreResult<bool> {
    let connection = open_repo_connection(repo_path)?;
    has_running_reindex_session_on_connection(&connection, excluded_session_id)
}

pub(crate) fn has_running_reindex_session_read_only(repo_path: &Path) -> CoreResult<bool> {
    let connection = open_repo_read_connection(repo_path)?;
    has_running_reindex_session_on_connection(&connection, None)
}

fn has_running_reindex_session_on_connection(
    connection: &rusqlite::Connection,
    excluded_session_id: Option<i64>,
) -> CoreResult<bool> {
    let count: i64 = connection
        .query_row(
            "SELECT COUNT(*)
             FROM scan_sessions
             WHERE kind = 'reindex'
               AND status = 'running'
               AND (?1 IS NULL OR id != ?1)",
            params![excluded_session_id],
            |row| row.get(0),
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(count > 0)
}

pub(crate) fn latest_scan_session(repo_path: &Path) -> CoreResult<Option<ScanSession>> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT id, kind, status, last_path, inserted, updated,
                    missing, conflicts, unreadable, unknown, skipped,
                    started_at, updated_at, finished_at, errors_json
             FROM scan_sessions
             WHERE kind IN ('adopt', 'reindex')
             ORDER BY updated_at DESC, id DESC
             LIMIT 1",
            [],
            scan_session_from_row,
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn scan_session_by_id(
    repo_path: &Path,
    scan_session_id: i64,
) -> CoreResult<ScanSession> {
    let connection = open_repo_connection(repo_path)?;
    connection
        .query_row(
            "SELECT id, kind, status, last_path, inserted, updated,
                    missing, conflicts, unreadable, unknown, skipped,
                    started_at, updated_at, finished_at, errors_json
             FROM scan_sessions
             WHERE id = ?1",
            params![scan_session_id],
            scan_session_from_row,
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .ok_or_else(|| CoreError::db("database error"))
}

pub(crate) fn active_scan_file_snapshots(repo_path: &Path) -> CoreResult<Vec<ScanFileSnapshot>> {
    let connection = open_repo_connection(repo_path)?;
    active_scan_file_snapshots_on_connection(&connection)
}

pub(crate) fn active_scan_file_snapshots_read_only(
    repo_path: &Path,
) -> CoreResult<Vec<ScanFileSnapshot>> {
    let connection = open_repo_read_connection(repo_path)?;
    active_scan_file_snapshots_on_connection(&connection)
}

fn active_scan_file_snapshots_on_connection(
    connection: &rusqlite::Connection,
) -> CoreResult<Vec<ScanFileSnapshot>> {
    let mut statement = connection
        .prepare(
            "SELECT path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path
             FROM files
             WHERE status = 'active'",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut rows = statement
        .query([])
        .map_err(|error| CoreError::db(error.to_string()))?;
    let mut snapshots = Vec::new();
    while let Some(row) = rows
        .next()
        .map_err(|error| CoreError::db(error.to_string()))?
    {
        let storage_mode: String = row
            .get(6)
            .map_err(|error| CoreError::db(error.to_string()))?;
        let origin: String = row
            .get(7)
            .map_err(|error| CoreError::db(error.to_string()))?;
        snapshots.push(ScanFileSnapshot {
            path: row
                .get(0)
                .map_err(|error| CoreError::db(error.to_string()))?,
            original_name: row
                .get(1)
                .map_err(|error| CoreError::db(error.to_string()))?,
            current_name: row
                .get(2)
                .map_err(|error| CoreError::db(error.to_string()))?,
            category: row
                .get(3)
                .map_err(|error| CoreError::db(error.to_string()))?,
            size_bytes: row
                .get(4)
                .map_err(|error| CoreError::db(error.to_string()))?,
            hash_sha256: row
                .get(5)
                .map_err(|error| CoreError::db(error.to_string()))?,
            storage_mode: storage_mode_from_db(&storage_mode)?,
            origin: origin_from_db(&origin)?,
            source_path: row
                .get(8)
                .map_err(|error| CoreError::db(error.to_string()))?,
        });
    }
    Ok(snapshots)
}

pub(crate) fn mark_scan_session_running_for_resume(
    repo_path: &Path,
    scan_session_id: i64,
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    let changed = connection
        .execute(
            "UPDATE scan_sessions
             SET status = 'running',
                 updated_at = strftime('%s', 'now'),
                 finished_at = NULL,
                 errors_json = '[]'
             WHERE id = ?1
               AND status IN ('paused', 'failed', 'interrupted')",
            params![scan_session_id],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 0 {
        return Err(CoreError::db("database error"));
    }
    Ok(())
}

pub(crate) fn upsert_adopted_file(
    repo_path: &Path,
    input: &FileIndexInput,
) -> CoreResult<ScanFileChange> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let existing = existing_file_for_path(&tx, &input.path)?;
    let change = match existing {
        Some(existing) if existing.matches(input, FileOrigin::Adopted) => ScanFileChange::Skipped,
        Some(existing) => {
            tx.execute(
                "UPDATE files
                 SET original_name = ?2,
                     current_name = ?3,
                     category = ?4,
                     size_bytes = ?5,
                     hash_sha256 = ?6,
                     storage_mode = 'indexed',
                     origin = 'adopted',
                     source_path = NULL,
                     updated_at = strftime('%s', 'now'),
                     status = 'active'
                 WHERE id = ?1",
                params![
                    existing.id,
                    input.original_name,
                    input.current_name,
                    input.category,
                    input.size_bytes,
                    input.hash_sha256,
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
            ScanFileChange::Updated
        }
        None => {
            tx.execute(
                "INSERT INTO files (
                    path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path,
                    imported_at, updated_at, status
                 ) VALUES (
                    ?1, ?2, ?3, ?4, ?5, ?6, 'indexed', 'adopted', NULL,
                    strftime('%s', 'now'), strftime('%s', 'now'), 'active'
                 )",
                params![
                    input.path,
                    input.original_name,
                    input.current_name,
                    input.category,
                    input.size_bytes,
                    input.hash_sha256,
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
            let file_id = tx.last_insert_rowid();
            tx.execute(
                "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
                 VALUES (?1, 'adopted', ?2, strftime('%s', 'now'))",
                params![file_id, r#"{"mode":"indexed","source":"adopt_existing"}"#],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
            ScanFileChange::Inserted
        }
    };
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(change)
}

pub(crate) fn upsert_reindexed_file(
    repo_path: &Path,
    input: &FileIndexInput,
) -> CoreResult<ScanFileChange> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let existing = existing_file_for_path(&tx, &input.path)?;
    let change = match existing {
        Some(existing) if existing.matches(input, FileOrigin::External) => ScanFileChange::Skipped,
        Some(existing) => {
            tx.execute(
                "UPDATE files
                 SET original_name = ?2,
                     current_name = ?3,
                     category = ?4,
                     size_bytes = ?5,
                     hash_sha256 = ?6,
                     storage_mode = 'indexed',
                     origin = 'external',
                     source_path = NULL,
                     deleted_at = NULL,
                     updated_at = strftime('%s', 'now'),
                     status = 'active'
                 WHERE id = ?1",
                params![
                    existing.id,
                    input.original_name,
                    input.current_name,
                    input.category,
                    input.size_bytes,
                    input.hash_sha256,
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
            insert_reindex_change(&tx, existing.id, input)?;
            ScanFileChange::Updated
        }
        None => {
            tx.execute(
                "INSERT INTO files (
                    path, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, source_path,
                    imported_at, updated_at, status
                 ) VALUES (
                    ?1, ?2, ?3, ?4, ?5, ?6, 'indexed', 'external', NULL,
                    strftime('%s', 'now'), strftime('%s', 'now'), 'active'
                 )",
                params![
                    input.path,
                    input.original_name,
                    input.current_name,
                    input.category,
                    input.size_bytes,
                    input.hash_sha256,
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
            let file_id = tx.last_insert_rowid();
            insert_reindex_change(&tx, file_id, input)?;
            ScanFileChange::Inserted
        }
    };
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(change)
}

pub(crate) fn update_scan_session_progress(
    repo_path: &Path,
    scan_session_id: i64,
    last_path: &str,
    change: ScanFileChange,
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    let inserted_inc = if change == ScanFileChange::Inserted {
        1
    } else {
        0
    };
    let updated_inc = if change == ScanFileChange::Updated {
        1
    } else {
        0
    };
    let skipped_inc = if change == ScanFileChange::Skipped {
        1
    } else {
        0
    };
    let missing_inc = if change == ScanFileChange::Missing {
        1
    } else {
        0
    };
    let conflict_inc = if change == ScanFileChange::Conflict {
        1
    } else {
        0
    };
    let unreadable_inc = if change == ScanFileChange::Unreadable {
        1
    } else {
        0
    };
    let unknown_inc = if change == ScanFileChange::Unknown {
        1
    } else {
        0
    };
    connection
        .execute(
            "UPDATE scan_sessions
             SET last_path = CASE WHEN ?2 = '' THEN last_path ELSE ?2 END,
                 inserted = inserted + ?3,
                 updated = updated + ?4,
                 skipped = skipped + ?5,
                 missing = missing + ?6,
                 conflicts = conflicts + ?7,
                 unreadable = unreadable + ?8,
                 unknown = unknown + ?9,
                 updated_at = strftime('%s', 'now')
             WHERE id = ?1",
            params![
                scan_session_id,
                last_path,
                inserted_inc,
                updated_inc,
                skipped_inc,
                missing_inc,
                conflict_inc,
                unreadable_inc,
                unknown_inc
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(())
}

pub(crate) fn finish_scan_session(
    repo_path: &Path,
    scan_session_id: i64,
    status: ScanSessionStatus,
    errors: &[String],
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    let errors_json =
        serde_json::to_string(errors).map_err(|error| CoreError::db(error.to_string()))?;
    connection
        .execute(
            "UPDATE scan_sessions
             SET status = ?2,
                 updated_at = strftime('%s', 'now'),
                 finished_at = CASE WHEN ?2 = 'completed' THEN strftime('%s', 'now') ELSE NULL END,
                 errors_json = ?3
             WHERE id = ?1",
            params![scan_session_id, status_to_db(&status), errors_json],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(())
}

#[derive(Debug)]
struct ExistingFile {
    id: i64,
    original_name: String,
    current_name: String,
    category: String,
    size_bytes: i64,
    hash_sha256: String,
    storage_mode: StorageMode,
    origin: FileOrigin,
    status: String,
}

impl ExistingFile {
    fn matches(&self, input: &FileIndexInput, origin: FileOrigin) -> bool {
        self.original_name == input.original_name
            && self.current_name == input.current_name
            && self.category == input.category
            && self.size_bytes == input.size_bytes
            && self.hash_sha256 == input.hash_sha256
            && self.storage_mode == StorageMode::Indexed
            && self.origin == origin
            && self.status == "active"
    }
}

fn insert_reindex_change(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    input: &FileIndexInput,
) -> CoreResult<()> {
    let detail_json = json!({
        "kind": "reindex",
        "path": input.path,
        "category": input.category,
        "hash_after": input.hash_sha256,
        "size_bytes": input.size_bytes,
    })
    .to_string();
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, strftime('%s', 'now'))",
        params![file_id, detail_json],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn existing_file_for_path(
    connection: &rusqlite::Transaction<'_>,
    path: &str,
) -> CoreResult<Option<ExistingFile>> {
    connection
        .query_row(
            "SELECT id, original_name, current_name, category, size_bytes,
                    hash_sha256, storage_mode, origin, status
             FROM files
             WHERE path = ?1",
            params![path],
            |row| {
                let storage_mode: String = row.get(6)?;
                let origin: String = row.get(7)?;
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, String>(5)?,
                    storage_mode,
                    origin,
                    row.get::<_, String>(8)?,
                ))
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?
        .map(|row| {
            Ok(ExistingFile {
                id: row.0,
                original_name: row.1,
                current_name: row.2,
                category: row.3,
                size_bytes: row.4,
                hash_sha256: row.5,
                storage_mode: storage_mode_from_db(&row.6)?,
                origin: origin_from_db(&row.7)?,
                status: row.8,
            })
        })
        .transpose()
}

fn scan_session_from_row(row: &Row<'_>) -> rusqlite::Result<ScanSession> {
    let kind: String = row.get(1)?;
    let status: String = row.get(2)?;
    let errors_json: String = row.get(14)?;
    let errors = serde_json::from_str(&errors_json).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(14, Type::Text, Box::new(error))
    })?;
    Ok(ScanSession {
        id: row.get(0)?,
        kind: kind_from_db(&kind)?,
        status: status_from_db(&status)?,
        last_path: row.get(3)?,
        inserted: row.get(4)?,
        updated: row.get(5)?,
        missing: row.get(6)?,
        conflicts: row.get(7)?,
        unreadable: row.get(8)?,
        unknown: row.get(9)?,
        skipped: row.get(10)?,
        started_at: row.get(11)?,
        updated_at: row.get(12)?,
        finished_at: row.get(13)?,
        errors,
    })
}

fn kind_to_db(kind: &ScanSessionKind) -> &'static str {
    match kind {
        ScanSessionKind::Adopt => "adopt",
        ScanSessionKind::Reindex => "reindex",
    }
}

fn kind_from_db(value: &str) -> rusqlite::Result<ScanSessionKind> {
    match value {
        "adopt" | "Adopt" => Ok(ScanSessionKind::Adopt),
        "reindex" | "Reindex" => Ok(ScanSessionKind::Reindex),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}

fn status_to_db(status: &ScanSessionStatus) -> &'static str {
    match status {
        ScanSessionStatus::Running => "running",
        ScanSessionStatus::Completed => "completed",
        ScanSessionStatus::Paused => "paused",
        ScanSessionStatus::Failed => "failed",
        ScanSessionStatus::Interrupted => "interrupted",
    }
}

fn status_from_db(value: &str) -> rusqlite::Result<ScanSessionStatus> {
    match value {
        "running" | "Running" => Ok(ScanSessionStatus::Running),
        "completed" | "Completed" => Ok(ScanSessionStatus::Completed),
        "paused" | "Paused" => Ok(ScanSessionStatus::Paused),
        "failed" | "Failed" => Ok(ScanSessionStatus::Failed),
        "interrupted" | "Interrupted" => Ok(ScanSessionStatus::Interrupted),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}
