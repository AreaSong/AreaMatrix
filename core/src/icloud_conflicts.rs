//! iCloud conflicted copy listing, preview, and single-conflict resolution.

mod paths;
mod preview;
mod resolve;
mod types;

use std::path::Path;

use walkdir::WalkDir;

use crate::{
    db, CoreError, CoreResult, ICloudConflictPair, ICloudConflictPreviewReport,
    ICloudConflictResolution, ICloudConflictResolveReport,
};

use self::{
    paths::{
        bind_conflict, candidate_for_path, map_walkdir_error, reject_placeholder_path,
        should_descend, validate_initialized_repo_path, validate_repo_path, version_states,
    },
    preview::{ensure_resolution_enabled, preview_report, trash_available},
    resolve::{resolve_destructive, resolve_keep_both},
};

/// Lists iCloud conflicted copy pairs without mutating repository files.
///
/// # Errors
///
/// Returns `CoreError::ICloudPlaceholder` when a scanned candidate is still an
/// iCloud placeholder, `PermissionDenied` for blocked metadata reads, and `Io`
/// for filesystem traversal or timestamp conversion failures.
pub(crate) fn list_icloud_conflicts(repo_path: String) -> CoreResult<Vec<ICloudConflictPair>> {
    let repo = validate_repo_path(&repo_path)?;
    reject_placeholder_path(&repo)?;
    let mut conflicts = Vec::new();

    for entry in WalkDir::new(&repo)
        .follow_links(false)
        .same_file_system(true)
        .into_iter()
        .filter_entry(|entry| should_descend(&repo, entry))
    {
        let entry = entry.map_err(map_walkdir_error)?;
        if !entry.file_type().is_file() {
            continue;
        }
        if !paths::is_conflicted_copy(entry.path()) {
            continue;
        }
        conflicts.push(candidate_for_path(&repo, entry.path())?.into_pair());
    }

    apply_persisted_statuses(&repo, &mut conflicts)?;
    conflicts.sort_by(|left, right| {
        right
            .conflicted_modified_at
            .cmp(&left.conflicted_modified_at)
            .then_with(|| left.conflicted_copy_path.cmp(&right.conflicted_copy_path))
    });
    Ok(conflicts)
}

/// Previews one iCloud conflict without moving, deleting, or resolving files.
///
/// # Errors
///
/// Returns `CoreError::ICloudPlaceholder` for placeholder-shaped versions,
/// `CoreError::Conflict` for stale or ambiguous conflict ids,
/// `CoreError::PermissionDenied` for blocked metadata or Trash checks,
/// and `CoreError::Io` for filesystem metadata or hash failures.
pub(crate) fn preview_conflict_versions(
    repo_path: String,
    conflict_id: String,
) -> CoreResult<ICloudConflictPreviewReport> {
    let repo = validate_initialized_repo_path(&repo_path)?;
    let binding = bind_conflict(&repo, &conflict_id)?;
    let versions = version_states(&binding)?;
    Ok(preview_report(
        binding.conflict_id,
        versions,
        trash_available()?,
    ))
}

/// Resolves one iCloud conflict after explicit UI confirmation.
///
/// # Errors
///
/// Returns `CoreError::Conflict` if the conflict id no longer binds to the same
/// versions, `CoreError::ICloudPlaceholder` for unavailable versions,
/// `CoreError::PermissionDenied` for Trash or metadata write failures,
/// and `CoreError::Db` for conflict-state or change-log writes. Any failure
/// before commit leaves the conflict unresolved and restores the moved version.
pub(crate) fn resolve_icloud_conflict(
    repo_path: String,
    conflict_id: String,
    resolution: ICloudConflictResolution,
) -> CoreResult<ICloudConflictResolveReport> {
    let repo = validate_initialized_repo_path(&repo_path)?;
    let binding = bind_conflict(&repo, &conflict_id)?;
    let versions = version_states(&binding)?;
    let preview = preview_report(binding.conflict_id.clone(), versions, trash_available()?);
    ensure_resolution_enabled(&preview, &resolution)?;

    match resolution {
        ICloudConflictResolution::KeepBoth => resolve_keep_both(&repo, &binding, resolution),
        ICloudConflictResolution::KeepOriginal => resolve_destructive(
            &repo,
            &binding,
            resolution,
            &binding.conflicted_path,
            &binding.conflicted_relative_path,
        ),
        ICloudConflictResolution::KeepConflictedCopy => {
            let path = binding
                .original_path
                .as_ref()
                .ok_or_else(|| CoreError::conflict("original version not found"))?;
            let relative_path = binding
                .original_relative_path
                .as_deref()
                .ok_or_else(|| CoreError::conflict("original version not found"))?;
            resolve_destructive(&repo, &binding, resolution, path, relative_path)
        }
    }
}

fn apply_persisted_statuses(repo: &Path, conflicts: &mut [ICloudConflictPair]) -> CoreResult<()> {
    let statuses = match db::list_icloud_conflict_statuses(repo) {
        Ok(statuses) => statuses,
        Err(CoreError::RepoNotInitialized { .. }) => return Ok(()),
        Err(error) => return Err(error),
    };
    if statuses.is_empty() {
        return Ok(());
    }

    for conflict in conflicts {
        if let Some(status) = statuses.get(&conflict.conflict_id) {
            conflict.status = status.clone();
        }
    }
    Ok(())
}
