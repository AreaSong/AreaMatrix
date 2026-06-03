//! C4-16 sync conflict resolution contract types and entry points.

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult, SyncConflictFileRole, SyncConflictStatus};

/// User-selected C4-16 sync conflict resolution strategy.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SyncConflictResolutionStrategy {
    /// Keep every version visible as normal repository files.
    KeepBoth,
    /// Keep the existing canonical version and retain incoming versions visibly.
    UseExisting,
    /// Make the incoming version canonical after replace confirmation.
    UseIncoming,
}

/// Per-version impact shown in S4-X-01 before applying a resolution.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SyncConflictVersionImpact {
    /// Repository-relative path for the affected version.
    pub path: String,
    /// AreaMatrix file id when the version is already tracked.
    pub file_id: Option<i64>,
    /// Role of the version in the original conflict.
    pub role: SyncConflictFileRole,
    /// Whether the version remains available after the planned resolution.
    pub will_keep: bool,
    /// Whether this version becomes or remains the canonical path.
    pub will_be_canonical: bool,
    /// Whether the version remains in a normal user-visible location.
    pub will_remain_user_visible: bool,
    /// Whether the version is planned to move to Trash or Recycle Bin.
    pub will_move_to_trash: bool,
    /// Planned retained, backup, Trash, or Recycle Bin target.
    pub recovery_target: Option<String>,
    /// Stable reason for disabled or risky impact rows.
    pub reason: Option<String>,
}

/// Replace plan required before S4-X-09 can confirm a destructive resolution.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SyncConflictReplacePlan {
    /// Existing canonical path that would stop being canonical.
    pub old_path: String,
    /// Incoming path that would become canonical.
    pub new_path: String,
    /// Existing version hash when available.
    pub old_hash_sha256: Option<String>,
    /// Incoming version hash when available.
    pub new_hash_sha256: Option<String>,
    /// File record affected by the canonical replacement.
    pub affected_file_id: Option<i64>,
    /// Trash, Recycle Bin, or Core safety backup target for the old version.
    pub backup_target: Option<String>,
    /// Display-safe database update summary.
    pub database_update: String,
    /// Planned change-log action name.
    pub change_log_action: String,
    /// Recovery note shown before confirmation.
    pub recovery_note: String,
}

/// Read-only preview report for one planned sync conflict resolution.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SyncConflictResolutionPreviewReport {
    /// Stable conflict id being previewed.
    pub conflict_id: String,
    /// Strategy selected for this preview.
    pub resolution: SyncConflictResolutionStrategy,
    /// Default safe strategy for the page.
    pub default_resolution: SyncConflictResolutionStrategy,
    /// Lifecycle state expected after a successful apply.
    pub status_after: SyncConflictStatus,
    /// Per-version file impact rows.
    pub version_impacts: Vec<SyncConflictVersionImpact>,
    /// Paths that remain available after the planned resolution.
    pub kept_paths: Vec<String>,
    /// Non-canonical paths retained in user-visible locations.
    pub retained_paths: Vec<String>,
    /// Paths planned to move to Trash or Recycle Bin.
    pub planned_trash_paths: Vec<String>,
    /// File records affected by the planned resolution.
    pub affected_file_ids: Vec<i64>,
    /// Canonical path after the planned resolution.
    pub canonical_path: Option<String>,
    /// Planned change-log action name.
    pub change_log_action: String,
    /// Whether the selected strategy is destructive.
    pub destructive: bool,
    /// Whether S4-X-09 replace confirmation is required before apply.
    pub requires_replace_confirmation: bool,
    /// Whether Trash or Recycle Bin support is required.
    pub trash_required: bool,
    /// Whether the required Trash or Recycle Bin support is currently available.
    pub trash_available: bool,
    /// Whether the UI may enable `Apply resolution`.
    pub can_apply: bool,
    /// Stable disabled reason when the plan cannot be applied.
    pub blocked_reason: Option<String>,
    /// Token binding the later apply request to this preview.
    pub preview_token: Option<String>,
    /// Replace plan for S4-X-09 when the strategy can replace a canonical version.
    pub replace_plan: Option<SyncConflictReplacePlan>,
}

/// Apply request for resolving one sync conflict after preview.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SyncConflictResolutionRequest {
    /// Strategy to apply.
    pub strategy: SyncConflictResolutionStrategy,
    /// Preview token returned by `preview_sync_conflict_resolution`.
    pub preview_token: String,
    /// Whether S4-X-09 replace confirmation has completed.
    pub replace_confirmed: bool,
    /// Optional confirmation record from the platform dialog.
    pub replace_confirmation_id: Option<String>,
}

/// Result report returned after resolving one sync conflict.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SyncConflictResolveReport {
    /// Resolved conflict id.
    pub conflict_id: String,
    /// Applied strategy.
    pub resolution: SyncConflictResolutionStrategy,
    /// Final conflict lifecycle state.
    pub status: SyncConflictStatus,
    /// Paths that remain available after resolution.
    pub kept_paths: Vec<String>,
    /// Non-canonical paths retained in user-visible locations.
    pub retained_paths: Vec<String>,
    /// Paths moved to Trash or Recycle Bin.
    pub trashed_paths: Vec<String>,
    /// File records changed by the resolution.
    pub affected_file_ids: Vec<i64>,
    /// Written change-log action name.
    pub change_log_action: String,
    /// Undo token when Trash or Recycle Bin work can be reversed.
    pub undo_token: Option<String>,
    /// Unix timestamp when the conflict was resolved.
    pub resolved_at: Option<i64>,
}

/// Previews a C4-16 resolution plan without mutating files or metadata.
///
/// # Errors
///
/// Returns a documented C4-16 error until the implementation task binds the
/// contract to persisted conflict state and file-safety preflight checks.
pub(crate) fn preview_sync_conflict_resolution(
    repo_path: String,
    conflict_id: String,
    _resolution: SyncConflictResolutionStrategy,
) -> CoreResult<SyncConflictResolutionPreviewReport> {
    validate_contract_inputs(&repo_path, &conflict_id)?;
    Err(CoreError::conflict(conflict_id))
}

/// Resolves one C4-16 sync conflict after preview and required confirmation.
///
/// # Errors
///
/// Returns a documented C4-16 error until the implementation task binds the
/// contract to transactional conflict-state, change-log, and Trash handling.
pub(crate) fn resolve_sync_conflict(
    repo_path: String,
    conflict_id: String,
    resolution: SyncConflictResolutionRequest,
) -> CoreResult<SyncConflictResolveReport> {
    validate_contract_inputs(&repo_path, &conflict_id)?;
    validate_resolution_request(&resolution)?;
    Err(CoreError::conflict(conflict_id))
}

fn validate_contract_inputs(repo_path: &str, conflict_id: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::io("repository path is required"));
    }
    if conflict_id.trim().is_empty() {
        return Err(CoreError::conflict("sync conflict id is required"));
    }
    Ok(())
}

fn validate_resolution_request(request: &SyncConflictResolutionRequest) -> CoreResult<()> {
    if request.preview_token.trim().is_empty() {
        return Err(CoreError::conflict(
            "sync conflict preview token is required",
        ));
    }
    if matches!(
        request.strategy,
        SyncConflictResolutionStrategy::UseIncoming
    ) && !request.replace_confirmed
    {
        return Err(CoreError::permission_denied(
            "replace confirmation is required",
        ));
    }
    Ok(())
}
