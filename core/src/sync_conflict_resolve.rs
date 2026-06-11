//! C4-16 sync conflict resolution contract types and entry points.

mod apply;
mod plan;

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::{
    db, repo_path, CoreError, CoreResult, SyncConflict, SyncConflictFileRole, SyncConflictStatus,
};

const CHANGE_LOG_DB_ACTION: &str = "external_modified";
const RESOLUTION_KIND_PREFIX: &str = "conflict_resolved";
const SYNC_CONFLICT_RESOLVED_KIND: &str = "sync_conflict_resolved";

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

#[derive(Clone)]
struct IncomingReplacement {
    existing_path: String,
    incoming_path: String,
    canonical_path: String,
    affected_file_id: i64,
    existing_hash_sha256: Option<String>,
    incoming_size_bytes: i64,
    incoming_hash_sha256: String,
    move_incoming_to_canonical: bool,
    trash_existing: bool,
}

#[derive(Clone)]
struct ResolutionPlan {
    conflict_id: String,
    resolution: SyncConflictResolutionStrategy,
    version_impacts: Vec<SyncConflictVersionImpact>,
    kept_paths: Vec<String>,
    retained_paths: Vec<String>,
    planned_trash_paths: Vec<String>,
    affected_file_ids: Vec<i64>,
    canonical_path: Option<String>,
    change_log_action: String,
    destructive: bool,
    requires_replace_confirmation: bool,
    trash_required: bool,
    trash_available: bool,
    can_apply: bool,
    blocked_reason: Option<String>,
    preview_token: Option<String>,
    replace_plan: Option<SyncConflictReplacePlan>,
    replacement: Option<IncomingReplacement>,
}

impl ResolutionPlan {
    fn preview_report(&self) -> SyncConflictResolutionPreviewReport {
        SyncConflictResolutionPreviewReport {
            conflict_id: self.conflict_id.clone(),
            resolution: self.resolution.clone(),
            default_resolution: SyncConflictResolutionStrategy::KeepBoth,
            status_after: SyncConflictStatus::Resolved,
            version_impacts: self.version_impacts.clone(),
            kept_paths: self.kept_paths.clone(),
            retained_paths: self.retained_paths.clone(),
            planned_trash_paths: self.planned_trash_paths.clone(),
            affected_file_ids: self.affected_file_ids.clone(),
            canonical_path: self.canonical_path.clone(),
            change_log_action: self.change_log_action.clone(),
            destructive: self.destructive,
            requires_replace_confirmation: self.requires_replace_confirmation,
            trash_required: self.trash_required,
            trash_available: self.trash_available,
            can_apply: self.can_apply,
            blocked_reason: self.blocked_reason.clone(),
            preview_token: self.preview_token.clone(),
            replace_plan: self.replace_plan.clone(),
        }
    }

    fn resolve_report(
        &self,
        trashed_paths: Vec<String>,
        undo_token: Option<String>,
        resolved_at: i64,
    ) -> SyncConflictResolveReport {
        SyncConflictResolveReport {
            conflict_id: self.conflict_id.clone(),
            resolution: self.resolution.clone(),
            status: SyncConflictStatus::Resolved,
            kept_paths: self.kept_paths.clone(),
            retained_paths: self.retained_paths.clone(),
            trashed_paths,
            affected_file_ids: self.affected_file_ids.clone(),
            change_log_action: self.change_log_action.clone(),
            undo_token,
            resolved_at: Some(resolved_at),
        }
    }
}

/// Previews a C4-16 resolution plan without mutating files or metadata.
///
/// # Errors
///
/// Returns `CoreError::Conflict` for stale or missing conflict state,
/// `CoreError::PermissionDenied` for blocked Trash or metadata preflight,
/// `CoreError::Io` for filesystem preflight failures, and `CoreError::Db` for
/// persisted state reads that cannot be decoded.
pub(crate) fn preview_sync_conflict_resolution(
    repo_path: String,
    conflict_id: String,
    resolution: SyncConflictResolutionStrategy,
) -> CoreResult<SyncConflictResolutionPreviewReport> {
    validate_contract_inputs(&repo_path, &conflict_id)?;
    let repo = initialized_repo_path(&repo_path)?;
    db::preflight_sync_conflict_resolution(&repo).map_err(normalize_state_error)?;
    let state = load_conflict_state(&repo)?;
    let conflict = state
        .get(bind_conflict_index(&state, &conflict_id)?)
        .ok_or_else(|| CoreError::conflict("sync conflict state is stale"))?;
    let trash_available = plan::trash_available()?;
    Ok(plan::build_resolution_plan(conflict, resolution, trash_available)?.preview_report())
}

/// Resolves one C4-16 sync conflict after preview and required confirmation.
///
/// # Errors
///
/// Returns `CoreError::Conflict` when the conflict state or preview token is
/// stale, `CoreError::PermissionDenied` when confirmation or Trash preflight is
/// missing, `CoreError::Io` when filesystem moves or rollback fail, and
/// `CoreError::Db` when the state or change-log transaction fails.
pub(crate) fn resolve_sync_conflict(
    repo_path: String,
    conflict_id: String,
    resolution: SyncConflictResolutionRequest,
) -> CoreResult<SyncConflictResolveReport> {
    validate_contract_inputs(&repo_path, &conflict_id)?;
    validate_resolution_request(&resolution)?;
    let repo = initialized_repo_path(&repo_path)?;
    db::preflight_sync_conflict_resolution(&repo).map_err(normalize_state_error)?;
    let mut state = load_conflict_state(&repo)?;
    let conflict_index = bind_conflict_index(&state, &conflict_id)?;
    let conflict = state[conflict_index].clone();
    let trash_available = plan::trash_available()?;
    let plan =
        plan::build_resolution_plan(&conflict, resolution.strategy.clone(), trash_available)?;
    ensure_request_matches_plan(&resolution, &plan)?;

    state[conflict_index].status = SyncConflictStatus::Resolved;
    let serialized_state = serialize_conflict_state(&state)?;
    let resolved_at = chrono::Utc::now().timestamp();
    apply::apply_resolution(&repo, &plan, &resolution, &serialized_state, resolved_at)
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

fn initialized_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    repo_path::validate_initialized_repo_path(repo_path.to_owned())
        .map_err(normalize_state_error)?;
    Ok(PathBuf::from(repo_path))
}

fn load_conflict_state(repo: &Path) -> CoreResult<Vec<SyncConflict>> {
    let Some((payload, _updated_at)) =
        db::load_sync_conflict_state(repo).map_err(normalize_state_error)?
    else {
        return Err(CoreError::conflict("sync conflict state is unavailable"));
    };
    serde_json::from_str(&payload)
        .map_err(|_| CoreError::db("sync conflict state metadata is invalid"))
}

fn bind_conflict_index(conflicts: &[SyncConflict], conflict_id: &str) -> CoreResult<usize> {
    let Some(index) = conflicts
        .iter()
        .position(|conflict| conflict.conflict_id == conflict_id)
    else {
        return Err(CoreError::conflict(conflict_id.to_owned()));
    };
    if conflicts[index].status != SyncConflictStatus::NeedsReview {
        return Err(CoreError::conflict("sync conflict is already resolved"));
    }
    Ok(index)
}

fn ensure_request_matches_plan(
    request: &SyncConflictResolutionRequest,
    plan: &ResolutionPlan,
) -> CoreResult<()> {
    let Some(preview_token) = &plan.preview_token else {
        return Err(CoreError::conflict(
            plan.blocked_reason
                .clone()
                .unwrap_or_else(|| "sync conflict resolution is blocked".to_owned()),
        ));
    };
    if request.preview_token != *preview_token {
        return Err(CoreError::conflict("sync conflict preview token is stale"));
    }
    if matches!(
        request.strategy,
        SyncConflictResolutionStrategy::UseIncoming
    ) {
        ensure_use_incoming_enabled(request, plan)?;
    } else if !plan.can_apply {
        return Err(CoreError::conflict(
            plan.blocked_reason
                .clone()
                .unwrap_or_else(|| "sync conflict resolution is blocked".to_owned()),
        ));
    }
    Ok(())
}

fn ensure_use_incoming_enabled(
    request: &SyncConflictResolutionRequest,
    plan: &ResolutionPlan,
) -> CoreResult<()> {
    if !request.replace_confirmed {
        return Err(CoreError::permission_denied(
            "replace confirmation is required",
        ));
    }
    if plan.trash_required && !plan.trash_available {
        return Err(CoreError::permission_denied("Trash unavailable"));
    }
    if plan.replacement.is_none() {
        return Err(CoreError::conflict("replace plan is unavailable"));
    }
    Ok(())
}

fn serialize_conflict_state(conflicts: &[SyncConflict]) -> CoreResult<String> {
    serde_json::to_string(conflicts)
        .map_err(|_| CoreError::db("sync conflict state metadata is invalid"))
}

fn resolution_detail_json(
    plan: &ResolutionPlan,
    request: &SyncConflictResolutionRequest,
    trashed_paths: &[String],
    resolved_at: i64,
) -> CoreResult<String> {
    serde_json::to_string(&json!({
        "kind": SYNC_CONFLICT_RESOLVED_KIND,
        "logical_action": plan.change_log_action,
        "db_action": CHANGE_LOG_DB_ACTION,
        "conflict_id": plan.conflict_id,
        "strategy": strategy_key(&plan.resolution),
        "status": "resolved",
        "kept_paths": plan.kept_paths,
        "retained_paths": plan.retained_paths,
        "trashed_paths": trashed_paths,
        "affected_file_ids": plan.affected_file_ids,
        "canonical_path": plan.canonical_path,
        "replace_confirmation_id": request.replace_confirmation_id,
        "resolved_at": resolved_at,
        "by": "user",
    }))
    .map_err(|error| CoreError::internal(error.to_string()))
}

fn logical_change_log_action(resolution: &SyncConflictResolutionStrategy) -> String {
    format!("{}_{}", RESOLUTION_KIND_PREFIX, strategy_key(resolution))
}

fn strategy_key(resolution: &SyncConflictResolutionStrategy) -> &'static str {
    match resolution {
        SyncConflictResolutionStrategy::KeepBoth => "keep_both",
        SyncConflictResolutionStrategy::UseExisting => "use_existing",
        SyncConflictResolutionStrategy::UseIncoming => "use_incoming",
    }
}

fn normalize_state_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Config { .. } | CoreError::RepoNotInitialized { .. } => {
            CoreError::db("sync conflict state requires initialized metadata")
        }
        CoreError::InvalidPath { .. } => CoreError::io("sync conflict repository path is invalid"),
        other => other,
    }
}
