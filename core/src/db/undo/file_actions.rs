use std::path::{Path, PathBuf};

use rusqlite::{params, OptionalExtension};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::{CoreError, CoreResult};

use super::batch_file_actions::{
    batch_file_state_block_reason, execute_restore_batch_file_state, parse_restore_batch_file_state,
};
use super::fs_ops::{map_io_error, move_checked_path, repo_relative_path, FileMoveRollbackGuard};

pub(super) const RENAME_FILES_KIND: &str = "rename_files";
pub(super) const MOVE_FILES_KIND: &str = "move_files";
pub(super) const CHANGE_CATEGORY_KIND: &str = "change_category";
pub(super) const BATCH_CHANGE_CATEGORY_KIND: &str = "batch_change_category";
pub(super) const TRASH_DELETE_KIND: &str = "trash_delete";

pub(super) struct FileUndoExecution {
    pub(super) summary: String,
    pub(super) affected_count: i64,
    pub(super) refresh_targets: Vec<String>,
    pub(super) guards: Vec<FileMoveRollbackGuard>,
}

impl FileUndoExecution {
    pub(super) fn disarm(&mut self) {
        for guard in &mut self.guards {
            guard.disarm();
        }
    }
}

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
    trash_path: Option<String>,
    restore_path: String,
    restore_name: String,
    restore_category: String,
}

pub(super) struct FileDbState {
    pub(super) path: String,
    pub(super) current_name: String,
    pub(super) category: String,
    pub(super) status: String,
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

pub(super) fn pending_file_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &Value,
) -> CoreResult<Option<String>> {
    match inverse.get("kind").and_then(Value::as_str) {
        Some("restore_file_state") => {
            let inverse = parse_restore_file_state(inverse)?;
            file_state_block_reason(connection, repo, &inverse)
        }
        Some("restore_batch_file_state") => {
            let inverse = parse_restore_batch_file_state(inverse)?;
            batch_file_state_block_reason(connection, repo, &inverse)
        }
        Some("restore_deleted_file") => {
            let inverse = parse_restore_deleted_file(inverse)?;
            deleted_file_block_reason(connection, repo, &inverse)
        }
        _ => Ok(Some("Unsupported undo inverse".to_owned())),
    }
}

pub(super) fn execute_file_action(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    kind: &str,
    inverse_json: &str,
    action_id: &str,
    completed_at: i64,
) -> CoreResult<FileUndoExecution> {
    let inverse = parse_inverse_value(inverse_json)?;
    match inverse.get("kind").and_then(Value::as_str) {
        Some("restore_file_state") => {
            let inverse = parse_restore_file_state(&inverse)?;
            execute_restore_file_state(tx, repo, kind, &inverse, action_id, completed_at)
        }
        Some("restore_batch_file_state") => {
            let inverse = parse_restore_batch_file_state(&inverse)?;
            execute_restore_batch_file_state(tx, repo, kind, &inverse, action_id, completed_at)
        }
        Some("restore_deleted_file") => {
            let inverse = parse_restore_deleted_file(&inverse)?;
            execute_restore_deleted_file(tx, repo, &inverse, action_id, completed_at)
        }
        _ => Err(CoreError::conflict("Unsupported undo inverse")),
    }
}

fn execute_restore_file_state(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    kind: &str,
    inverse: &RestoreFileStateInverse,
    action_id: &str,
    completed_at: i64,
) -> CoreResult<FileUndoExecution> {
    ensure_restore_file_state_kind(inverse)?;
    ensure_db_state_matches(tx, inverse)?;
    let mut guards = if inverse.index_only {
        Vec::new()
    } else {
        move_active_paths(repo, inverse)?
    };
    if let Err(error) = update_active_file_state(tx, inverse, completed_at) {
        for guard in &mut guards {
            guard.rollback();
        }
        return Err(error);
    }
    insert_file_undo_change(
        tx,
        kind,
        inverse.file_id,
        action_id,
        completed_at,
        &inverse.operation,
    )?;
    Ok(FileUndoExecution {
        summary: format!("Undone: {}.", inverse.operation),
        affected_count: 1,
        refresh_targets: file_refresh_targets(kind),
        guards,
    })
}

fn execute_restore_deleted_file(
    tx: &rusqlite::Transaction<'_>,
    repo: &Path,
    inverse: &RestoreDeletedFileInverse,
    action_id: &str,
    completed_at: i64,
) -> CoreResult<FileUndoExecution> {
    ensure_restore_deleted_file_kind(inverse)?;
    ensure_deleted_db_state_matches(tx, inverse)?;
    let mut guards = restore_deleted_path(repo, inverse)?;
    if let Err(error) = update_deleted_file_state(tx, inverse, completed_at) {
        for guard in &mut guards {
            guard.rollback();
        }
        return Err(error);
    }
    insert_file_undo_change(
        tx,
        TRASH_DELETE_KIND,
        inverse.file_id,
        action_id,
        completed_at,
        "delete",
    )?;
    Ok(FileUndoExecution {
        summary: "Undone: restored deleted file.".to_owned(),
        affected_count: 1,
        refresh_targets: file_refresh_targets(TRASH_DELETE_KIND),
        guards,
    })
}

fn file_state_block_reason(
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
    if !active_state_matches(&state, inverse) {
        return Ok(Some("File changed after action".to_owned()));
    }
    if inverse.index_only {
        return Ok(None);
    }
    filesystem_restore_block_reason(repo, &inverse.expected_path, &inverse.restore_path)
}

fn deleted_file_block_reason(
    connection: &rusqlite::Connection,
    repo: &Path,
    inverse: &RestoreDeletedFileInverse,
) -> CoreResult<Option<String>> {
    ensure_restore_deleted_file_kind(inverse)?;
    let Some(state) = load_file_state(connection, inverse.file_id)? else {
        return Ok(Some("File no longer exists".to_owned()));
    };
    if state.status != "deleted" {
        return Ok(Some("File is not deleted".to_owned()));
    }
    let Some(trash_path) = inverse.trash_path.as_deref() else {
        return Ok(Some("Trash restore location unavailable".to_owned()));
    };
    let trash_path = Path::new(trash_path);
    if !path_exists(trash_path)? {
        return Ok(Some("Trash item no longer exists".to_owned()));
    }
    if !trash_path.metadata().map_err(map_io_error)?.is_file() {
        return Ok(Some("Trash item changed".to_owned()));
    }
    let restore_path = repo_relative_path(repo, &inverse.restore_path)?;
    if path_exists(&restore_path)? {
        return Ok(Some("Original path is occupied".to_owned()));
    }
    Ok(None)
}

pub(super) fn filesystem_restore_block_reason(
    repo: &Path,
    expected_relative: &str,
    restore_relative: &str,
) -> CoreResult<Option<String>> {
    let expected_path = repo_relative_path(repo, expected_relative)?;
    let restore_path = repo_relative_path(repo, restore_relative)?;
    if !path_exists(&expected_path)? {
        return Ok(Some("File no longer exists".to_owned()));
    }
    if !expected_path.metadata().map_err(map_io_error)?.is_file() {
        return Ok(Some("File changed after action".to_owned()));
    }
    if expected_path == restore_path {
        return Ok(None);
    }
    if path_exists(&restore_path)? {
        return Ok(Some("Original path is occupied".to_owned()));
    }
    Ok(None)
}

fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(map_io_error)
}

fn move_active_paths(
    repo: &Path,
    inverse: &RestoreFileStateInverse,
) -> CoreResult<Vec<FileMoveRollbackGuard>> {
    let expected_path = repo_relative_path(repo, &inverse.expected_path)?;
    let restore_path = repo_relative_path(repo, &inverse.restore_path)?;
    if expected_path == restore_path {
        return Ok(Vec::new());
    }
    move_checked_path(&expected_path, &restore_path).map(|guard| vec![guard])
}

fn restore_deleted_path(
    repo: &Path,
    inverse: &RestoreDeletedFileInverse,
) -> CoreResult<Vec<FileMoveRollbackGuard>> {
    let trash_path = inverse
        .trash_path
        .as_ref()
        .ok_or_else(|| CoreError::conflict("Trash restore location unavailable"))?;
    let restore_path = repo_relative_path(repo, &inverse.restore_path)?;
    let trash_path = PathBuf::from(trash_path);
    move_checked_path(&trash_path, &restore_path).map(|guard| vec![guard])
}

fn update_active_file_state(
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
                inverse.restore_path,
                inverse.restore_name,
                inverse.restore_category,
                updated_at
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_single_row_changed(changed, inverse.file_id)
}

fn update_deleted_file_state(
    tx: &rusqlite::Transaction<'_>,
    inverse: &RestoreDeletedFileInverse,
    updated_at: i64,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE files
             SET path = ?2,
                 current_name = ?3,
                 category = ?4,
                 deleted_at = NULL,
                 updated_at = ?5,
                 status = 'active'
             WHERE id = ?1 AND status = 'deleted'",
            params![
                inverse.file_id,
                inverse.restore_path,
                inverse.restore_name,
                inverse.restore_category,
                updated_at
            ],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_single_row_changed(changed, inverse.file_id)
}

pub(super) fn insert_file_undo_change(
    tx: &rusqlite::Transaction<'_>,
    kind: &str,
    file_id: i64,
    action_id: &str,
    occurred_at: i64,
    operation: &str,
) -> CoreResult<()> {
    let action = match kind {
        RENAME_FILES_KIND => "renamed",
        MOVE_FILES_KIND | CHANGE_CATEGORY_KIND | BATCH_CHANGE_CATEGORY_KIND => "moved",
        TRASH_DELETE_KIND => "restored",
        _ => return Err(CoreError::conflict("Unsupported undo action kind")),
    };
    let detail = json!({
        "kind": "undo_file_action",
        "operation": operation,
        "undo_action": action_id,
        "by": "undo",
    });
    let detail_json =
        serde_json::to_string(&detail).map_err(|error| CoreError::internal(error.to_string()))?;
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, ?2, ?3, ?4)",
        params![file_id, action, detail_json, occurred_at],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn ensure_db_state_matches(
    connection: &rusqlite::Connection,
    inverse: &RestoreFileStateInverse,
) -> CoreResult<()> {
    let state = load_file_state(connection, inverse.file_id)?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{}", inverse.file_id)))?;
    if state.status != "active" || !active_state_matches(&state, inverse) {
        return Err(CoreError::conflict("File changed after action"));
    }
    Ok(())
}

fn ensure_deleted_db_state_matches(
    connection: &rusqlite::Connection,
    inverse: &RestoreDeletedFileInverse,
) -> CoreResult<()> {
    let state = load_file_state(connection, inverse.file_id)?
        .ok_or_else(|| CoreError::file_not_found(format!("file:{}", inverse.file_id)))?;
    if state.status != "deleted" {
        return Err(CoreError::conflict("File is not deleted"));
    }
    Ok(())
}

fn active_state_matches(state: &FileDbState, inverse: &RestoreFileStateInverse) -> bool {
    state.path == inverse.expected_path
        && state.current_name == inverse.expected_name
        && state.category == inverse.expected_category
}

pub(super) fn load_file_state(
    connection: &rusqlite::Connection,
    file_id: i64,
) -> CoreResult<Option<FileDbState>> {
    connection
        .query_row(
            "SELECT path, current_name, category, status
               FROM files
              WHERE id = ?1",
            params![file_id],
            |row| {
                Ok(FileDbState {
                    path: row.get(0)?,
                    current_name: row.get(1)?,
                    category: row.get(2)?,
                    status: row.get(3)?,
                })
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn ensure_single_row_changed(changed: usize, file_id: i64) -> CoreResult<()> {
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::file_not_found(format!("file:{file_id}")))
    }
}

pub(super) fn file_refresh_targets(kind: &str) -> Vec<String> {
    let mut targets = vec![
        "files".to_owned(),
        "undo_actions".to_owned(),
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

fn parse_inverse_value(inverse_json: &str) -> CoreResult<Value> {
    serde_json::from_str(inverse_json).map_err(|error| CoreError::db(error.to_string()))
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
        Err(CoreError::conflict("Unsupported undo inverse"))
    }
}

fn ensure_restore_deleted_file_kind(inverse: &RestoreDeletedFileInverse) -> CoreResult<()> {
    if inverse.kind == "restore_deleted_file" {
        Ok(())
    } else {
        Err(CoreError::conflict("Unsupported undo inverse"))
    }
}
