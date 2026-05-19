use rusqlite::{params, Transaction};

use crate::{CoreError, CoreResult};

use super::{ImportConflictKind, ImportConflictRow, ImportConflictStatus};

pub(super) fn import_conflict_from_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<ImportConflictRow> {
    let conflict_type: String = row.get(2)?;
    let status: String = row.get(7)?;
    Ok(ImportConflictRow {
        conflict_id: row.get(0)?,
        import_session_id: row.get(1)?,
        conflict_type: conflict_type_from_db(&conflict_type)?,
        staging_file_id: row.get(3)?,
        existing_file_id: row.get(4)?,
        incoming_path: row.get(5)?,
        target_path: row.get(6)?,
        status: conflict_status_from_db(&status)?,
        failure_reason: row.get(8)?,
    })
}

pub(super) fn update_import_conflict_status(
    connection: &rusqlite::Connection,
    import_session_id: &str,
    conflict_id: &str,
    status: &str,
    decision: &str,
    failure_reason: Option<&str>,
) -> CoreResult<()> {
    update_status(
        connection,
        import_session_id,
        conflict_id,
        status,
        decision,
        failure_reason,
    )
}

pub(super) fn update_import_conflict_status_in_tx(
    tx: &Transaction<'_>,
    import_session_id: &str,
    conflict_id: &str,
    status: &str,
    decision: &str,
    failure_reason: Option<&str>,
) -> CoreResult<()> {
    update_status(
        tx,
        import_session_id,
        conflict_id,
        status,
        decision,
        failure_reason,
    )
}

pub(super) fn refresh_import_session_status(
    tx: &Transaction<'_>,
    import_session_id: &str,
) -> CoreResult<()> {
    let pending_count = pending_import_conflict_count(tx, import_session_id)?;
    update_import_session_status(tx, import_session_id, pending_count)
}

pub(super) fn refresh_import_session_status_with_connection(
    connection: &rusqlite::Connection,
    import_session_id: &str,
) -> CoreResult<()> {
    let pending_count = pending_import_conflict_count(connection, import_session_id)?;
    update_import_session_status(connection, import_session_id, pending_count)
}

fn conflict_type_from_db(value: &str) -> rusqlite::Result<ImportConflictKind> {
    match value {
        "duplicate_hash" => Ok(ImportConflictKind::DuplicateHash),
        "same_name_different_content" => Ok(ImportConflictKind::SameNameDifferentContent),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}

fn conflict_status_from_db(value: &str) -> rusqlite::Result<ImportConflictStatus> {
    match value {
        "pending" => Ok(ImportConflictStatus::Pending),
        "queued_for_per_item" => Ok(ImportConflictStatus::QueuedForPerItem),
        "resolved" => Ok(ImportConflictStatus::Resolved),
        "failed" => Ok(ImportConflictStatus::Failed),
        _ => Err(rusqlite::Error::InvalidQuery),
    }
}

fn update_status(
    connection: &rusqlite::Connection,
    import_session_id: &str,
    conflict_id: &str,
    status: &str,
    decision: &str,
    failure_reason: Option<&str>,
) -> CoreResult<()> {
    let changed = connection
        .execute(
            STATUS_UPDATE_SQL,
            params![
                import_session_id,
                conflict_id,
                status,
                decision,
                failure_reason
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::file_not_found("missing import conflict"))
    }
}

fn pending_import_conflict_count(
    connection: &rusqlite::Connection,
    import_session_id: &str,
) -> CoreResult<i64> {
    connection
        .query_row(
            PENDING_CONFLICT_COUNT_SQL,
            params![import_session_id],
            |row| row.get(0),
        )
        .map_err(|error| CoreError::db(error.to_string()))
}

fn update_import_session_status(
    connection: &rusqlite::Connection,
    import_session_id: &str,
    pending_count: i64,
) -> CoreResult<()> {
    connection
        .execute(
            IMPORT_SESSION_STATUS_SQL,
            params![import_session_id, import_session_status(pending_count)],
        )
        .map(|_| ())
        .map_err(|error| CoreError::db(error.to_string()))
}

fn import_session_status(pending_count: i64) -> &'static str {
    if pending_count == 0 {
        "resolved"
    } else {
        "partially_resolved"
    }
}

const STATUS_UPDATE_SQL: &str = "UPDATE import_conflicts
    SET status = ?3,
        decision = ?4,
        failure_reason = ?5,
        updated_at = strftime('%s', 'now')
  WHERE import_session_id = ?1 AND conflict_id = ?2";
const IMPORT_SESSION_STATUS_SQL: &str = "UPDATE import_sessions
    SET status = ?2,
        updated_at = strftime('%s', 'now')
  WHERE import_session_id = ?1";
const PENDING_CONFLICT_COUNT_SQL: &str = "SELECT COUNT(*)
    FROM import_conflicts
   WHERE import_session_id = ?1
     AND status IN ('pending', 'failed')";
