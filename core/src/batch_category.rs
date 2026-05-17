//! C2-08 batch category change types and entry points.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{classify, db, CoreError, CoreResult, FileEntry, StorageMode};

mod apply;
mod path_plan;
mod plan;
mod token;

const AREA_MATRIX_DIR: &str = ".areamatrix";

/// Preview row status for a C2-08 batch category change.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BatchCategoryPreviewStatus {
    /// Repo-owned file would be moved into the target category folder.
    WillMove,
    /// Indexed or metadata-only row would update category without moving a source file.
    MetadataOnly,
    /// The file is already in the requested category and has no effective change.
    Unchanged,
    /// The row is intentionally skipped, for example because the physical file is missing.
    Skipped,
    /// The row blocks Apply until the user changes options or resolves the issue.
    Blocked,
}

/// Execution row status for a C2-08 batch category change.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BatchCategoryResultStatus {
    /// Repo-owned file was moved and metadata was updated.
    Moved,
    /// Category metadata was updated without moving a source file.
    MetadataUpdated,
    /// The file already matched the target state.
    Unchanged,
    /// The row was skipped by the batch policy.
    Skipped,
    /// The row failed and carries a per-item error summary.
    Failed,
}

/// Current category distribution for the selected files.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CategoryDistributionItem {
    /// Category slug.
    pub category: String,
    /// Number of selected active files in this category.
    pub count: i64,
}

/// Per-file preview row returned before applying a C2-08 batch category change.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchCategoryPreviewItem {
    /// Requested file id.
    pub file_id: i64,
    /// Category before Apply, when the active file row can be inspected.
    pub from_category: Option<String>,
    /// Requested target category.
    pub to_category: String,
    /// Current entry path before Apply, when available.
    pub current_path: Option<String>,
    /// Target path Apply would use, when the row can be planned.
    pub target_path: Option<String>,
    /// Target filename Apply would use, when the row can be planned.
    pub target_name: Option<String>,
    /// Storage mode, when the active file row can be inspected.
    pub storage_mode: Option<StorageMode>,
    /// Whether Apply would be metadata-only for this row.
    pub index_only: bool,
    /// Whether Apply would physically move a repo-owned file.
    pub will_move_file: bool,
    /// Stable preview status for UI summaries and VoiceOver.
    pub status: BatchCategoryPreviewStatus,
    /// Optional per-row reason for skipped or blocked states.
    pub reason: Option<String>,
}

/// Read-only preview report consumed by S2-12 before Apply is enabled.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchCategoryPreviewReport {
    /// Number of unique file ids accepted by the contract.
    pub requested_file_count: i64,
    /// Requested target category.
    pub target_category: String,
    /// Whether repo-owned files are allowed to move to the category folder.
    pub move_repo_owned_files: bool,
    /// Token that binds Apply to this preview request and inspected state.
    pub preview_token: String,
    /// Category distribution across the inspected selection.
    pub category_distribution: Vec<CategoryDistributionItem>,
    /// Number of rows that would move repo-owned files.
    pub will_move_count: i64,
    /// Number of rows that would only update metadata.
    pub metadata_only_count: i64,
    /// Number of rows that are already in the requested target state.
    pub unchanged_count: i64,
    /// Number of rows skipped by policy.
    pub skipped_count: i64,
    /// Number of rows blocking Apply.
    pub blocked_count: i64,
    /// Detailed preview rows for the full impact table.
    pub items: Vec<BatchCategoryPreviewItem>,
    /// Whether Apply may be called with this report's `preview_token`.
    pub can_apply: bool,
    /// User-displayable reason when Apply is disabled.
    pub apply_blocked_reason: Option<String>,
}

/// Per-file execution result returned after a C2-08 batch category change.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchCategoryChangeItemResult {
    /// Requested file id.
    pub file_id: i64,
    /// Category before Apply, when available.
    pub from_category: Option<String>,
    /// Requested target category.
    pub to_category: String,
    /// Final entry path, when the row succeeded.
    pub final_path: Option<String>,
    /// Stable execution status for S2-12 summaries.
    pub status: BatchCategoryResultStatus,
    /// Optional failure or skip reason.
    pub error: Option<String>,
}

/// Execution report returned to S2-12 and C2-07 undo consumers.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchCategoryChangeReport {
    /// Number of unique file ids accepted by the contract.
    pub requested_file_count: i64,
    /// Requested target category.
    pub target_category: String,
    /// Number of repo-owned files moved.
    pub moved_count: i64,
    /// Number of metadata-only category updates.
    pub metadata_only_count: i64,
    /// Number of rows already matching the requested target state.
    pub unchanged_count: i64,
    /// Number of rows skipped by policy.
    pub skipped_count: i64,
    /// Number of rows that failed.
    pub failed_count: i64,
    /// Detailed per-file execution results.
    pub item_results: Vec<BatchCategoryChangeItemResult>,
    /// Updated file entries for successful rows.
    pub updated_files: Vec<FileEntry>,
    /// Undo token for C2-07 toast/history when successful writes create one.
    pub undo_token: Option<String>,
}

/// Previews a C2-08 batch category change without mutating files or metadata.
///
/// S2-12 uses this API to show current category distribution, target paths,
/// metadata-only rows, skipped rows, blocked rows, and the `preview_token`
/// required by [`batch_move_to_category`]. This entry point must remain
/// side-effect free: it does not create category folders, move files, update
/// `files`, write `change_log`, or create undo actions.
///
/// # Errors
///
/// Returns `CoreError::Classify { reason }` for missing or invalid target
/// categories, `CoreError::FileNotFound { path }` for an empty selection or
/// invalid ids, `CoreError::PermissionDenied { path }` for blocked metadata or
/// filesystem inspection, `CoreError::Io { message }` for preview filesystem
/// failures, and `CoreError::Db { message }` for metadata reads.
pub fn preview_batch_move_to_category(
    repo_path: String,
    file_ids: Vec<i64>,
    target_category: String,
    move_repo_owned_files: bool,
) -> CoreResult<BatchCategoryPreviewReport> {
    let repo = prepare_batch_category_request(&repo_path, &file_ids, &target_category)?;
    let normalized_ids = normalize_batch_category_file_ids(&file_ids)?;
    let plan = plan::build_batch_category_plan(
        &repo,
        &normalized_ids,
        target_category.trim(),
        move_repo_owned_files,
    )?;
    Ok(plan.into_preview_report())
}

/// Applies a C2-08 batch category change that was previously previewed.
///
/// `preview_token` must come from [`preview_batch_move_to_category`] for the
/// same selection, target category, move option, and inspected state. Successful
/// rows update repository metadata, optionally move repo-owned files, write
/// `change_log`, and create one C2-07 undo action for all changed rows.
///
/// # Errors
///
/// Returns `CoreError::Classify { reason }` for missing or invalid target
/// categories, `CoreError::FileNotFound { path }` for an empty selection or
/// invalid ids, `CoreError::Conflict { path }` when Apply is not bound to the
/// current preview state, `CoreError::PermissionDenied { path }` for blocked
/// writes, `CoreError::Io { message }` for file moves, and `CoreError::Db {
/// message }` for metadata, change-log, or undo writes.
pub fn batch_move_to_category(
    repo_path: String,
    file_ids: Vec<i64>,
    target_category: String,
    move_repo_owned_files: bool,
    preview_token: String,
) -> CoreResult<BatchCategoryChangeReport> {
    if preview_token.trim().is_empty() {
        return Err(CoreError::conflict("missing batch category preview"));
    }
    let repo = prepare_batch_category_request(&repo_path, &file_ids, &target_category)?;
    let normalized_ids = normalize_batch_category_file_ids(&file_ids)?;
    let plan = plan::build_batch_category_plan(
        &repo,
        &normalized_ids,
        target_category.trim(),
        move_repo_owned_files,
    )?;
    if plan.preview_token != preview_token {
        return Err(CoreError::conflict("stale batch category preview"));
    }
    if !plan.can_apply() {
        return Err(CoreError::conflict(
            plan.apply_blocked_reason()
                .unwrap_or_else(|| "batch category preview cannot be applied".to_owned()),
        ));
    }
    apply::apply_batch_category_plan(&repo, plan)
}

fn prepare_batch_category_request(
    repo_path: &str,
    file_ids: &[i64],
    target_category: &str,
) -> CoreResult<PathBuf> {
    let repo = validate_batch_category_repo_path(repo_path)
        .map_err(|_| CoreError::db("batch category metadata is unavailable"))?;
    normalize_batch_category_file_ids(file_ids)?;
    validate_target_category(target_category)?;
    db::ensure_initialized(&repo).map_err(normalize_batch_category_metadata_error)?;
    classify::ensure_category_exists(&repo, target_category.trim())?;
    Ok(repo)
}

fn validate_batch_category_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::invalid_path("repository path is required"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::invalid_path("repository path is invalid"));
    }
    Ok(repo)
}

fn normalize_batch_category_file_ids(file_ids: &[i64]) -> CoreResult<Vec<i64>> {
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

fn validate_target_category(target_category: &str) -> CoreResult<()> {
    let trimmed = target_category.trim();
    if trimmed.is_empty()
        || trimmed.contains('/')
        || trimmed.contains('\\')
        || trimmed.contains(':')
        || trimmed.contains('\0')
    {
        return Err(CoreError::classify("target category is invalid"));
    }
    Ok(())
}

fn normalize_batch_category_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => {
            CoreError::db("batch category metadata is unavailable")
        }
        CoreError::PermissionDenied { .. } => {
            CoreError::permission_denied("batch category metadata permission denied")
        }
        CoreError::Io { .. } => CoreError::io("batch category metadata io unavailable"),
        other => other,
    }
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}
