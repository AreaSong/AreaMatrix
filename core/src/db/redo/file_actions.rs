use std::path::Path;

use rusqlite::params;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::{CoreError, CoreResult};

use super::{
    batch_file_actions::{
        batch_deleted_files_redo_block_reason, batch_file_state_redo_block_reason,
        execute_restore_batch_deleted_files_redo, execute_restore_batch_file_state_redo,
        parse_restore_batch_deleted_files, parse_restore_batch_file_state,
    },
    change_log::insert_change_log,
    file_state::{ensure_single_row_changed, load_file_state, FileDbState},
    fs_ops, records, RedoExecution, StoredRedoAction, BATCH_CHANGE_CATEGORY_KIND,
    CHANGE_CATEGORY_KIND, MOVE_FILES_KIND, RENAME_FILES_KIND, TRASH_DELETE_KIND,
};

#[derive(Debug, Deserialize)]
struct RestoreFileStateInverse {
    kind: String,
    file_id: i64,
    operation: String,
    expected_path: String,
    expected_name: String,
    expected_category: String,
    restore_path: String,
    restore_name: String,
    restore_category: String,
    index_only: bool,
}

#[derive(Debug, Deserialize)]
struct RestoreDeletedFileInverse {
    kind: String,
    file_id: i64,
    #[serde(rename = "trash_path")]
    _trash_path: Option<String>,
    restore_path: String,
    restore_name: String,
    restore_category: String,
}

pub(super) fn is_file_action_kind(kind: &str) -> bool {
    matches!(
        kind,
        RENAME_FILES_KIND
            | MOVE_FILES_KIND
            | CHANGE_CATEGORY_KIND
            | BATCH_CHANGE_CATEGORY_KIND
            | TRASH_DELETE_KIND
    )
}

pub(super) fn execute_file_redo(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    row: &StoredRedoAction,
    completed_at: i64,
) -> CoreResult<RedoExecution> {
    let inverse = records::parse_inverse_value(&row.inverse_json)?;
    match inverse.get("kind").and_then(Value::as_str) {
        Some("restore_file_state") => {
            let inverse = parse_restore_file_state(&inverse)?;
            execute_restore_file_state_redo(tx, repo, &row.kind, &inverse, completed_at)
        }
        Some("restore_batch_file_state") => {
            let inverse = parse_restore_batch_file_state(&inverse)?;
            execute_restore_batch_file_state_redo(tx, repo, &row.kind, &inverse, completed_at)
        }
        Some("restore_deleted_file") => {
            let inverse = parse_restore_deleted_file(&inverse)?;
            execute_restore_deleted_file_redo(tx, repo, &inverse, completed_at)
        }
        Some("restore_batch_deleted_files") => {
            let inverse = parse_restore_batch_deleted_files(&inverse)?;
            execute_restore_batch_deleted_files_redo(tx, repo, &inverse, completed_at)
        }
        _ => Err(CoreError::conflict("Unsupported redo inverse")),
    }
}

pub(super) fn file_redo_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &Value,
) -> CoreResult<Option<String>> {
    match inverse.get("kind").and_then(Value::as_str) {
        Some("restore_file_state") => {
            let inverse = parse_restore_file_state(inverse)?;
            file_state_redo_block_reason(connection, repo, &inverse)
        }
        Some("restore_batch_file_state") => {
            let inverse = parse_restore_batch_file_state(inverse)?;
            batch_file_state_redo_block_reason(connection, repo, &inverse)
        }
        Some("restore_deleted_file") => {
            let inverse = parse_restore_deleted_file(inverse)?;
            deleted_file_redo_block_reason(connection, repo, &inverse)
        }
        Some("restore_batch_deleted_files") => {
            let inverse = parse_restore_batch_deleted_files(inverse)?;
            batch_deleted_files_redo_block_reason(connection, repo, &inverse)
        }
        _ => Ok(Some("Unsupported redo inverse".to_owned())),
    }
}

fn execute_restore_file_state_redo(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    kind: &str,
    inverse: &RestoreFileStateInverse,
    completed_at: i64,
) -> CoreResult<RedoExecution> {
    ensure_restore_file_state_kind(inverse)?;
    ensure_file_state_matches_restored(tx, inverse)?;
    let mut guards = if inverse.index_only {
        Vec::new()
    } else {
        move_redo_active_path(repo, &inverse.restore_path, &inverse.expected_path)?
    };
    if let Err(error) = update_active_file_state_to_expected(tx, inverse, completed_at) {
        for guard in &mut guards {
            guard.rollback();
        }
        return Err(error);
    }
    insert_file_redo_change(tx, kind, inverse.file_id, completed_at, &inverse.operation)?;
    Ok(RedoExecution {
        summary: format!("Redone: {}.", inverse.operation),
        affected_count: 1,
        refresh_targets: file_refresh_targets(kind),
        guards,
    })
}

fn execute_restore_deleted_file_redo(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    inverse: &RestoreDeletedFileInverse,
    completed_at: i64,
) -> CoreResult<RedoExecution> {
    ensure_restore_deleted_file_kind(inverse)?;
    ensure_deleted_file_matches_restored(tx, inverse)?;
    let current_path = fs_ops::repo_relative_path(repo, &inverse.restore_path)?;
    let mut guards = vec![fs_ops::move_path_to_user_trash(&current_path)?];
    if let Err(error) = update_deleted_file_state_to_deleted(tx, inverse, completed_at) {
        for guard in &mut guards {
            guard.rollback();
        }
        return Err(error);
    }
    insert_file_redo_change(
        tx,
        TRASH_DELETE_KIND,
        inverse.file_id,
        completed_at,
        "delete",
    )?;
    Ok(RedoExecution {
        summary: "Redone: moved file to Trash.".to_owned(),
        affected_count: 1,
        refresh_targets: file_refresh_targets(TRASH_DELETE_KIND),
        guards,
    })
}

fn file_state_redo_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &RestoreFileStateInverse,
) -> CoreResult<Option<String>> {
    ensure_restore_file_state_kind(inverse)?;
    let Some(state) = load_file_state(connection, inverse.file_id)? else {
        return Ok(Some("File no longer exists".to_owned()));
    };
    if state.status != "active" {
        return Ok(Some("File no longer active".to_owned()));
    }
    if !state_matches_restored(&state, inverse) {
        return Ok(Some("File changed after undo".to_owned()));
    }
    if inverse.index_only {
        return Ok(None);
    }
    filesystem_redo_block_reason(repo, &inverse.restore_path, &inverse.expected_path)
}

fn deleted_file_redo_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &RestoreDeletedFileInverse,
) -> CoreResult<Option<String>> {
    ensure_restore_deleted_file_kind(inverse)?;
    let Some(state) = load_file_state(connection, inverse.file_id)? else {
        return Ok(Some("File no longer exists".to_owned()));
    };
    if state.status != "active" || !deleted_state_matches_restored(&state, inverse) {
        return Ok(Some("File changed after undo".to_owned()));
    }
    let current_path = fs_ops::repo_relative_path(repo, &inverse.restore_path)?;
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
    Ok(None)
}

fn update_active_file_state_to_expected(
    tx: &rusqlite::Transaction<'_>,
    inverse: &RestoreFileStateInverse,
    updated_at: i64,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET path = ?2,
                 current_name = ?3,
                 category = ?4,
                 updated_at = ?5
             WHERE id = ?1 AND status = 'active'",
            params![
                inverse.file_id,
                inverse.expected_path,
                inverse.expected_name,
                inverse.expected_category,
                updated_at
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_single_row_changed(changed, inverse.file_id)
}

fn update_deleted_file_state_to_deleted(
    tx: &rusqlite::Transaction<'_>,
    inverse: &RestoreDeletedFileInverse,
    updated_at: i64,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET deleted_at = ?2,
                 updated_at = ?2,
                 status = 'deleted'
             WHERE id = ?1 AND status = 'active'",
            params![inverse.file_id, updated_at],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_single_row_changed(changed, inverse.file_id)
}

fn ensure_file_state_matches_restored(
    connection: &rusqlite::Connection,
    inverse: &RestoreFileStateInverse,
) -> CoreResult<()> {
    let state = load_file_state(connection, inverse.file_id)?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{}", inverse.file_id)))?;
    if state.status != "active" || !state_matches_restored(&state, inverse) {
        return Err(CoreError::conflict("File changed after undo"));
    }
    Ok(())
}

fn ensure_deleted_file_matches_restored(
    connection: &rusqlite::Connection,
    inverse: &RestoreDeletedFileInverse,
) -> CoreResult<()> {
    let state = load_file_state(connection, inverse.file_id)?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{}", inverse.file_id)))?;
    if state.status != "active" || !deleted_state_matches_restored(&state, inverse) {
        return Err(CoreError::conflict("File changed after undo"));
    }
    Ok(())
}

fn state_matches_restored(state: &FileDbState, inverse: &RestoreFileStateInverse) -> bool {
    state.path == inverse.restore_path
        && state.current_name == inverse.restore_name
        && state.category == inverse.restore_category
}

fn deleted_state_matches_restored(
    state: &FileDbState,
    inverse: &RestoreDeletedFileInverse,
) -> bool {
    state.path == inverse.restore_path
        && state.current_name == inverse.restore_name
        && state.category == inverse.restore_category
}

fn move_redo_active_path(
    repo: &Path,
    restored_relative: &str,
    expected_relative: &str,
) -> CoreResult<Vec<fs_ops::FileMoveRollbackGuard>> {
    let restored_path = fs_ops::repo_relative_path(repo, restored_relative)?;
    let expected_path = fs_ops::repo_relative_path(repo, expected_relative)?;
    if restored_path == expected_path {
        return Ok(Vec::new());
    }
    fs_ops::move_checked_path(&restored_path, &expected_path).map(|guard| vec![guard])
}

pub(super) fn filesystem_redo_block_reason(
    repo: &Path,
    restored_relative: &str,
    expected_relative: &str,
) -> CoreResult<Option<String>> {
    let restored_path = fs_ops::repo_relative_path(repo, restored_relative)?;
    let expected_path = fs_ops::repo_relative_path(repo, expected_relative)?;
    if !fs_ops::path_exists(&restored_path)? {
        return Ok(Some("File no longer exists".to_owned()));
    }
    if !restored_path
        .metadata()
        .map_err(fs_ops::map_io_error)?
        .is_file()
    {
        return Ok(Some("File changed after undo".to_owned()));
    }
    if restored_path == expected_path {
        return Ok(None);
    }
    if fs_ops::path_exists(&expected_path)? {
        return Ok(Some("Redo destination is occupied".to_owned()));
    }
    Ok(None)
}

pub(super) fn insert_file_redo_change(
    tx: &rusqlite::Transaction<'_>,
    kind: &str,
    file_id: i64,
    occurred_at: i64,
    operation: &str,
) -> CoreResult<()> {
    let action = match kind {
        RENAME_FILES_KIND => "renamed",
        MOVE_FILES_KIND | CHANGE_CATEGORY_KIND | BATCH_CHANGE_CATEGORY_KIND => "moved",
        TRASH_DELETE_KIND => "deleted",
        _ => return Err(CoreError::conflict("Unsupported redo action kind")),
    };
    let detail = json!({
        "kind": "redo_file_action",
        "operation": operation,
        "by": "redo",
    });
    insert_change_log(tx, file_id, action, &detail, occurred_at)
}

pub(super) fn file_refresh_targets(kind: &str) -> Vec<String> {
    let mut targets = vec![
        "files".to_owned(),
        "undo_actions".to_owned(),
        "redo_actions".to_owned(),
        "change_log".to_owned(),
        "selection".to_owned(),
    ];
    if matches!(
        kind,
        MOVE_FILES_KIND | CHANGE_CATEGORY_KIND | TRASH_DELETE_KIND
    ) {
        targets.push("tree".to_owned());
    }
    targets
}

fn parse_restore_file_state(value: &Value) -> CoreResult<RestoreFileStateInverse> {
    serde_json::from_value(value.clone()).map_err(|error| CoreError::db(error.to_string()))
}

fn parse_restore_deleted_file(value: &Value) -> CoreResult<RestoreDeletedFileInverse> {
    serde_json::from_value(value.clone()).map_err(|error| CoreError::db(error.to_string()))
}

fn ensure_restore_file_state_kind(inverse: &RestoreFileStateInverse) -> CoreResult<()> {
    if inverse.kind == "restore_file_state" {
        Ok(())
    } else {
        Err(CoreError::conflict("Unsupported redo inverse"))
    }
}

fn ensure_restore_deleted_file_kind(inverse: &RestoreDeletedFileInverse) -> CoreResult<()> {
    if inverse.kind == "restore_deleted_file" {
        Ok(())
    } else {
        Err(CoreError::conflict("Unsupported redo inverse"))
    }
}
