//! Public FFI history entry points.

use crate::{redo, CoreError, CoreResult, FileEntry, RedoActionRecord, RedoActionResult};

/// Restores a deleted file entry.
pub fn restore_file(_repo_path: String, _file_id: i64) -> CoreResult<FileEntry> {
    Err(CoreError::internal("internal error"))
}
/// Lists redo action state for redo surface.
///
/// redo surface uses this contract in the redo slot of undo toast surface and the redo row of
/// undo history surface. The returned rows expose availability, source undo action, disabled
/// reasons, affected counts, and updated timestamps so the app can render
/// `Redo`, `Redo latest`, `Shift+Cmd+Z`, and VoiceOver state from one stable
/// contract.
///
/// This contract is read-only. It must not execute redo, write undo state,
/// write change-log rows, move files, restore Trash items, retag, reclassify,
/// reindex, trigger iCloud downloads, call AI/network providers, or touch
/// `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` when redo stack metadata cannot be read.
/// Implementations may also return `CoreError::Io { message }` when summary
/// state requires AreaMatrix-owned metadata reads.
pub fn list_redo_actions(repo_path: String) -> CoreResult<Vec<RedoActionRecord>> {
    redo::list_redo_actions(repo_path)
}

/// Executes one redo action after preflight validation.
///
/// `action_id` must reference an available redo row returned by
/// [`list_redo_actions`]. Redo only replays an AreaMatrix action that was
/// previously undone successfully, and successful redo restores the original
/// operation to the undo action log Undo stack. New writes clear redo availability; this
/// API must return a cleared, expired, or blocked result/error rather than
/// replaying across unsafe state.
///
/// This contract does not implement Undo itself, batch actions, import
/// conflict decisions, classifier rules, AI suggestions, remote sync, or a
/// standalone Redo page.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when `action_id` is empty or no
/// redo row exists, `CoreError::ExpiredAction { action_id }` when the row was
/// cleared or expired, `CoreError::Conflict { path }` for external changes,
/// stale state, path conflicts, or Trash preflight failure,
/// `CoreError::PermissionDenied { path }` for blocked metadata, Trash, target-file, or
/// directory permissions, `CoreError::Db { message }` for redo metadata,
/// change-log, or undo-stack writes, and `CoreError::Io { message }` for
/// filesystem execution or rollback failures.
pub fn redo_action(repo_path: String, action_id: String) -> CoreResult<RedoActionResult> {
    redo::redo_action(repo_path, action_id)
}
