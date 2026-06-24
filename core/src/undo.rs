//! undo action log contract types and entry points.

use std::path::{Component, PathBuf};

use rusqlite::params;
use serde::{Deserialize, Serialize};

use crate::storage::history as fs_ops;
use crate::{db, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const UNDO_ACTION_LIMIT: i64 = 100;
const BATCH_ADD_TAGS_KIND: &str = "batch_add_tags";

pub(crate) mod batch_file_actions;
pub(crate) mod file_actions;
mod records;
mod tags;

use file_actions::{
    BATCH_CHANGE_CATEGORY_KIND, CHANGE_CATEGORY_KIND, MOVE_FILES_KIND, RENAME_FILES_KIND,
    TRASH_DELETE_KIND,
};

/// Lifecycle state for an undo action.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum UndoActionStatus {
    /// The action can still be executed.
    Pending,
    /// The action has already been executed.
    Executed,
    /// The action is no longer available because its lifetime ended.
    Expired,
    /// The action cannot be executed until the user reviews the blocking reason.
    Blocked,
}

/// One row returned to undo toast and undo history consumers.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct UndoActionRecord {
    /// Stable action identifier, backed by `undo_actions.token`.
    pub action_id: String,
    /// Stable action kind, such as `batch_add_tags`, `move_files`, or `rename_files`.
    pub kind: String,
    /// Display-ready operation summary for toast and history rows.
    pub summary: String,
    /// Number of affected files or relations.
    pub affected_count: i64,
    /// Sample file names for the history preview.
    pub affected_file_names: Vec<String>,
    /// Current undo lifecycle state.
    pub status: UndoActionStatus,
    /// Whether the latest action can be executed through `undo_action`.
    pub can_undo: bool,
    /// User-visible reason when the action is blocked or expired.
    pub disabled_reason: Option<String>,
    /// Unix timestamp when the action was created.
    pub created_at: i64,
    /// Unix timestamp when the action state last changed.
    pub updated_at: i64,
}

/// Result returned after executing one undo action.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct UndoActionResult {
    /// Stable action identifier that was requested.
    pub action_id: String,
    /// Final lifecycle state after the undo attempt.
    pub status: UndoActionStatus,
    /// Display-ready completion or failure summary.
    pub summary: String,
    /// Number of affected files or relations.
    pub affected_count: i64,
    /// Stable refresh hints for UI stores after a successful undo.
    pub refresh_targets: Vec<String>,
    /// Unix timestamp when execution completed.
    pub completed_at: i64,
}

/// Lists undo actions for the toast and history surfaces.
///
/// The contract returns enough state for undo toast surface and undo history surface to render available,
/// blocked, expired, and already executed actions without parsing raw
/// `summary_json` or `inverse_json`. Listing is metadata-only and must not
/// execute undo, redo, file moves, Trash restore, tag mutation, or filesystem
/// repair behavior.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` when undo metadata is unavailable.
/// Later implementation may also surface `CoreError::Io { message }` for
/// metadata summary material that cannot be decoded.
pub fn list_undo_actions(repo_path: String) -> CoreResult<Vec<UndoActionRecord>> {
    let repo = validate_undo_repo_path(&repo_path)?;
    db::ensure_initialized(&repo).map_err(normalize_undo_metadata_error)?;
    list_undo_action_rows(&repo).map_err(normalize_undo_metadata_error)
}

/// Executes one undo action.
///
/// `action_id` maps to the `undo_actions.token` value returned by
/// [`list_undo_actions`] or by an operation result such as batch tag mutation
/// `BatchMutationReport::undo_token`. This entry point owns Undo only; redo
/// stack execution stays with redo action log and is not hidden behind this API.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when `action_id` is empty or no
/// pending undo action exists. Implementations must return `CoreError::Conflict
/// { path }` for blocked inverse operations, `CoreError::PermissionDenied {
/// path }` for permission or Trash restore failures, `CoreError::Db { message
/// }` for undo metadata failures, and `CoreError::Io { message }` for
/// filesystem failures. Failed undo must not corrupt the current repository
/// state or partially mark an action as executed.
pub fn undo_action(repo_path: String, action_id: String) -> CoreResult<UndoActionResult> {
    let repo = validate_undo_repo_path(&repo_path)?;
    let normalized_action_id = action_id.trim();
    if normalized_action_id.is_empty() {
        return Err(CoreError::file_not_found("undo action is required"));
    }
    db::ensure_initialized(&repo).map_err(normalize_undo_metadata_error)?;
    execute_undo_action_row(&repo, normalized_action_id).map_err(normalize_undo_metadata_error)
}

fn list_undo_action_rows(repo_path: &std::path::Path) -> CoreResult<Vec<UndoActionRecord>> {
    let connection = db::open_repo_connection(repo_path)?;
    records::ensure_undo_metadata_ready(&connection)?;
    records::load_undo_actions(repo_path, &connection)
}

fn execute_undo_action_row(
    repo_path: &std::path::Path,
    action_id: &str,
) -> CoreResult<UndoActionResult> {
    let mut connection = db::open_repo_connection(repo_path)?;
    records::ensure_undo_metadata_ready(&connection)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    let row = records::load_pending_action(&tx, action_id)?;
    let completed_at = chrono::Utc::now().timestamp();

    if row.kind == BATCH_ADD_TAGS_KIND {
        let result = tags::execute_batch_tag_action(&tx, &row, completed_at)?;
        tx.commit()
            .map_err(|error| CoreError::db(error.to_string()))?;
        return Ok(result);
    }

    if file_actions::is_file_action_kind(&row.kind) {
        let mut execution = file_actions::execute_file_action(
            &tx,
            repo_path,
            &row.kind,
            &row.inverse_json,
            &row.token,
            completed_at,
        )?;
        mark_action_status(&tx, row.token.as_str(), "executed", completed_at)?;
        tx.commit()
            .map_err(|error| CoreError::db(error.to_string()))?;
        execution.disarm();
        return Ok(UndoActionResult {
            action_id: row.token,
            status: UndoActionStatus::Executed,
            summary: execution.summary,
            affected_count: execution.affected_count,
            refresh_targets: execution.refresh_targets,
            completed_at,
        });
    }

    if row.kind == "icloud_conflict_resolution" {
        return Err(CoreError::conflict(
            "iCloud conflict resolution undo requires manual review",
        ));
    }

    Err(CoreError::conflict("Unsupported undo action kind"))
}

fn mark_action_status(
    connection: &rusqlite::Connection,
    action_id: &str,
    status: &str,
    updated_at: i64,
) -> CoreResult<()> {
    let changed = connection
        .execute(
            "UPDATE undo_actions
                SET status = ?1, updated_at = ?2
              WHERE token = ?3 AND status = 'pending'",
            params![status, updated_at, action_id],
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::file_not_found(action_id.to_owned()))
    }
}

fn validate_undo_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::db("undo metadata is unavailable"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::db("undo metadata is unavailable"));
    }
    Ok(repo)
}

fn normalize_undo_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => CoreError::db("undo metadata is unavailable"),
        CoreError::PermissionDenied { .. } => CoreError::permission_denied("permission denied"),
        CoreError::Io { .. } => CoreError::io("undo metadata io unavailable"),
        other => other,
    }
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}
