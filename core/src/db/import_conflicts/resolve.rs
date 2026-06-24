use std::path::Path;

use rusqlite::{params, Transaction};
use serde_json::Value;

use crate::{CoreError, CoreResult};

use super::{
    super::open_repo_connection,
    json::serialize_json,
    status,
    types::{ImportConflictApplyItem, ImportConflictRow},
};

pub(crate) fn resolve_import_conflict_item(
    repo_path: &Path,
    item: ImportConflictApplyItem<'_>,
) -> CoreResult<()> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    if let Some(replacement) = item.replaced {
        let existing_id = item
            .conflict
            .existing_file_id
            .ok_or_else(|| CoreError::db("database error"))?;
        soft_delete_existing(
            &tx,
            existing_id,
            replacement.archived_path,
            replacement.deleted_detail,
        )?;
    }
    if let (Some(final_path), Some(final_name), Some(change_detail)) =
        (item.final_path, item.final_name, item.change_detail)
    {
        promote_staging_file(
            &tx,
            item.conflict.staging_file_id,
            final_path,
            final_name,
            change_detail,
        )?;
    }
    status::update_import_conflict_status_in_tx(
        &tx,
        &item.conflict.import_session_id,
        &item.conflict.conflict_id,
        "resolved",
        item.decision,
        None,
    )?;
    status::refresh_import_session_status(&tx, &item.conflict.import_session_id)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(crate) fn queue_import_conflict_for_per_item(
    repo_path: &Path,
    conflict: &ImportConflictRow,
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    status::update_import_conflict_status(
        &connection,
        &conflict.import_session_id,
        &conflict.conflict_id,
        "queued_for_per_item",
        "ask_per_item",
        None,
    )?;
    status::refresh_import_session_status_with_connection(&connection, &conflict.import_session_id)
}

pub(crate) fn mark_import_conflict_failed(
    repo_path: &Path,
    conflict: &ImportConflictRow,
    decision: &str,
    reason: &str,
) -> CoreResult<()> {
    let connection = open_repo_connection(repo_path)?;
    status::update_import_conflict_status(
        &connection,
        &conflict.import_session_id,
        &conflict.conflict_id,
        "failed",
        decision,
        Some(reason),
    )
}

fn soft_delete_existing(
    tx: &Transaction<'_>,
    existing_id: i64,
    archived_path: &str,
    detail: &Value,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
                SET path = ?2,
                    deleted_at = strftime('%s', 'now'),
                    updated_at = strftime('%s', 'now'),
                    status = 'deleted'
              WHERE id = ?1 AND status = 'active'",
            params![existing_id, archived_path],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    insert_change(tx, existing_id, "deleted", detail)
}

fn promote_staging_file(
    tx: &Transaction<'_>,
    file_id: i64,
    final_path: &str,
    final_name: &str,
    detail: &Value,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
                SET path = ?2,
                    current_name = ?3,
                    updated_at = strftime('%s', 'now'),
                    status = 'active'
              WHERE id = ?1 AND status = 'staging'",
            params![file_id, final_path, final_name],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed != 1 {
        return Err(CoreError::db("database error"));
    }
    insert_change(tx, file_id, "imported", detail)
}

fn insert_change(
    tx: &Transaction<'_>,
    file_id: i64,
    action: &str,
    detail: &Value,
) -> CoreResult<()> {
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, ?2, ?3, strftime('%s', 'now'))",
        params![file_id, action, serialize_json(detail)?],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}
