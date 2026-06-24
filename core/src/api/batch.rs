//! Public FFI batch entry points.

use crate::{
    batch_category, batch_delete, batch_rename as batch_rename_mod, BatchCategoryChangeReport,
    BatchCategoryPreviewReport, BatchDeleteMode, BatchDeletePreviewReport, BatchDeleteReport,
    BatchRenamePreviewReport, BatchRenameReport, BatchRenameRule, CoreResult,
};

/// Previews a batch category change for batch change-category surface without side effects.
///
/// The report gives Swift enough state to show selected-file category
/// distribution, per-file target paths, metadata-only rows, skipped rows,
/// blocked rows, and whether Apply can be enabled. `move_repo_owned_files`
/// controls whether repository-owned `Copied` and `Moved` files are planned as
/// filesystem moves; Indexed rows must remain metadata-only either way.
///
/// This preview must not create category folders, move files, update `files`,
/// write `change_log`, create undo actions, update generated overviews, call AI
/// providers, or touch user file contents.
///
/// # Errors
///
/// Returns `CoreError::Classify { reason }` for invalid target categories,
/// `CoreError::FileNotFound { path }` for empty or invalid selections,
/// `CoreError::PermissionDenied { path }` for blocked metadata or filesystem
/// inspection, `CoreError::Io { message }` for preview filesystem failures,
/// and `CoreError::Db { message }` for metadata reads.
pub fn preview_batch_move_to_category(
    repo_path: String,
    file_ids: Vec<i64>,
    target_category: String,
    move_repo_owned_files: bool,
) -> CoreResult<BatchCategoryPreviewReport> {
    batch_category::preview_batch_move_to_category(
        repo_path,
        file_ids,
        target_category,
        move_repo_owned_files,
    )
}

/// Applies a previously previewed batch category change.
///
/// `preview_token` binds Apply to the latest preview for the same selection,
/// target category, move option, and inspected state. Successful rows update
/// `files.category`, optionally update `files.path` for repository-owned
/// files, write `change_log`, and create an undo action log token. Partial
/// failures must be represented per item rather than silently treated as
/// success.
///
/// The operation is limited to batch category change. It must not create new categories,
/// implement classifier rule editing, delete or trash files, rename unrelated
/// files, save searches, retag files, call AI/network providers, or touch
/// `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::Classify { reason }` for invalid target categories,
/// `CoreError::Conflict { path }` for stale previews or unsafe target
/// conflicts, `CoreError::FileNotFound { path }` for invalid selections,
/// `CoreError::PermissionDenied { path }` for blocked filesystem or metadata
/// writes, `CoreError::Io { message }` for file moves, and
/// `CoreError::Db { message }` for metadata, change-log, or undo writes.
pub fn batch_move_to_category(
    repo_path: String,
    file_ids: Vec<i64>,
    target_category: String,
    move_repo_owned_files: bool,
    preview_token: String,
) -> CoreResult<BatchCategoryChangeReport> {
    batch_category::batch_move_to_category(
        repo_path,
        file_ids,
        target_category,
        move_repo_owned_files,
        preview_token,
    )
}

/// Previews a batch delete operation without side effects.
///
/// batch delete confirmation uses this contract to display selected-file impact before enabling a
/// destructive button: repository-owned rows that can move to Trash,
/// index-only or missing rows that can be removed from metadata, blocked rows,
/// Trash availability, and Undo availability. The preview must not move files,
/// remove index rows, write metadata, create undo actions, or touch `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` for empty selections or invalid
/// file ids, `CoreError::PermissionDenied { path }` when Trash or metadata
/// inspection is blocked, `CoreError::Io { message }` for filesystem preview
/// failures, and `CoreError::Db { message }` for metadata reads.
pub fn preview_batch_delete(
    repo_path: String,
    file_ids: Vec<i64>,
    delete_mode: BatchDeleteMode,
) -> CoreResult<BatchDeletePreviewReport> {
    batch_delete::preview_batch_delete(repo_path, file_ids, delete_mode)
}

/// Applies batch deletion for the mode confirmed by batch delete confirmation.
///
/// `preview_token` must come from the last confirmed batch delete preview for the
/// same selection, delete mode, Trash availability, and inspected file state.
/// `MoveToTrash` handles only repository-owned files and must never perform
/// permanent deletion. `RemoveFromIndex` handles index-only or missing rows
/// without touching external source files. Successful writes report per-item
/// status, update metadata/change log, and return an Undo token when undo action log can
/// reverse the operation.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` for empty selections or invalid
/// ids, `CoreError::Conflict { path }` when Apply is not bound to the current
/// preview state, `CoreError::PermissionDenied { path }` when Trash or metadata
/// writes are blocked, `CoreError::Io { message }` for Trash or filesystem
/// failures, and `CoreError::Db { message }` for metadata, change-log, or undo
/// writes.
pub fn batch_delete_to_trash(
    repo_path: String,
    file_ids: Vec<i64>,
    delete_mode: BatchDeleteMode,
    preview_token: String,
) -> CoreResult<BatchDeleteReport> {
    batch_delete::batch_delete_to_trash(repo_path, file_ids, delete_mode, preview_token)
}

/// Previews a batch rename operation without side effects.
///
/// batch rename surface uses this contract to display each selected row's original name,
/// generated new name, blocking status, index-only display-name behavior,
/// conflicts, and whether Apply can be enabled. `file_ids` order represents
/// the current list order and is part of the preview state for sequence naming.
/// The preview must not rename files, update metadata, write change log, create
/// undo actions, change extensions, delete or Trash files, or touch `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for invalid repo paths or rename
/// rules, `CoreError::FileNotFound { path }` for empty selections or invalid
/// file ids, `CoreError::Conflict { path }` when a conflict cannot be returned
/// as row state, `CoreError::PermissionDenied { path }` for blocked metadata or
/// filesystem inspection, `CoreError::Io { message }` for preview filesystem
/// failures, and `CoreError::Db { message }` for metadata reads.
pub fn preview_batch_rename(
    repo_path: String,
    file_ids: Vec<i64>,
    rule: BatchRenameRule,
) -> CoreResult<BatchRenamePreviewReport> {
    batch_rename_mod::preview_batch_rename(repo_path, file_ids, rule)
}

/// Applies a previously previewed batch rename operation.
///
/// `preview_token` must come from the last batch rename preview for the same
/// selection order, rename rule, and inspected file state. Successful rows
/// rename repository-owned files or update index-only display names, update
/// metadata, write change-log rows, and return an undo action log token when Undo can
/// reverse the operation.
///
/// This operation is limited to batch rename. It must not implement AI naming, change
/// file extensions, overwrite existing files, delete or Trash files,
/// recategorize files, retag files, save searches, reindex, call AI/network
/// providers, or touch `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for invalid repo paths or rename
/// rules, `CoreError::Conflict { path }` for stale previews or unsafe target
/// conflicts, `CoreError::FileNotFound { path }` for invalid selections,
/// `CoreError::PermissionDenied { path }` for blocked filesystem or metadata
/// writes, `CoreError::Io { message }` for rename failures, and
/// `CoreError::Db { message }` for metadata, change-log, or undo writes.
pub fn batch_rename(
    repo_path: String,
    file_ids: Vec<i64>,
    rule: BatchRenameRule,
    preview_token: String,
) -> CoreResult<BatchRenameReport> {
    batch_rename_mod::batch_rename(repo_path, file_ids, rule, preview_token)
}
