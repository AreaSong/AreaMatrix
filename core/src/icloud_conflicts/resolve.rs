use std::path::{Path, PathBuf};

use crate::{
    db, storage, CoreResult, ICloudConflictResolution, ICloudConflictResolveReport,
    ICloudConflictStatus, ICloudConflictVersionRole,
};

use super::{
    paths::{map_io_error, version_states},
    token::{ensure_token_matches, preview_token},
    types::ConflictBinding,
};

const CHANGE_LOG_ACTION: &str = "external_modified";

pub(super) fn resolve_keep_both(
    repo: &Path,
    binding: &ConflictBinding,
    resolution: ICloudConflictResolution,
    preview_token: &str,
) -> CoreResult<ICloudConflictResolveReport> {
    // KeepBoth has no file move, but it still changes durable conflict state;
    // re-sample immediately before the DB write so a stale preview cannot mark
    // a different pair as resolved.
    let current_versions = version_states(binding)?;
    let current_token = preview_token_for_binding(binding, &current_versions)?;
    ensure_token_matches(preview_token, &current_token)?;
    let kept_paths = kept_paths(binding, None);
    db::record_icloud_conflict_resolution(
        repo,
        &binding.conflict_id,
        resolution_db(&resolution),
        false,
    )?;
    Ok(ICloudConflictResolveReport {
        conflict_id: binding.conflict_id.clone(),
        resolution,
        status: ICloudConflictStatus::Resolved,
        kept_paths,
        trashed_paths: Vec::new(),
        undo_token: None,
        change_log_action: CHANGE_LOG_ACTION.to_owned(),
    })
}

pub(super) fn resolve_destructive(
    repo: &Path,
    binding: &ConflictBinding,
    resolution: ICloudConflictResolution,
    discard_path: &Path,
    discard_relative_path: &str,
    discard_role: ICloudConflictVersionRole,
    preview_token: &str,
) -> CoreResult<ICloudConflictResolveReport> {
    // Re-sample immediately before any Trash operation. The first sample is
    // the UI preview; this one closes the stale-preview gap for same-path
    // replacement, mtime-only changes, and ancestor swaps.
    let current_versions = version_states(binding)?;
    let current_token = preview_token_for_binding(binding, &current_versions)?;
    ensure_token_matches(preview_token, &current_token)?;
    let discard_version = current_versions
        .iter()
        .find(|version| {
            version.role == discard_role
                && version.relative_path == discard_relative_path
                && version.absolute_path == discard_path
        })
        .ok_or_else(|| crate::CoreError::conflict(discard_relative_path.to_owned()))?;

    let mut guard = TrashMoveGuard::move_to_trash(discard_path, discard_version)?;
    let undo_token = db::record_icloud_conflict_resolution(
        repo,
        &binding.conflict_id,
        resolution_db(&resolution),
        true,
    );
    match undo_token {
        Ok(undo_token) => {
            let trashed_paths = vec![discard_relative_path.to_owned()];
            let kept_paths = kept_paths(binding, Some(discard_relative_path));
            guard.disarm();
            Ok(ICloudConflictResolveReport {
                conflict_id: binding.conflict_id.clone(),
                resolution,
                status: ICloudConflictStatus::Resolved,
                kept_paths,
                trashed_paths,
                undo_token,
                change_log_action: CHANGE_LOG_ACTION.to_owned(),
            })
        }
        Err(error) => {
            guard.rollback()?;
            Err(error)
        }
    }
}

fn preview_token_for_binding(
    binding: &ConflictBinding,
    versions: &[super::types::VersionState],
) -> CoreResult<String> {
    preview_token(binding, versions)
}

struct TrashMoveGuard {
    original_path: PathBuf,
    trash_path: Option<PathBuf>,
    armed: bool,
}

fn kept_paths(binding: &ConflictBinding, discarded: Option<&str>) -> Vec<String> {
    let mut paths = Vec::new();
    if let Some(path) = &binding.original_relative_path {
        if Some(path.as_str()) != discarded {
            paths.push(path.clone());
        }
    }
    if Some(binding.conflicted_relative_path.as_str()) != discarded {
        paths.push(binding.conflicted_relative_path.clone());
    }
    paths
}

fn resolution_db(resolution: &ICloudConflictResolution) -> &'static str {
    match resolution {
        ICloudConflictResolution::KeepBoth => "keep_both",
        ICloudConflictResolution::KeepOriginal => "keep_original",
        ICloudConflictResolution::KeepConflictedCopy => "keep_conflicted_copy",
    }
}

impl TrashMoveGuard {
    fn move_to_trash(path: &Path, expected: &super::types::VersionState) -> CoreResult<Self> {
        let trash_path = storage::move_to_user_trash_checked(
            path,
            &expected.file_identity,
            expected.size_bytes,
            expected.modified_at_nanos,
            &expected.hash_sha256,
        )?;
        Ok(Self {
            original_path: path.to_path_buf(),
            trash_path,
            armed: true,
        })
    }

    fn rollback(&mut self) -> CoreResult<()> {
        if self.armed {
            if let Some(trash_path) = &self.trash_path {
                if is_regular_no_follow(trash_path)? && !path_exists_no_follow(&self.original_path)?
                {
                    storage::move_recoverable_file(trash_path, &self.original_path)?;
                }
            }
            self.armed = false;
        }
        Ok(())
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

fn path_exists_no_follow(path: &Path) -> CoreResult<bool> {
    match std::fs::symlink_metadata(path) {
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(map_io_error(error)),
    }
}

fn is_regular_no_follow(path: &Path) -> CoreResult<bool> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) => Ok(metadata.is_file() && !metadata.file_type().is_symlink()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(map_io_error(error)),
    }
}

impl Drop for TrashMoveGuard {
    fn drop(&mut self) {
        let _rollback_result = self.rollback();
    }
}
