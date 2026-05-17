use std::path::Path;

use rusqlite::params;
use serde::Deserialize;
use serde_json::Value;

use crate::{CoreError, CoreResult};

use super::file_actions::{insert_file_undo_change, FileDbState, FileUndoExecution};
use super::fs_ops::{move_checked_path, repo_relative_path, FileMoveRollbackGuard};

#[derive(Debug, Deserialize)]
pub(super) struct RestoreBatchFileStateInverse {
    pub(super) kind: String,
    pub(super) operation: String,
    pub(super) items: Vec<RestoreBatchFileStateItem>,
}

#[derive(Debug, Deserialize)]
pub(super) struct RestoreBatchFileStateItem {
    pub(super) file_id: i64,
    pub(super) expected_path: String,
    pub(super) expected_name: String,
    pub(super) expected_category: String,
    pub(super) restore_path: String,
    pub(super) restore_name: String,
    pub(super) restore_category: String,
    pub(super) index_only: bool,
}

pub(super) fn parse_restore_batch_file_state(
    value: &Value,
) -> CoreResult<RestoreBatchFileStateInverse> {
    serde_json::from_value(value.clone()).map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn execute_restore_batch_file_state(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    kind: &str,
    inverse: &RestoreBatchFileStateInverse,
    action_id: &str,
    completed_at: i64,
) -> CoreResult<FileUndoExecution> {
    ensure_restore_batch_file_state_kind(inverse)?;
    ensure_batch_db_state_matches(tx, inverse)?;
    let mut guards = move_batch_active_paths(repo, inverse)?;
    if let Err(error) = update_batch_active_file_state(tx, inverse, completed_at) {
        for guard in &mut guards {
            guard.rollback();
        }
        return Err(error);
    }
    for item in &inverse.items {
        insert_file_undo_change(
            tx,
            kind,
            item.file_id,
            action_id,
            completed_at,
            &inverse.operation,
        )?;
    }
    Ok(FileUndoExecution {
        summary: format!("Undone: {}.", inverse.operation),
        affected_count: inverse.items.len() as i64,
        refresh_targets: super::file_actions::file_refresh_targets(kind),
        guards,
    })
}

pub(super) fn batch_file_state_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &RestoreBatchFileStateInverse,
) -> CoreResult<Option<String>> {
    ensure_restore_batch_file_state_kind(inverse)?;
    for item in &inverse.items {
        let Some(state) = super::file_actions::load_file_state(connection, item.file_id)? else {
            return Ok(Some("File no longer exists".to_owned()));
        };
        if state.status != "active" {
            return Ok(Some("File no longer active".to_owned()));
        }
        if !batch_active_state_matches(&state, item) {
            return Ok(Some("File changed after action".to_owned()));
        }
        if item.index_only {
            continue;
        }
        if let Some(reason) = super::file_actions::filesystem_restore_block_reason(
            repo,
            &item.expected_path,
            &item.restore_path,
        )? {
            return Ok(Some(reason));
        }
    }
    Ok(None)
}

fn move_batch_active_paths(
    repo: &Path,
    inverse: &RestoreBatchFileStateInverse,
) -> CoreResult<Vec<FileMoveRollbackGuard>> {
    let mut guards = Vec::new();
    for item in &inverse.items {
        if item.index_only {
            continue;
        }
        let expected_path = repo_relative_path(repo, &item.expected_path)?;
        let restore_path = repo_relative_path(repo, &item.restore_path)?;
        if expected_path == restore_path {
            continue;
        }
        guards.push(move_checked_path(&expected_path, &restore_path)?);
    }
    Ok(guards)
}

fn update_batch_active_file_state(
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
                    item.restore_path,
                    item.restore_name,
                    item.restore_category,
                    updated_at
                ],
            )
            .map_err(|error| CoreError::db(error.to_string()))?;
        super::file_actions::ensure_single_row_changed(changed, item.file_id)?;
    }
    Ok(())
}

fn ensure_batch_db_state_matches(
    connection: &rusqlite::Connection,
    inverse: &RestoreBatchFileStateInverse,
) -> CoreResult<()> {
    for item in &inverse.items {
        let state = super::file_actions::load_file_state(connection, item.file_id)?
            .ok_or_else(|| CoreError::file_not_found(format!("file:{}", item.file_id)))?;
        if state.status != "active" || !batch_active_state_matches(&state, item) {
            return Err(CoreError::conflict("File changed after action"));
        }
    }
    Ok(())
}

fn batch_active_state_matches(state: &FileDbState, inverse: &RestoreBatchFileStateItem) -> bool {
    state.path == inverse.expected_path
        && state.current_name == inverse.expected_name
        && state.category == inverse.expected_category
}

fn ensure_restore_batch_file_state_kind(inverse: &RestoreBatchFileStateInverse) -> CoreResult<()> {
    if inverse.kind == "restore_batch_file_state" && !inverse.items.is_empty() {
        Ok(())
    } else {
        Err(CoreError::conflict("Unsupported undo inverse"))
    }
}
