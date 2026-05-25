use std::path::Path;

use rusqlite::params;
use serde::Deserialize;
use serde_json::Value;

use crate::{CoreError, CoreResult};

use super::{
    file_actions::{file_refresh_targets, filesystem_redo_block_reason, insert_file_redo_change},
    file_state::{ensure_single_row_changed, load_file_state, FileDbState},
    fs_ops, RedoExecution, TRASH_DELETE_KIND,
};

#[derive(Debug, Deserialize)]
pub(super) struct RestoreBatchFileStateInverse {
    kind: String,
    operation: String,
    items: Vec<RestoreBatchFileStateItem>,
}

#[derive(Debug, Deserialize)]
struct RestoreBatchFileStateItem {
    file_id: i64,
    expected_path: String,
    expected_name: String,
    expected_category: String,
    restore_path: String,
    restore_name: String,
    restore_category: String,
    index_only: bool,
}

#[derive(Debug, Deserialize)]
pub(super) struct RestoreBatchDeletedFilesInverse {
    kind: String,
    operation: String,
    items: Vec<RestoreBatchDeletedFileItem>,
}

#[derive(Debug, Deserialize)]
struct RestoreBatchDeletedFileItem {
    file_id: i64,
    #[serde(rename = "trash_path")]
    _trash_path: String,
    restore_path: String,
    restore_name: String,
    restore_category: String,
}

pub(super) fn parse_restore_batch_file_state(
    value: &Value,
) -> CoreResult<RestoreBatchFileStateInverse> {
    serde_json::from_value(value.clone()).map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn parse_restore_batch_deleted_files(
    value: &Value,
) -> CoreResult<RestoreBatchDeletedFilesInverse> {
    serde_json::from_value(value.clone()).map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn execute_restore_batch_file_state_redo(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    kind: &str,
    inverse: &RestoreBatchFileStateInverse,
    completed_at: i64,
) -> CoreResult<RedoExecution> {
    ensure_restore_batch_file_state_kind(inverse)?;
    ensure_batch_file_state_matches_restored(tx, inverse)?;
    let mut guards = move_redo_batch_active_paths(repo, inverse)?;
    if let Err(error) = update_batch_file_state_to_expected(tx, inverse, completed_at) {
        return Err(fs_ops::rollback_guards_or_error(&mut guards, error));
    }
    for item in &inverse.items {
        if let Err(error) =
            insert_file_redo_change(tx, kind, item.file_id, completed_at, &inverse.operation)
        {
            return Err(fs_ops::rollback_guards_or_error(&mut guards, error));
        }
    }
    Ok(RedoExecution {
        summary: format!("Redone: {}.", inverse.operation),
        affected_count: inverse.items.len() as i64,
        refresh_targets: file_refresh_targets(kind),
        guards,
    })
}

pub(super) fn execute_restore_batch_deleted_files_redo(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    inverse: &RestoreBatchDeletedFilesInverse,
    completed_at: i64,
) -> CoreResult<RedoExecution> {
    ensure_restore_batch_deleted_files_kind(inverse)?;
    ensure_batch_deleted_files_match_restored(tx, inverse)?;
    let mut guards = move_batch_files_to_trash(repo, inverse)?;
    if let Err(error) = update_batch_deleted_files_to_deleted(tx, inverse, completed_at) {
        return Err(fs_ops::rollback_guards_or_error(&mut guards, error));
    }
    for item in &inverse.items {
        if let Err(error) = insert_file_redo_change(
            tx,
            TRASH_DELETE_KIND,
            item.file_id,
            completed_at,
            &inverse.operation,
        ) {
            return Err(fs_ops::rollback_guards_or_error(&mut guards, error));
        }
    }
    Ok(RedoExecution {
        summary: "Redone: moved files to Trash.".to_owned(),
        affected_count: inverse.items.len() as i64,
        refresh_targets: file_refresh_targets(TRASH_DELETE_KIND),
        guards,
    })
}

pub(super) fn batch_file_state_redo_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &RestoreBatchFileStateInverse,
) -> CoreResult<Option<String>> {
    ensure_restore_batch_file_state_kind(inverse)?;
    for item in &inverse.items {
        let Some(state) = load_file_state(connection, item.file_id)? else {
            return Ok(Some("File no longer exists".to_owned()));
        };
        if state.status != "active" {
            return Ok(Some("File no longer active".to_owned()));
        }
        if !batch_state_matches_restored(&state, item) {
            return Ok(Some("File changed after undo".to_owned()));
        }
        if item.index_only {
            continue;
        }
        if let Some(reason) =
            filesystem_redo_block_reason(repo, &item.restore_path, &item.expected_path)?
        {
            return Ok(Some(reason));
        }
    }
    Ok(None)
}

pub(super) fn batch_deleted_files_redo_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &RestoreBatchDeletedFilesInverse,
) -> CoreResult<Option<String>> {
    ensure_restore_batch_deleted_files_kind(inverse)?;
    for item in &inverse.items {
        let Some(state) = load_file_state(connection, item.file_id)? else {
            return Ok(Some("File no longer exists".to_owned()));
        };
        if state.status != "active" || !batch_deleted_state_matches_restored(&state, item) {
            return Ok(Some("File changed after undo".to_owned()));
        }
        let current_path = fs_ops::repo_relative_path(repo, &item.restore_path)?;
        if !fs_ops::path_exists(&current_path)? {
            return Ok(Some("File no longer exists".to_owned()));
        }
        if !current_path
            .metadata()
            .map_err(fs_ops::map_io_error)?
            .is_file()
        {
            return Ok(Some("File changed after undo".to_owned()));
        }
    }
    Ok(None)
}

fn move_redo_batch_active_paths(
    repo: &Path,
    inverse: &RestoreBatchFileStateInverse,
) -> CoreResult<Vec<fs_ops::FileMoveRollbackGuard>> {
    let mut guards = Vec::new();
    for item in &inverse.items {
        if item.index_only {
            continue;
        }
        let restored_path = fs_ops::repo_relative_path(repo, &item.restore_path)?;
        let expected_path = fs_ops::repo_relative_path(repo, &item.expected_path)?;
        if restored_path == expected_path {
            continue;
        }
        guards.push(fs_ops::move_checked_path(
            repo,
            &restored_path,
            &expected_path,
        )?);
    }
    Ok(guards)
}

fn move_batch_files_to_trash(
    repo: &Path,
    inverse: &RestoreBatchDeletedFilesInverse,
) -> CoreResult<Vec<fs_ops::FileMoveRollbackGuard>> {
    let mut guards = Vec::new();
    for item in &inverse.items {
        let current_path = fs_ops::repo_relative_path(repo, &item.restore_path)?;
        guards.push(fs_ops::move_path_to_user_trash(repo, &current_path)?);
    }
    Ok(guards)
}

fn update_batch_file_state_to_expected(
    tx: &rusqlite::Transaction<'_>,
    inverse: &RestoreBatchFileStateInverse,
    updated_at: i64,
) -> CoreResult<()> {
    for item in &inverse.items {
        let changed = tx
            .execute(
                "UPDATE files
                 SET path = ?2,
                     current_name = ?3,
                     category = ?4,
                     updated_at = ?5
                 WHERE id = ?1 AND status = 'active'",
                params![
                    item.file_id,
                    item.expected_path,
                    item.expected_name,
                    item.expected_category,
                    updated_at
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
        ensure_single_row_changed(changed, item.file_id)?;
    }
    Ok(())
}

fn update_batch_deleted_files_to_deleted(
    tx: &rusqlite::Transaction<'_>,
    inverse: &RestoreBatchDeletedFilesInverse,
    updated_at: i64,
) -> CoreResult<()> {
    for item in &inverse.items {
        let changed = tx
            .execute(
                "UPDATE files
                 SET deleted_at = ?2,
                     updated_at = ?2,
                     status = 'deleted'
                 WHERE id = ?1 AND status = 'active'",
                params![item.file_id, updated_at],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
        ensure_single_row_changed(changed, item.file_id)?;
    }
    Ok(())
}

fn ensure_batch_file_state_matches_restored(
    connection: &rusqlite::Connection,
    inverse: &RestoreBatchFileStateInverse,
) -> CoreResult<()> {
    for item in &inverse.items {
        let state = load_file_state(connection, item.file_id)?
            .ok_or_else(|| CoreError::file_not_found(format!("file:{}", item.file_id)))?;
        if state.status != "active" || !batch_state_matches_restored(&state, item) {
            return Err(CoreError::conflict("File changed after undo"));
        }
    }
    Ok(())
}

fn ensure_batch_deleted_files_match_restored(
    connection: &rusqlite::Connection,
    inverse: &RestoreBatchDeletedFilesInverse,
) -> CoreResult<()> {
    for item in &inverse.items {
        let state = load_file_state(connection, item.file_id)?
            .ok_or_else(|| CoreError::file_not_found(format!("file:{}", item.file_id)))?;
        if state.status != "active" || !batch_deleted_state_matches_restored(&state, item) {
            return Err(CoreError::conflict("File changed after undo"));
        }
    }
    Ok(())
}

fn batch_state_matches_restored(state: &FileDbState, inverse: &RestoreBatchFileStateItem) -> bool {
    state.path == inverse.restore_path
        && state.current_name == inverse.restore_name
        && state.category == inverse.restore_category
}

fn batch_deleted_state_matches_restored(
    state: &FileDbState,
    inverse: &RestoreBatchDeletedFileItem,
) -> bool {
    state.path == inverse.restore_path
        && state.current_name == inverse.restore_name
        && state.category == inverse.restore_category
}

fn ensure_restore_batch_file_state_kind(inverse: &RestoreBatchFileStateInverse) -> CoreResult<()> {
    if inverse.kind == "restore_batch_file_state" && !inverse.items.is_empty() {
        Ok(())
    } else {
        Err(CoreError::conflict("Unsupported redo inverse"))
    }
}

fn ensure_restore_batch_deleted_files_kind(
    inverse: &RestoreBatchDeletedFilesInverse,
) -> CoreResult<()> {
    if inverse.kind == "restore_batch_deleted_files" && !inverse.items.is_empty() {
        Ok(())
    } else {
        Err(CoreError::conflict("Unsupported redo inverse"))
    }
}
