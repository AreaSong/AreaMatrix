use std::path::Path;

use rusqlite::{params, OptionalExtension};

use crate::{CoreError, CoreResult, ScanSession, ScanSessionKind, ScanSessionStatus};

use super::{
    kind_to_db, open_repo_connection, open_repo_read_connection, scan_session_from_row,
    status_to_db, ScanFileChange,
};

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
