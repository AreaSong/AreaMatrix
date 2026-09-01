//! Public FFI conflicts entry points.

use crate::{
    cloud_permission_state, icloud_conflicts, import_conflict_batch, sync_conflict_detect,
    sync_conflict_resolve, CloudStorageState, CoreResult, ICloudConflictPair,
    ICloudConflictPreviewReport, ICloudConflictResolution, ICloudConflictResolveReport,
    ImportConflictBatchApplyReport, ImportConflictBatchApplyRequest,
    ImportConflictBatchPreviewReport, ImportConflictBatchPreviewRequest, SyncConflict,
    SyncConflictResolutionPreviewReport, SyncConflictResolutionRequest,
    SyncConflictResolutionStrategy, SyncConflictResolveReport,
};

/// Detects sync conflicts without resolving any version.
///
/// `sync conflict entry surface sync-conflict-entry` consumes this non-resolving list for conflict
/// count, latest detection state, row badges, and Review routing.
/// `sync conflict review surface sync-conflict` consumes the same rows as its conflict summary and
/// affected-version metadata before sync conflict resolution builds impact plans. Core
/// may inspect persisted external events and safe file metadata, and it may
/// write or refresh conflict-state metadata for detected conflicts. This entry
/// point must not choose a winning version, mark conflicts resolved, advance
/// sync cursors, trigger rescan, download cloud placeholders, or
/// move/delete/rename/overwrite user files.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` for unavailable, unreadable, or
/// unwritable conflict-state metadata, `CoreError::Io { message }` for safe
/// metadata inspection failures, and `CoreError::Conflict { path }` when
/// snapshots or event state cannot be bound to a stable conflict without user
/// review.
pub fn detect_sync_conflicts(repo_path: String) -> CoreResult<Vec<SyncConflict>> {
    sync_conflict_detect::detect_sync_conflicts(repo_path)
}

/// Previews a sync conflict resolution plan without mutating files.
///
/// `sync conflict review surface sync-conflict` consumes this contract after the user chooses
/// `Keep both`, `Use existing version`, or `Use incoming version`. The preview
/// exposes per-version file impact, affected DB record ids, canonical and
/// retained paths, planned change-log action, and whether `replace confirmation surface
/// replace-confirm` is required. `Keep both` remains the default safe strategy.
/// This entry point must not mark a conflict resolved, write change log rows,
/// move files, rename files, overwrite files, Trash versions, or bypass
/// replace confirmation.
///
/// # Errors
///
/// Returns `CoreError::Conflict { path }` when the conflict id is missing,
/// stale, or cannot be bound to a stable conflict state,
/// `CoreError::PermissionDenied { path }` when required Trash/Recycle Bin,
/// metadata, or permission preflight is blocked, `CoreError::Io { message }`
/// for safe filesystem inspection failures, and `CoreError::Db { message }`
/// for conflict-state or change-log preflight reads.
pub fn preview_sync_conflict_resolution(
    repo_path: String,
    conflict_id: String,
    resolution: SyncConflictResolutionStrategy,
) -> CoreResult<SyncConflictResolutionPreviewReport> {
    sync_conflict_resolve::preview_sync_conflict_resolution(repo_path, conflict_id, resolution)
}

/// Resolves one sync conflict after preview and required confirmation.
///
/// `sync conflict review surface sync-conflict` calls this only after a fresh preview. Requests that
/// use `Use incoming version` must first complete `replace confirmation surface replace-confirm`;
/// Core receives that result as `replace_confirmed` and the preview token.
/// Successful resolution must leave all non-discarded versions visible or move
/// discarded versions only to Trash/Recycle Bin or a documented Core safety
/// backup, then update conflict state and write change log. Failure must leave
/// the conflict unresolved and must not silently delete or hide any version.
///
/// # Errors
///
/// Returns `CoreError::Conflict { path }` when the preview token, conflict id,
/// version set, or conflict state is stale, `CoreError::PermissionDenied {
/// path }` when replace confirmation, Trash/Recycle Bin, metadata, or
/// permissions block the selected strategy, `CoreError::Io { message }` for
/// filesystem or rollback failures, and `CoreError::Db { message }` for
/// conflict-state or change-log write failures.
pub fn resolve_sync_conflict(
    repo_path: String,
    conflict_id: String,
    resolution: SyncConflictResolutionRequest,
) -> CoreResult<SyncConflictResolveReport> {
    sync_conflict_resolve::resolve_sync_conflict(repo_path, conflict_id, resolution)
}

/// Lists iCloud conflicted copy pairs without resolving them.
///
/// iCloud conflict listing owns the read-only contract for iCloud conflict list. The caller supplies an
/// initialized repository root and receives one row per detected conflicted
/// copy pair. The output preserves the original path when Core can identify
/// it, the conflicted copy path, both modification timestamps when available,
/// and a status value. Ambiguous pairings must be returned as
/// `ICloudConflictStatus::NeedsReview` instead of being silently merged.
///
/// This API must not delete, move, rename, overwrite, merge, or download any
/// file. Single-item resolution remains a later explicit action and is not
/// hidden behind this list query.
///
/// # Errors
///
/// Returns `CoreError::ICloudPlaceholder { path }` for unavailable iCloud
/// metadata, `CoreError::PermissionDenied { path }` for blocked inspection,
/// `CoreError::Io { message }` for filesystem scan failures, and
/// `CoreError::Db { message }` for optional conflict-state reads.
pub fn list_icloud_conflicts(repo_path: String) -> CoreResult<Vec<ICloudConflictPair>> {
    icloud_conflicts::list_icloud_conflicts(repo_path)
}

/// Previews iCloud conflict versions without resolving the conflict.
///
/// iCloud conflict review surface uses this contract after selecting one conflict id from
/// [`list_icloud_conflicts`]. The preview returns version metadata, optional
/// Core-computed preview summaries, the safe default resolution, and per-choice
/// enablement for Keep both, Keep original, and Keep conflicted copy.
/// Destructive choices must be disabled when metadata is incomplete, Trash is
/// unavailable, the repository is read-only, or a version is still an iCloud
/// placeholder.
///
/// This API is a contract entry point for the later implementation task. It
/// must remain read-only: it must not mark conflicts resolved, move files to
/// Trash, write change log entries, create undo actions, trigger iCloud
/// downloads, or touch `apps/**`.
///
/// # Errors
///
/// Returns `CoreError::ICloudPlaceholder { path }` when required metadata or a
/// conflict version is still an iCloud placeholder, `CoreError::PermissionDenied
/// { path }` when version metadata or conflict state cannot be inspected,
/// `CoreError::Conflict { path }` when the conflict id is stale or cannot be
/// bound safely, `CoreError::Io { message }` for filesystem preview failures,
/// and `CoreError::Db { message }` for conflict-state metadata reads.
pub fn preview_conflict_versions(
    repo_path: String,
    conflict_id: String,
) -> CoreResult<ICloudConflictPreviewReport> {
    icloud_conflicts::preview_conflict_versions(repo_path, conflict_id)
}

/// Resolves one iCloud conflict after explicit user confirmation.
///
/// `preview_token` must be the non-empty opaque token returned by the immediately preceding
/// `preview_conflict_versions` call for the same repository and conflict. Core binds the token to
/// both version identities and rejects stale, cross-repository, replayed, or empty tokens before
/// any filesystem or database mutation. `resolution` is limited to the previewed iCloud conflict
/// resolution choices. `KeepBoth` must keep
/// every version and only mark the conflict resolved or acknowledged. `KeepOriginal`
/// and `KeepConflictedCopy` may move only the unkept paired version to system
/// Trash after the UI completed destructive confirmation. A successful write
/// records conflict state and change log metadata, and returns an undo token
/// when Trash-based undo is available.
///
/// This contract does not replace import-conflict handling, batch delete,
/// generic sync conflicts, QuickLook rendering, platform download coordination,
/// or any page ability outside iCloud conflict review surface / iCloud conflict list consumption.
///
/// # Errors
///
/// Returns `CoreError::ICloudPlaceholder { path }` when a required version is
/// still unavailable, `CoreError::PermissionDenied { path }` for Trash,
/// metadata, or conflict-state write failures, `CoreError::Conflict { path }`
/// when the conflict changed since preview or the requested resolution is no
/// longer safe, `CoreError::Io { message }` for Trash or rollback failures, and
/// `CoreError::Db { message }` for conflict state, change log, or undo writes.
/// On any failure the conflict must remain unresolved and no version may be
/// silently deleted.
pub fn resolve_icloud_conflict(
    repo_path: String,
    conflict_id: String,
    resolution: ICloudConflictResolution,
    preview_token: String,
) -> CoreResult<ICloudConflictResolveReport> {
    icloud_conflicts::resolve_icloud_conflict(repo_path, conflict_id, resolution, preview_token)
}

/// Detects cloud storage provider state and OneDrive risk state.
///
/// `iCloud permission surface`, `OneDrive notice surface`, and the cloud
/// branch of `iOS repository connection` use this read-only contract to render
/// provider-specific recovery or notice state from structured fields. Core
/// inspects only the authorized repository path and basic filesystem metadata;
/// security-scoped bookmarks, iCloud availability, OneDrive client state,
/// settings links, SDK calls, provider downloads, acknowledgement UI, and
/// reconnect UI remain in the platform layer. `OneDrive notice surface` can use
/// `recommended_action`, `requires_notice_acknowledgement`, and
/// `notice_acknowledged` to render the OneDrive confirmation state without
/// parsing display text.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` when the input is empty or points
/// inside AreaMatrix metadata, `CoreError::ICloudPlaceholder { path }` when the
/// repository path or required metadata is still a visible cloud placeholder,
/// `CoreError::PermissionDenied { path }` when metadata or directory listing is
/// blocked, and `CoreError::Io { message }` for other read-only filesystem
/// inspection failures.
pub fn detect_cloud_storage_state(repo_path: String) -> CoreResult<CloudStorageState> {
    cloud_permission_state::detect_cloud_storage_state(repo_path)
}

/// Persists the OneDrive risk notice acknowledgement.
///
/// `OneDrive notice surface` calls this only after the user has explicitly
/// confirmed the OneDrive warning. The API writes only Core-visible repository
/// metadata (`repo_config`) for an already initialized repository, then returns
/// the refreshed [`CloudStorageState`]. It does not create a repository, move,
/// rename, delete, overwrite, reindex, trigger downloads, call the OneDrive
/// SDK, or change cloud sync settings.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` when the input is empty or points
/// inside AreaMatrix metadata, `CoreError::ICloudPlaceholder { path }` when the
/// repository path or required metadata is still a visible cloud placeholder,
/// `CoreError::PermissionDenied { path }` when metadata, directory listing, or
/// acknowledgement persistence is blocked, and `CoreError::Io { message }` for
/// missing initialized metadata or other acknowledgement persistence failures.
pub fn acknowledge_onedrive_risk_notice(repo_path: String) -> CoreResult<CloudStorageState> {
    cloud_permission_state::acknowledge_onedrive_risk_notice(repo_path)
}

/// Previews import conflict batch decisions without mutating staging or files.
///
/// import conflict review surface uses this contract after a batch import session has accumulated hash
/// duplicate or same-name different-content conflicts. The preview returns row
/// status, selected strategy, Replace risk, Trash/undo availability, pending
/// rows, and the `preview_token` required by [`apply_import_conflict_batch`].
/// Default-safe strategies are `Skip` for duplicate hashes and `KeepBoth` for
/// same-name different-content conflicts.
///
/// This contract is read-only. It must not write import session decisions,
/// promote staged files, move files to Trash, replace existing files, write
/// change log rows, create undo actions, trigger iCloud downloads, call AI or
/// network providers, or touch `apps/**`.
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
    import_conflict_batch::preview_import_conflict_batch(repo_path, request)
}

/// Applies import conflict batch decisions after explicit confirmation.
///
/// `preview_token` must come from [`preview_import_conflict_batch`] for the same
/// import session, conflict scope, strategies, Trash availability, and inspected
/// staging state. Replace rows require import conflict review surface's second-confirmation sheet before
/// any write is allowed. Failed rows must keep staged files and unresolved
/// conflict state so the user can retry or route them to per-item handling.
///
/// This contract does not implement iCloud conflict resolution, generic sync
/// conflicts, classifier rule changes, batch delete/rename/category actions,
/// or any page ability outside import conflict review surface / undo action log consumption.
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
    import_conflict_batch::apply_import_conflict_batch(repo_path, request, preview_token)
}
