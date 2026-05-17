//! C2-10 batch rename contract types and entry points.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{db, CoreError, CoreResult, FileEntry, StorageMode};

mod apply;
mod plan;
mod plan_name;
mod plan_path;
mod plan_types;
mod token;

const AREA_MATRIX_DIR: &str = ".areamatrix";

/// Batch rename strategy selected by S2-14 before previewing C2-10.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BatchRenameMode {
    /// Prefix the existing stem while preserving the extension.
    Prefix,
    /// Prefix the existing stem with a formatted date while preserving the extension.
    DatePrefix,
    /// Keep the existing stem and append a stable sequence number.
    KeepBaseSequence,
    /// Replace matching text inside the stem while preserving the extension.
    ReplaceText,
}

/// Date source used by [`BatchRenameMode::DatePrefix`].
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BatchRenameDateSource {
    /// Use the file's AreaMatrix imported timestamp.
    Imported,
    /// Use the file's last modified timestamp when available.
    Modified,
    /// Use the current local date at preview time.
    Today,
}

/// Rename rule supplied by S2-14 for preview and Apply.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchRenameRule {
    /// Selected rename strategy.
    pub mode: BatchRenameMode,
    /// Prefix text for `Prefix`.
    pub prefix: Option<String>,
    /// Date source for `DatePrefix`.
    pub date_source: Option<BatchRenameDateSource>,
    /// Date format for `DatePrefix`.
    pub date_format: Option<String>,
    /// Separator for `DatePrefix` and `KeepBaseSequence`.
    pub separator: Option<String>,
    /// Starting sequence number for `KeepBaseSequence`.
    pub start_number: Option<i64>,
    /// Minimum sequence padding for `KeepBaseSequence`.
    pub padding: Option<i64>,
    /// Search text for `ReplaceText`.
    pub find: Option<String>,
    /// Replacement text for `ReplaceText`.
    pub replacement: Option<String>,
    /// Whether `ReplaceText` should match case-sensitively.
    pub case_sensitive: bool,
}

/// Per-file preview status for C2-10 batch rename.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BatchRenamePreviewStatus {
    /// Row can be renamed or display-name updated.
    Ok,
    /// Generated filename is invalid.
    Error,
    /// Generated filename conflicts with another selected row or existing target.
    NameConflict,
    /// The active row or repository-owned file is missing.
    Missing,
    /// File or metadata is not writable.
    ReadOnly,
    /// Indexed row updates AreaMatrix display name only.
    DisplayOnly,
    /// Rule produces no effective change for this row.
    Unchanged,
    /// The file changed after preview and Apply must refresh.
    ExternalChange,
}

/// Per-file execution status for C2-10 batch rename.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum BatchRenameResultStatus {
    /// Repository-owned file was renamed and metadata updated.
    Renamed,
    /// Indexed row display name was updated without touching the source file.
    DisplayNameUpdated,
    /// The rule produced no effective change.
    Unchanged,
    /// Row was intentionally left unchanged.
    Skipped,
    /// Row failed and carries a per-item error summary.
    Failed,
}

/// Conflict detected while previewing generated names.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchRenameConflict {
    /// Requested file id that owns this conflict row.
    pub file_id: i64,
    /// Another selected file id when the conflict is inside the batch.
    pub conflicting_file_id: Option<i64>,
    /// Target path or display name that conflicts.
    pub conflict_path: Option<String>,
    /// Display-ready conflict reason.
    pub reason: String,
}

/// Per-file preview row returned before applying C2-10 batch rename.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchRenamePreviewItem {
    /// Requested file id.
    pub file_id: i64,
    /// Current repository-relative path or external display path, when available.
    pub current_path: Option<String>,
    /// Current display name.
    pub original_name: Option<String>,
    /// Generated name that preserves the original extension.
    pub new_name: Option<String>,
    /// Target repository-relative path for repo-owned files.
    pub target_path: Option<String>,
    /// Storage mode, when the active row can be inspected.
    pub storage_mode: Option<StorageMode>,
    /// Whether Apply would update AreaMatrix display name only.
    pub index_only: bool,
    /// Whether Apply would physically rename a repository-owned file.
    pub will_rename_file: bool,
    /// Stable preview status for S2-14 summaries and VoiceOver.
    pub status: BatchRenamePreviewStatus,
    /// Optional per-row reason for blocked, skipped, or unchanged states.
    pub reason: Option<String>,
}

/// Read-only preview report consumed by S2-14 before Apply is enabled.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchRenamePreviewReport {
    /// Number of unique file ids accepted by the contract.
    pub requested_file_count: i64,
    /// Rule used for this preview.
    pub rule: BatchRenameRule,
    /// Token that binds Apply to this preview request, order, and inspected state.
    pub preview_token: String,
    /// Number of repository-owned files that would be renamed.
    pub will_rename_count: i64,
    /// Number of index-only rows that would update display name only.
    pub display_only_count: i64,
    /// Number of rows with no effective filename change.
    pub unchanged_count: i64,
    /// Number of rows blocking Apply.
    pub blocked_count: i64,
    /// Number of generated-name conflicts.
    pub conflict_count: i64,
    /// Detailed preview rows for the impact table.
    pub items: Vec<BatchRenamePreviewItem>,
    /// Conflict details for S2-14 error rows and accessibility text.
    pub conflicts: Vec<BatchRenameConflict>,
    /// Whether Apply may be called for this preview state.
    pub can_apply: bool,
    /// User-displayable reason when Apply is disabled.
    pub apply_blocked_reason: Option<String>,
}

/// Per-file execution result returned after C2-10 batch rename.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchRenameItemResult {
    /// Requested file id.
    pub file_id: i64,
    /// Display name before Apply, when available.
    pub original_name: Option<String>,
    /// Final display name after Apply, when available.
    pub final_name: Option<String>,
    /// Final path for repo-owned files, when available.
    pub final_path: Option<String>,
    /// Stable execution status for S2-14 result summaries.
    pub status: BatchRenameResultStatus,
    /// Optional failure or skip reason.
    pub error: Option<String>,
}

/// Execution report returned to S2-14 and C2-07 undo consumers.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BatchRenameReport {
    /// Number of unique file ids accepted by the contract.
    pub requested_file_count: i64,
    /// Number of repository-owned files renamed.
    pub renamed_count: i64,
    /// Number of index-only display-name updates.
    pub display_name_updated_count: i64,
    /// Number of rows already matching the requested name.
    pub unchanged_count: i64,
    /// Number of rows intentionally left unchanged.
    pub skipped_count: i64,
    /// Number of rows that failed.
    pub failed_count: i64,
    /// Detailed per-file execution results.
    pub item_results: Vec<BatchRenameItemResult>,
    /// Updated file entries for successful rows.
    pub updated_files: Vec<FileEntry>,
    /// Undo token for C2-07 toast/history when successful writes create one.
    pub undo_token: Option<String>,
}

/// Previews C2-10 batch rename without mutating files or metadata.
///
/// S2-14 uses this API to show each selected file's original name, generated
/// new name, conflict or blocked status, index-only display-name rows, and the
/// `preview_token` required by [`batch_rename`]. The order of `file_ids`
/// represents the current list order and is part of the preview state.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for invalid repo paths or rename
/// rules, `CoreError::FileNotFound { path }` for empty or invalid selections,
/// `CoreError::Conflict { path }` for name conflicts that cannot be represented
/// as per-row preview state, `CoreError::PermissionDenied { path }` for blocked
/// metadata or filesystem inspection, `CoreError::Io { message }` for preview
/// filesystem failures, and `CoreError::Db { message }` for metadata reads.
pub fn preview_batch_rename(
    repo_path: String,
    file_ids: Vec<i64>,
    rule: BatchRenameRule,
) -> CoreResult<BatchRenamePreviewReport> {
    let repo = prepare_batch_rename_request(&repo_path, &file_ids, &rule)?;
    let normalized_ids = normalize_batch_rename_file_ids(&file_ids)?;
    let plan = plan::build_batch_rename_plan(&repo, &normalized_ids, rule)?;
    Ok(plan.into_preview_report())
}

/// Applies a C2-10 batch rename that was previously previewed.
///
/// `preview_token` must come from [`preview_batch_rename`] for the same
/// selection order, rename rule, and inspected file state. Successful rows
/// update repository metadata, rename repository-owned files or update
/// index-only display names, write change-log rows, and create one C2-07 undo
/// action for all changed rows. This API must not change extensions, overwrite
/// existing files, delete or Trash files, retag files, recategorize files, save
/// searches, reindex, or call AI/network providers.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for invalid repo paths or rename
/// rules, `CoreError::Conflict { path }` for missing/stale preview tokens or
/// unsafe target conflicts, `CoreError::FileNotFound { path }` for invalid
/// selections, `CoreError::PermissionDenied { path }` for blocked filesystem or
/// metadata writes, `CoreError::Io { message }` for rename failures, and
/// `CoreError::Db { message }` for metadata, change-log, or undo writes.
pub fn batch_rename(
    repo_path: String,
    file_ids: Vec<i64>,
    rule: BatchRenameRule,
    preview_token: String,
) -> CoreResult<BatchRenameReport> {
    if preview_token.trim().is_empty() {
        return Err(CoreError::conflict("missing batch rename preview"));
    }
    let repo = prepare_batch_rename_request(&repo_path, &file_ids, &rule)?;
    let normalized_ids = normalize_batch_rename_file_ids(&file_ids)?;
    let plan = plan::build_batch_rename_plan(&repo, &normalized_ids, rule)?;
    if plan.preview_token != preview_token {
        return Err(CoreError::conflict("stale batch rename preview"));
    }
    if !plan.can_apply() {
        return Err(CoreError::conflict(
            plan.apply_blocked_reason()
                .unwrap_or_else(|| "batch rename preview cannot be applied".to_owned()),
        ));
    }
    apply::apply_batch_rename_plan(&repo, plan)
}

fn prepare_batch_rename_request(
    repo_path: &str,
    file_ids: &[i64],
    rule: &BatchRenameRule,
) -> CoreResult<PathBuf> {
    let repo = validate_batch_rename_repo_path(repo_path)?;
    normalize_batch_rename_file_ids(file_ids)?;
    validate_batch_rename_rule(rule)?;
    db::ensure_initialized(&repo).map_err(normalize_batch_rename_metadata_error)?;
    Ok(repo)
}

fn validate_batch_rename_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::invalid_path("repository path is required"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::invalid_path("repository path is invalid"));
    }
    Ok(repo)
}

fn normalize_batch_rename_file_ids(file_ids: &[i64]) -> CoreResult<Vec<i64>> {
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

fn validate_batch_rename_rule(rule: &BatchRenameRule) -> CoreResult<()> {
    match rule.mode {
        BatchRenameMode::Prefix => validate_optional_name_part(rule.prefix.as_deref()),
        BatchRenameMode::DatePrefix => {
            require_date_source(rule.date_source.as_ref(), "date source is required")?;
            require_text(rule.date_format.as_deref(), "date format is required")?;
            validate_optional_name_part(rule.separator.as_deref())
        }
        BatchRenameMode::KeepBaseSequence => {
            validate_optional_name_part(rule.separator.as_deref())?;
            require_positive(rule.start_number, "start number is required")?;
            require_non_negative(rule.padding, "padding is required")
        }
        BatchRenameMode::ReplaceText => {
            require_text(rule.find.as_deref(), "find text is required")?;
            validate_optional_name_part(rule.replacement.as_deref())
        }
    }
}

fn require_text(value: Option<&str>, reason: &str) -> CoreResult<()> {
    if value.map(str::trim).unwrap_or_default().is_empty() {
        return Err(CoreError::invalid_path(reason));
    }
    Ok(())
}

fn require_positive(value: Option<i64>, reason: &str) -> CoreResult<()> {
    if value.unwrap_or_default() <= 0 {
        return Err(CoreError::invalid_path(reason));
    }
    Ok(())
}

fn require_non_negative(value: Option<i64>, reason: &str) -> CoreResult<()> {
    if value.unwrap_or(-1) < 0 {
        return Err(CoreError::invalid_path(reason));
    }
    Ok(())
}

fn require_date_source(value: Option<&BatchRenameDateSource>, reason: &str) -> CoreResult<()> {
    if value.is_none() {
        return Err(CoreError::invalid_path(reason));
    }
    Ok(())
}

fn validate_optional_name_part(value: Option<&str>) -> CoreResult<()> {
    if let Some(value) = value {
        if value.chars().any(is_invalid_filename_part_character) {
            return Err(CoreError::invalid_path(
                "rename rule contains invalid filename text",
            ));
        }
    }
    Ok(())
}

fn normalize_batch_rename_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => {
            CoreError::db("batch rename metadata is unavailable")
        }
        CoreError::PermissionDenied { .. } => {
            CoreError::permission_denied("batch rename metadata permission denied")
        }
        CoreError::Io { .. } => CoreError::io("batch rename metadata io unavailable"),
        other => other,
    }
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    component.as_os_str() == AREA_MATRIX_DIR
}

fn is_invalid_filename_part_character(character: char) -> bool {
    character.is_control()
        || matches!(
            character,
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | '\0'
        )
}
