//! C2-17 import conflict batch contract types and entry points.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{db, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";

/// Import conflict type surfaced by S2-21.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ImportConflictBatchConflictType {
    /// Incoming file has the same hash as an active repository file.
    DuplicateHash,
    /// Incoming file has the same target name but different content.
    SameNameDifferentContent,
}

/// Batch strategy selected for one import conflict type.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ImportConflictBatchStrategy {
    /// Skip duplicate content and leave existing files unchanged.
    Skip,
    /// Keep both files, using conflict-free numbering for incoming files.
    KeepBoth,
    /// Replace an existing file only after explicit second confirmation.
    Replace,
    /// Route each item into the Stage 1 per-item conflict flow.
    AskPerItem,
}

/// Per-row preview status returned before applying C2-17.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ImportConflictBatchPreviewStatus {
    /// Row can be processed by the selected strategy.
    Ready,
    /// Row is outside the current scope and remains unresolved in staging.
    Pending,
    /// Row needs second confirmation before Apply may continue.
    NeedsConfirmation,
    /// Row blocks Apply until staging, Trash, or permissions are fixed.
    Blocked,
    /// Row was previously attempted and carries a failure reason.
    Failed,
}

/// Per-row execution status returned after applying C2-17.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ImportConflictBatchResultStatus {
    /// Duplicate row was skipped and the incoming staged file remains non-final.
    Skipped,
    /// Incoming file was imported with conflict-free naming.
    KeptBoth,
    /// Existing file was moved to Trash or recovery storage and replaced.
    Replaced,
    /// Row was routed to the per-item Stage 1 conflict queue.
    QueuedForPerItem,
    /// Row remains outside the current scope.
    Pending,
    /// Row failed and carries a per-item error summary.
    Failed,
}

/// C2-17 preview request for the current import session and scope.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ImportConflictBatchPreviewRequest {
    /// Import session that owns the staged conflict rows.
    pub import_session_id: String,
    /// Conflict ids selected by S2-21; empty is invalid.
    pub conflict_ids: Vec<String>,
    /// Strategy for hash duplicate rows.
    pub duplicate_strategy: ImportConflictBatchStrategy,
    /// Strategy for same-name different-content rows.
    pub same_name_strategy: ImportConflictBatchStrategy,
    /// Whether strategies apply to all current conflicts of the same type.
    pub apply_to_all_similar_conflicts: bool,
}

/// One row in a C2-17 preview report.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ImportConflictBatchPreviewItem {
    /// Stable conflict id from the import session.
    pub conflict_id: String,
    /// Conflict type used for grouping and strategy selection.
    pub conflict_type: ImportConflictBatchConflictType,
    /// Existing active file id when the conflict binds to one.
    pub existing_file_id: Option<i64>,
    /// Existing repository-relative path, when available.
    pub existing_path: Option<String>,
    /// Incoming staged path or display path.
    pub incoming_path: String,
    /// Target path that Apply would use for the incoming file.
    pub target_path: Option<String>,
    /// Strategy selected for this row.
    pub selected_strategy: ImportConflictBatchStrategy,
    /// Stable row status for S2-21 summaries and accessibility.
    pub status: ImportConflictBatchPreviewStatus,
    /// Whether Apply would replace an existing file.
    pub will_replace: bool,
    /// Whether Apply would keep incoming content with a conflict-free name.
    pub will_keep_both: bool,
    /// Whether Apply would skip the incoming staged item.
    pub will_skip: bool,
    /// Whether Apply would route the row to per-item conflict handling.
    pub will_ask_per_item: bool,
    /// Whether the existing target is index-only and cannot be replaced.
    pub index_only: bool,
    /// User-visible risk or safety explanation for the selected strategy.
    pub risk_summary: String,
    /// Per-row blocked, pending, or failed reason.
    pub reason: Option<String>,
}

/// Read-only C2-17 preview report consumed before Apply is enabled.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ImportConflictBatchPreviewReport {
    /// Import session that owns the preview.
    pub import_session_id: String,
    /// Token that binds Apply to this preview request and inspected state.
    pub preview_token: String,
    /// Whether strategies applied to all current conflicts of the same type.
    pub apply_to_all_similar_conflicts: bool,
    /// Number of requested or in-scope conflict rows.
    pub requested_conflict_count: i64,
    /// Number of hash duplicate rows in scope.
    pub duplicate_conflict_count: i64,
    /// Number of same-name different-content rows in scope.
    pub same_name_conflict_count: i64,
    /// Number of rows included in the current Apply or Ask-per-item scope.
    pub included_count: i64,
    /// Number of rows intentionally left pending.
    pub pending_count: i64,
    /// Number of rows blocking Apply.
    pub blocked_count: i64,
    /// Number of rows that would replace existing files.
    pub replace_count: i64,
    /// Number of rows that would be skipped.
    pub skip_count: i64,
    /// Number of rows that would be imported with conflict-free names.
    pub keep_both_count: i64,
    /// Number of rows that would be routed to per-item handling.
    pub ask_per_item_count: i64,
    /// Whether Trash or recovery storage is available for replacement.
    pub trash_available: bool,
    /// Whether successful writes can create a C2-07 undo action.
    pub undo_available: bool,
    /// Whether Apply may be called with this preview token.
    pub can_apply: bool,
    /// User-displayable reason when Apply is disabled.
    pub apply_blocked_reason: Option<String>,
    /// Whether a Replace strategy still needs explicit second confirmation.
    pub replace_confirmation_required: bool,
    /// Summary text for the Replace second-confirmation sheet.
    pub replace_confirmation_summary: Option<String>,
    /// Detailed preview rows for S2-21.
    pub items: Vec<ImportConflictBatchPreviewItem>,
}

/// C2-17 apply request bound to a previous preview.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ImportConflictBatchApplyRequest {
    /// Import session that owns the staged conflict rows.
    pub import_session_id: String,
    /// Conflict ids selected by S2-21; empty is invalid.
    pub conflict_ids: Vec<String>,
    /// Strategy for hash duplicate rows.
    pub duplicate_strategy: ImportConflictBatchStrategy,
    /// Strategy for same-name different-content rows.
    pub same_name_strategy: ImportConflictBatchStrategy,
    /// Whether strategies apply to all current conflicts of the same type.
    pub apply_to_all_similar_conflicts: bool,
    /// Whether S2-21 completed the Replace second-confirmation sheet.
    pub replace_confirmed: bool,
}

/// One row in a C2-17 apply report.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ImportConflictBatchItemResult {
    /// Stable conflict id from the import session.
    pub conflict_id: String,
    /// Conflict type that was processed.
    pub conflict_type: ImportConflictBatchConflictType,
    /// Strategy actually applied to this row.
    pub applied_strategy: ImportConflictBatchStrategy,
    /// Stable execution status for S2-21 result summaries.
    pub status: ImportConflictBatchResultStatus,
    /// File id written or refreshed when Apply succeeded.
    pub file_id: Option<i64>,
    /// Final path for successful imports or replacements.
    pub final_path: Option<String>,
    /// Optional per-row failure or skip reason.
    pub error: Option<String>,
}

/// Execution report returned to S2-21 and C2-07 undo consumers.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ImportConflictBatchApplyReport {
    /// Import session processed by this apply call.
    pub import_session_id: String,
    /// Number of requested or in-scope conflict rows.
    pub requested_conflict_count: i64,
    /// Number of rows resolved by this apply call.
    pub resolved_count: i64,
    /// Number of duplicate rows skipped.
    pub skipped_count: i64,
    /// Number of incoming files kept with conflict-free names.
    pub kept_both_count: i64,
    /// Number of existing files replaced after confirmation.
    pub replaced_count: i64,
    /// Number of rows routed to per-item conflict handling.
    pub queued_for_per_item_count: i64,
    /// Number of rows intentionally left pending.
    pub pending_count: i64,
    /// Number of rows that failed.
    pub failed_count: i64,
    /// Detailed per-conflict execution results.
    pub item_results: Vec<ImportConflictBatchItemResult>,
    /// File ids that list/detail/tree consumers should refresh.
    pub affected_file_ids: Vec<i64>,
    /// Undo token for C2-07 toast/history when successful writes create one.
    pub undo_token: Option<String>,
    /// Change-log actions written by successful rows.
    pub change_log_actions: Vec<String>,
    /// Summary of failed rows for S2-21 recovery state.
    pub failure_summary: Option<String>,
}

/// Previews C2-17 import conflict batch decisions without mutating staging or files.
///
/// S2-21 uses this API to show conflict type groups, selected strategies, row
/// status, Replace risk, Trash/undo availability, pending rows, and whether
/// Apply can be enabled. This contract is side-effect free: it must not write
/// import session decisions, promote staged files, move files to Trash, replace
/// existing files, create undo actions, write change log rows, trigger iCloud
/// downloads, or call AI/network providers.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` for empty import sessions or
/// conflict selections, `CoreError::PermissionDenied { path }` for blocked
/// metadata or staging inspection, `CoreError::StagingRecoveryRequired { path }`
/// when unresolved staging residue must be repaired first, `CoreError::Io {
/// message }` for filesystem preview failures, and `CoreError::Db { message }`
/// for import-session metadata reads.
pub fn preview_import_conflict_batch(
    repo_path: String,
    request: ImportConflictBatchPreviewRequest,
) -> CoreResult<ImportConflictBatchPreviewReport> {
    let repo = prepare_import_conflict_batch_request(
        &repo_path,
        &request.import_session_id,
        &request.conflict_ids,
    )?;
    db::ensure_initialized(&repo).map_err(normalize_import_conflict_metadata_error)?;
    Err(CoreError::db(
        "import conflict batch implementation is pending",
    ))
}

/// Applies C2-17 import conflict batch decisions after explicit user confirmation.
///
/// `preview_token` must come from [`preview_import_conflict_batch`] for the
/// same import session, conflict scope, strategies, Trash availability, and
/// inspected staging state. Replace strategies require S2-21 to complete the
/// second-confirmation sheet before this API may mutate anything. Failed rows
/// must keep staged files and unresolved conflict state so the user can retry
/// or route them to per-item handling.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` for empty import sessions or
/// conflict selections, `CoreError::Conflict { path }` for missing/stale
/// preview tokens or missing Replace confirmation, `CoreError::PermissionDenied
/// { path }` for blocked staging, Trash, metadata, change-log, or undo writes,
/// `CoreError::StagingRecoveryRequired { path }` when recovery must run before
/// Apply, `CoreError::Io { message }` for filesystem or rollback failures, and
/// `CoreError::Db { message }` for import-session, file, change-log, or undo
/// writes.
pub fn apply_import_conflict_batch(
    repo_path: String,
    request: ImportConflictBatchApplyRequest,
    preview_token: String,
) -> CoreResult<ImportConflictBatchApplyReport> {
    if preview_token.trim().is_empty() {
        return Err(CoreError::conflict("missing import conflict batch preview"));
    }
    if has_replace_strategy(&request) && !request.replace_confirmed {
        return Err(CoreError::conflict("missing replace confirmation"));
    }
    let repo = prepare_import_conflict_batch_request(
        &repo_path,
        &request.import_session_id,
        &request.conflict_ids,
    )?;
    db::ensure_initialized(&repo).map_err(normalize_import_conflict_metadata_error)?;
    Err(CoreError::db(
        "import conflict batch implementation is pending",
    ))
}

fn prepare_import_conflict_batch_request(
    repo_path: &str,
    import_session_id: &str,
    conflict_ids: &[String],
) -> CoreResult<PathBuf> {
    let repo = validate_import_conflict_repo_path(repo_path)?;
    validate_import_session_id(import_session_id)?;
    normalize_import_conflict_ids(conflict_ids)?;
    Ok(repo)
}

fn validate_import_conflict_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::permission_denied("repository path is required"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::permission_denied("repository path is invalid"));
    }
    Ok(repo)
}

fn validate_import_session_id(import_session_id: &str) -> CoreResult<()> {
    if import_session_id.trim().is_empty() {
        return Err(CoreError::file_not_found("import-session:empty"));
    }
    Ok(())
}

fn normalize_import_conflict_ids(conflict_ids: &[String]) -> CoreResult<Vec<String>> {
    let mut normalized = Vec::new();
    for conflict_id in conflict_ids {
        let trimmed = conflict_id.trim();
        if trimmed.is_empty() {
            return Err(CoreError::file_not_found("conflict:empty"));
        }
        if !normalized.iter().any(|existing| existing == trimmed) {
            normalized.push(trimmed.to_owned());
        }
    }
    if normalized.is_empty() {
        return Err(CoreError::file_not_found("conflict:empty"));
    }
    Ok(normalized)
}

fn normalize_import_conflict_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => {
            CoreError::db("import conflict batch metadata is unavailable")
        }
        CoreError::PermissionDenied { .. } => {
            CoreError::permission_denied("import conflict batch metadata permission denied")
        }
        CoreError::Io { .. } => CoreError::io("import conflict batch metadata io unavailable"),
        other => other,
    }
}

fn has_replace_strategy(request: &ImportConflictBatchApplyRequest) -> bool {
    matches!(
        request.duplicate_strategy,
        ImportConflictBatchStrategy::Replace
    ) || matches!(
        request.same_name_strategy,
        ImportConflictBatchStrategy::Replace
    )
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    matches!(component, Component::Normal(value) if value == AREA_MATRIX_DIR)
}
