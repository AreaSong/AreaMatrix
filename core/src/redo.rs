//! redo action log contract types and entry points.

use std::path::{Component, PathBuf};

use rusqlite::params;
use serde::{Deserialize, Serialize};

use crate::storage::history as fs_ops;
use crate::{db, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
pub(super) const BATCH_ADD_TAGS_KIND: &str = "batch_add_tags";
pub(super) const RENAME_FILES_KIND: &str = "rename_files";
pub(super) const MOVE_FILES_KIND: &str = "move_files";
pub(super) const CHANGE_CATEGORY_KIND: &str = "change_category";
pub(super) const BATCH_CHANGE_CATEGORY_KIND: &str = "batch_change_category";
pub(super) const TRASH_DELETE_KIND: &str = "trash_delete";
pub(super) const REDO_CLEARED_REASON: &str = "Redo action was cleared by a new write";

mod batch_file_actions;
mod change_log;
mod file_actions;
mod file_state;
mod records;
mod tags;

/// Lifecycle state for a redo action.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RedoActionStatus {
    /// The action can still be redone.
    Available,
    /// A new write action has cleared the redo stack.
    Cleared,
    /// The action is blocked until the user reviews the reason.
    Blocked,
    /// The action has expired, for example after app restart.
    Expired,
    /// The redo has already completed.
    Executed,
}

/// One row returned to redo surface consumers.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RedoActionRecord {
    /// Stable redo action identifier, derived from the source undo action.
    pub action_id: String,
    /// Stable action kind, such as `batch_add_tags`, `move_files`, or `trash_delete`.
    pub kind: String,
    /// Display-ready redo summary for toast and history rows.
    pub summary: String,
    /// Number of affected files or relations.
    pub affected_count: i64,
    /// Sample file names for the redo history row.
    pub affected_file_names: Vec<String>,
    /// Current redo lifecycle state.
    pub status: RedoActionStatus,
    /// Whether `redo_action` may execute this row.
    pub can_redo: bool,
    /// User-visible reason when redo is cleared, blocked, or expired.
    pub disabled_reason: Option<String>,
    /// The undo action that created this redo row.
    pub source_undo_action_id: String,
    /// Unix timestamp when the redo action became available.
    pub created_at: i64,
    /// Unix timestamp when the redo action state last changed.
    pub updated_at: i64,
}

/// Result returned after executing one redo action.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RedoActionResult {
    /// Stable redo action identifier that was requested.
    pub action_id: String,
    /// Final lifecycle state after the redo attempt.
    pub status: RedoActionStatus,
    /// Display-ready completion or failure summary.
    pub summary: String,
    /// Number of affected files or relations.
    pub affected_count: i64,
    /// Stable refresh hints for UI stores after a successful redo.
    pub refresh_targets: Vec<String>,
    /// Undo token created when redo restores the original action.
    pub undo_token: Option<String>,
    /// Unix timestamp when execution completed.
    pub completed_at: i64,
}

/// Lists redo actions for redo surface feedback regions.
///
/// The contract returns redo availability, disabled reasons, source undo
/// linkage, and refresh-facing metadata for the redo slot in undo toast surface and the
/// redo row in undo history surface. Listing is metadata-only and must not execute redo, write
/// undo state, write change-log rows, move files, restore Trash items, retag,
/// reclassify, reindex, trigger iCloud downloads, or touch app-layer code.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` when redo metadata is unavailable.
/// Later implementation may also return `CoreError::Io { message }` when
/// metadata summaries require AreaMatrix-owned filesystem reads.
pub fn list_redo_actions(repo_path: String) -> CoreResult<Vec<RedoActionRecord>> {
    let repo = validate_redo_repo_path(&repo_path)?;
    db::ensure_initialized(&repo).map_err(normalize_redo_metadata_error)?;
    list_redo_action_rows(&repo).map_err(normalize_redo_metadata_error)
}

/// Executes one redo action.
///
/// `action_id` maps to an available row returned by [`list_redo_actions`].
/// Redo only replays an AreaMatrix action that was previously undone
/// successfully. New writes clear the redo stack, and external changes must
/// block redo rather than overwriting current filesystem or DB state.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when `action_id` is empty or no
/// redo row exists, `CoreError::ExpiredAction { action_id }` when the row was
/// cleared or expired, `CoreError::Conflict { path }` for external changes or
/// unsafe preflight state, `CoreError::PermissionDenied { path }` for metadata,
/// Trash, target-file, or directory permission failures, `CoreError::Db {
/// message }` for redo metadata failures, and `CoreError::Io { message }` for
/// filesystem failures. Failed redo must preserve the current filesystem and
/// DB state and must not mark unfinished redo as executed.
pub fn redo_action(repo_path: String, action_id: String) -> CoreResult<RedoActionResult> {
    let repo = validate_redo_repo_path(&repo_path)?;
    let normalized_action_id = action_id.trim();
    if normalized_action_id.is_empty() {
        return Err(CoreError::file_not_found("redo action is required"));
    }
    db::ensure_initialized(&repo).map_err(normalize_redo_metadata_error)?;
    execute_redo_action_row(&repo, normalized_action_id).map_err(normalize_redo_metadata_error)
}

fn list_redo_action_rows(repo_path: &std::path::Path) -> CoreResult<Vec<RedoActionRecord>> {
    let connection = db::open_repo_connection(repo_path)?;
    records::ensure_redo_metadata_ready(&connection)?;
    let rows = records::load_redo_actions(&connection)?;
    rows.into_iter()
        .map(|row| records::redo_record_from_row(repo_path, &connection, row))
        .collect()
}

fn execute_redo_action_row(
    repo_path: &std::path::Path,
    action_id: &str,
) -> CoreResult<RedoActionResult> {
    let mut connection = db::open_repo_connection(repo_path)?;
    records::ensure_redo_metadata_ready(&connection)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let row = records::load_executed_action(&tx, action_id)?;
    let completed_at = chrono::Utc::now().timestamp();

    let mut execution = if row.kind == BATCH_ADD_TAGS_KIND {
        tags::execute_batch_tag_redo(&tx, &row, completed_at)?
    } else if file_actions::is_file_action_kind(&row.kind) {
        file_actions::execute_file_redo(&tx, repo_path, &row, completed_at)?
    } else {
        return Err(CoreError::conflict("Unsupported redo action kind"));
    };

    if let Err(error) = restore_pending_undo_action(&tx, row.token.as_str(), completed_at) {
        return Err(fs_ops::rollback_guards_or_error(
            &mut execution.guards,
            error,
        ));
    }
    if let Err(error) = tx
        .commit()
        .map_err(|error| CoreError::db(error.to_string()))
    {
        return Err(fs_ops::rollback_guards_or_error(
            &mut execution.guards,
            error,
        ));
    }
    execution.disarm();

    Ok(RedoActionResult {
        action_id: row.token.clone(),
        status: RedoActionStatus::Executed,
        summary: execution.summary,
        affected_count: execution.affected_count,
        refresh_targets: execution.refresh_targets,
        undo_token: Some(row.token),
        completed_at,
    })
}

#[derive(Debug)]
pub(super) struct StoredRedoAction {
    pub(super) token: String,
    pub(super) kind: String,
    pub(super) summary_json: String,
    pub(super) inverse_json: String,
    pub(super) status: String,
    pub(super) updated_at: i64,
}

struct RedoExecution {
    summary: String,
    affected_count: i64,
    refresh_targets: Vec<String>,
    guards: Vec<fs_ops::FileMoveRollbackGuard>,
}

impl RedoExecution {
    fn disarm(&mut self) {
        for guard in &mut self.guards {
            guard.disarm();
        }
    }
}

fn restore_pending_undo_action(
    tx: &rusqlite::Transaction<'_>,
    action_id: &str,
    updated_at: i64,
) -> CoreResult<()> {
    let changed = tx
        .execute(
            "UPDATE undo_actions
                SET status = 'pending',
                    updated_at = ?2
              WHERE token = ?1 AND status = 'executed'",
            params![action_id, updated_at],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::expired_action(action_id.to_owned()))
    }
}

fn validate_redo_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::db("redo metadata is unavailable"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::db("redo metadata is unavailable"));
    }
    Ok(repo)
}

fn normalize_redo_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => CoreError::db("redo metadata is unavailable"),
        CoreError::PermissionDenied { .. } => CoreError::permission_denied("permission denied"),
        CoreError::Io { .. } => CoreError::io("redo metadata io unavailable"),
        other => other,
    }
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}
