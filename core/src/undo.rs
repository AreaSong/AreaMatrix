//! C2-07 undo action log contract types and entry points.

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

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

/// One row returned to C2-07 undo toast and undo history consumers.
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

/// Result returned after executing one C2-07 undo action.
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

/// Lists C2-07 undo actions for the toast and history surfaces.
///
/// The contract returns enough state for S2-10 and S2-11 to render available,
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
    if repo_path.trim().is_empty() {
        return Err(CoreError::db("undo metadata is unavailable"));
    }
    Err(CoreError::db("undo action listing is not implemented"))
}

/// Executes one C2-07 undo action.
///
/// `action_id` maps to the `undo_actions.token` value returned by
/// [`list_undo_actions`] or by an operation result such as C2-06
/// `BatchMutationReport::undo_token`. This entry point owns Undo only; redo
/// stack execution stays with C2-18 and is not hidden behind this API.
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
    if action_id.trim().is_empty() {
        return Err(CoreError::file_not_found("undo action is required"));
    }
    if repo_path.trim().is_empty() {
        return Err(CoreError::db("undo metadata is unavailable"));
    }
    Err(CoreError::db("undo action execution is not implemented"))
}
