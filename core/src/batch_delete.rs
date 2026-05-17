//! C2-09 batch delete to Trash contract types and entry points.

use std::{
    ffi::OsStr,
    path::{Component, Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use crate::{db, CoreError, CoreResult, StorageMode};

mod apply;
mod inspect;
mod plan;
mod token;

const AREA_MATRIX_DIR: &str = ".areamatrix";

/// Delete mode selected by S2-13 before previewing or applying C2-09.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BatchDeleteMode {
    /// Move repository-owned files to the system Trash.
    MoveToTrash,
    /// Remove index-only or missing rows from AreaMatrix metadata only.
    RemoveFromIndex,
}

/// Per-file preview status for C2-09 batch deletion.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BatchDeletePreviewStatus {
    /// Repository-owned file can be moved to Trash.
    WillMoveToTrash,
    /// Row can be removed from the AreaMatrix index without touching the source file.
    IndexOnly,
    /// Row points to a missing file and can only be removed from metadata.
    Missing,
    /// Row is excluded by the selected delete mode or policy.
    Skipped,
    /// Row blocks Apply until permissions, Trash availability, or external state changes.
    Blocked,
}

/// Per-file result status for C2-09 batch deletion.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BatchDeleteResultStatus {
    /// Repository-owned file was moved to Trash and metadata was soft-deleted.
    MovedToTrash,
    /// Index-only or missing row was removed from active metadata.
    RemovedFromIndex,
    /// Row was intentionally left unchanged.
    Skipped,
    /// Row failed and carries a per-item error summary.
    Failed,
}

/// Per-file preview row returned before applying C2-09 batch deletion.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchDeletePreviewItem {
    /// Requested file id.
    pub file_id: i64,
    /// Current repository-relative path or external display path, when available.
    pub current_path: Option<String>,
    /// Current display name, when the active row can be inspected.
    pub current_name: Option<String>,
    /// Storage mode, when the active row can be inspected.
    pub storage_mode: Option<StorageMode>,
    /// Delete mode used for this preview row.
    pub delete_mode: BatchDeleteMode,
    /// Whether Apply would move the file to the system Trash.
    pub will_move_to_trash: bool,
    /// Whether Apply would only remove AreaMatrix metadata.
    pub will_remove_index: bool,
    /// Stable preview status for S2-13 summaries and VoiceOver.
    pub status: BatchDeletePreviewStatus,
    /// Optional per-row reason for skipped or blocked states.
    pub reason: Option<String>,
}

/// Read-only preview report consumed by S2-13 before destructive actions are enabled.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchDeletePreviewReport {
    /// Number of unique file ids accepted by the contract.
    pub requested_file_count: i64,
    /// Delete mode selected for this preview.
    pub delete_mode: BatchDeleteMode,
    /// Token that binds Apply to this preview request and inspected state.
    pub preview_token: String,
    /// Whether the system Trash is available for repository-owned rows.
    pub trash_available: bool,
    /// Whether successful rows can create a C2-07 undo action.
    pub undo_available: bool,
    /// Number of rows that would move repository-owned files to Trash.
    pub will_trash_count: i64,
    /// Number of rows that can be removed from the index only.
    pub index_only_count: i64,
    /// Number of missing rows that can only be removed from metadata.
    pub missing_count: i64,
    /// Number of rows intentionally excluded by mode or policy.
    pub skipped_count: i64,
    /// Number of rows blocking Apply.
    pub blocked_count: i64,
    /// Detailed preview rows for the impact table.
    pub items: Vec<BatchDeletePreviewItem>,
    /// Whether Apply may be called for this preview state.
    pub can_apply: bool,
    /// User-displayable reason when Apply is disabled.
    pub apply_blocked_reason: Option<String>,
}

/// Per-file execution result returned after C2-09 batch deletion.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchDeleteItemResult {
    /// Requested file id.
    pub file_id: i64,
    /// Last known path for success, skipped, or failed summaries.
    pub final_path: Option<String>,
    /// Stable execution status for S2-13 result summaries.
    pub status: BatchDeleteResultStatus,
    /// Optional failure or skip reason.
    pub error: Option<String>,
}

/// Execution report returned to S2-13 and C2-07 undo consumers.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchDeleteReport {
    /// Number of unique file ids accepted by the contract.
    pub requested_file_count: i64,
    /// Delete mode applied by this request.
    pub delete_mode: BatchDeleteMode,
    /// Number of repository-owned files moved to Trash.
    pub moved_to_trash_count: i64,
    /// Number of index-only or missing rows removed from active metadata.
    pub removed_from_index_count: i64,
    /// Number of rows intentionally left unchanged.
    pub skipped_count: i64,
    /// Number of rows that failed.
    pub failed_count: i64,
    /// Detailed per-file execution results.
    pub item_results: Vec<BatchDeleteItemResult>,
    /// File ids that should be removed or refreshed by list/detail/tree consumers.
    pub affected_file_ids: Vec<i64>,
    /// Undo token for C2-07 toast/history when successful writes create one.
    pub undo_token: Option<String>,
}

/// Previews C2-09 batch deletion without mutating files or metadata.
///
/// S2-13 uses this API to show which selected rows will move to Trash, which
/// rows are index-only or missing metadata removals, which rows are blocked,
/// and whether Undo can be offered. The preview must remain side-effect free:
/// it must not move files to Trash, remove index rows, write `files`, write
/// `change_log`, create undo actions, update generated overviews, call
/// AI/network providers, or touch user file contents.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` for an empty selection or invalid
/// ids, `CoreError::PermissionDenied { path }` when Trash or metadata
/// inspection is blocked, `CoreError::Io { message }` for filesystem preview
/// failures, and `CoreError::Db { message }` for metadata reads.
pub fn preview_batch_delete(
    repo_path: String,
    file_ids: Vec<i64>,
    delete_mode: BatchDeleteMode,
) -> CoreResult<BatchDeletePreviewReport> {
    let repo = prepare_batch_delete_request(&repo_path, &file_ids)?;
    let normalized_ids = normalize_batch_delete_file_ids(&file_ids)?;
    let plan = plan::BatchDeletePlan::build(&repo, normalized_ids, delete_mode)?;
    Ok(plan.into_preview_report())
}

/// Applies C2-09 batch deletion for rows approved by S2-13.
///
/// `preview_token` must come from [`preview_batch_delete`] for the same
/// selection, delete mode, Trash availability, and inspected file state.
/// `BatchDeleteMode::MoveToTrash` is limited to repository-owned files that can
/// be moved to the system Trash. `BatchDeleteMode::RemoveFromIndex` is limited
/// to index-only or missing rows and must never delete, move, rename, overwrite,
/// trash, or otherwise mutate external source files. In short, this mode must
/// not touch external source files. Successful writes must report per-item
/// status, write change-log rows, and create a C2-07 undo token when Undo is
/// available.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` for an empty selection or invalid
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
    if preview_token.trim().is_empty() {
        return Err(CoreError::conflict("missing batch delete preview"));
    }
    let repo = prepare_batch_delete_request(&repo_path, &file_ids)?;
    let normalized_ids = normalize_batch_delete_file_ids(&file_ids)?;
    let plan = plan::BatchDeletePlan::build(&repo, normalized_ids, delete_mode)?;
    if plan.preview_token != preview_token {
        return Err(CoreError::conflict("stale batch delete preview"));
    }
    if !plan.can_apply() {
        return Err(CoreError::conflict(
            plan.apply_blocked_reason()
                .unwrap_or_else(|| "batch delete preview cannot be applied".to_owned()),
        ));
    }
    apply::apply_batch_delete_plan(&repo, plan)
}

fn prepare_batch_delete_request(repo_path: &str, file_ids: &[i64]) -> CoreResult<PathBuf> {
    let repo = validate_batch_delete_repo_path(repo_path)
        .map_err(|_| CoreError::db("batch delete metadata is unavailable"))?;
    normalize_batch_delete_file_ids(file_ids)?;
    db::ensure_initialized(&repo).map_err(normalize_batch_delete_metadata_error)?;
    Ok(repo)
}

fn validate_batch_delete_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::permission_denied("repository path is required"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::permission_denied("repository path is invalid"));
    }
    Ok(repo)
}

fn normalize_batch_delete_file_ids(file_ids: &[i64]) -> CoreResult<Vec<i64>> {
    let mut normalized = Vec::new();
    for file_id in file_ids {
        if *file_id <= 0 {
            return Err(CoreError::file_not_found(format!("file:{file_id}")));
        }
        if !normalized.iter().any(|existing| existing == file_id) {
            normalized.push(*file_id);
        }
    }
    if normalized.is_empty() {
        return Err(CoreError::file_not_found("file:empty"));
    }
    Ok(normalized)
}

fn normalize_batch_delete_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => {
            CoreError::db("batch delete metadata is unavailable")
        }
        CoreError::PermissionDenied { .. } => {
            CoreError::permission_denied("batch delete metadata permission denied")
        }
        CoreError::Io { .. } => CoreError::io("batch delete metadata io unavailable"),
        other => other,
    }
}

fn repo_relative_file_path(repo: &Path, relative_path: &str) -> CoreResult<PathBuf> {
    let relative = Path::new(relative_path);
    validate_repo_relative_path(relative)?;
    Ok(repo.join(relative))
}

fn validate_repo_relative_path(path: &Path) -> CoreResult<()> {
    if path.is_absolute() || path.as_os_str().is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    for component in path.components() {
        let Component::Normal(part) = component else {
            return Err(CoreError::invalid_path("invalid path"));
        };
        if part == OsStr::new(AREA_MATRIX_DIR) {
            return Err(CoreError::invalid_path("invalid path"));
        }
    }
    Ok(())
}

fn error_message(error: CoreError) -> String {
    match error {
        CoreError::Conflict { path } => format!("Conflict: {path}"),
        CoreError::FileNotFound { path } => format!("FileNotFound: {path}"),
        CoreError::PermissionDenied { path } => format!("PermissionDenied: {path}"),
        CoreError::Io { message } => format!("Io: {message}"),
        CoreError::Db { message } => format!("Db: {message}"),
        CoreError::InvalidPath { path } => format!("InvalidPath: {path}"),
        other => other.to_string(),
    }
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}
