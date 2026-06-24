use std::path::Path;

use rusqlite::{params, Transaction};

use crate::{CoreError, CoreResult};

use super::{super::open_repo_connection, types::ImportConflictRow};

pub(crate) fn rollback_import_conflict_decision(
    repo_path: &Path,
    conflict: &ImportConflictRow,
    session_status: &str,
) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    rollback_conflict_status(&tx, conflict, session_status)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn rollback_import_conflict_keep_both(
    repo_path: &Path,
    conflict: &ImportConflictRow,
    final_path: &str,
    staging_path: &str,
    staging_name: &str,
    session_status: &str,
) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    rollback_promoted_staging(
        &tx,
        conflict.staging_file_id,
        staging_path,
        final_path,
        staging_name,
    )?;
    rollback_conflict_status(&tx, conflict, session_status)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn rollback_import_conflict_replace(
    repo_path: &Path,
    conflict: &ImportConflictRow,
    final_path: &str,
    archived_path: &str,
    staging_path: &str,
    staging_name: &str,
    session_status: &str,
) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    rollback_promoted_staging(
        &tx,
        conflict.staging_file_id,
        staging_path,
        final_path,
        staging_name,
    )?;
    rollback_replaced_existing(&tx, conflict, archived_path)?;
    rollback_conflict_status(&tx, conflict, session_status)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn rollback_conflict_status(
    tx: &Transaction<'_>,
    conflict: &ImportConflictRow,
    session_status: &str,
) -> CoreResult<()> {
    tx.execute(
        "UPDATE import_conflicts
            SET status = 'pending',
                decision = NULL,
                failure_reason = NULL,
                updated_at = strftime('%s', 'now')
          WHERE import_session_id = ?1 AND conflict_id = ?2",
        params![conflict.import_session_id, conflict.conflict_id],
    )
    .map_err(|error| CoreError::db(error.to_string()))
    .and_then(|changed| {
        if changed == 1 {
            Ok(())
        } else {
            Err(CoreError::db("database error"))
        }
    })?;
    let changed = tx
        .execute(
            "UPDATE import_sessions
            SET status = ?2,
                updated_at = strftime('%s', 'now')
          WHERE import_session_id = ?1",
            params![conflict.import_session_id, session_status],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::db("database error"))
    }
}

fn rollback_promoted_staging(
    tx: &Transaction<'_>,
    file_id: i64,
    staging_path: &str,
    final_path: &str,
    staging_name: &str,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
                SET path = ?2,
                    current_name = ?4,
                    updated_at = strftime('%s', 'now'),
                    status = 'staging'
              WHERE id = ?1 AND status = 'active' AND path = ?3",
            params![file_id, staging_path, final_path, staging_name],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    tx.execute(
        "DELETE FROM change_log WHERE file_id = ?1 AND action = 'imported'",
        params![file_id],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn rollback_replaced_existing(
    tx: &Transaction<'_>,
    conflict: &ImportConflictRow,
    archived_path: &str,
) -> CoreResult<()> {
    let Some(existing_id) = conflict.existing_file_id else {
        return Err(CoreError::db("database error"));
    };
    let changed = tx
        .execute(
            "UPDATE files
                SET path = ?2,
                    deleted_at = NULL,
                    updated_at = strftime('%s', 'now'),
                    status = 'active'
              WHERE id = ?1 AND status = 'deleted' AND path = ?3",
            params![existing_id, conflict.target_path, archived_path],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    tx.execute(
        "DELETE FROM change_log WHERE file_id = ?1 AND action = 'deleted'",
        params![existing_id],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}
