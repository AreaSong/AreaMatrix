use std::path::{Path, PathBuf};

use crate::{
    db, storage, CoreResult, ICloudConflictResolution, ICloudConflictResolveReport,
    ICloudConflictStatus,
};

use super::{paths::map_io_error, types::ConflictBinding};

const CHANGE_LOG_ACTION: &str = "external_modified";

pub(super) fn resolve_keep_both(
    repo: &Path,
    binding: &ConflictBinding,
    resolution: ICloudConflictResolution,
) -> CoreResult<ICloudConflictResolveReport> {
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
) -> CoreResult<ICloudConflictResolveReport> {
    let mut guard = TrashMoveGuard::move_to_trash(discard_path)?;
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
    fn move_to_trash(path: &Path) -> CoreResult<Self> {
        let trash_path = storage::move_to_user_trash(path)?;
        Ok(Self {
            original_path: path.to_path_buf(),
            trash_path,
            armed: true,
        })
    }

    fn rollback(&mut self) -> CoreResult<()> {
        if self.armed {
            if let Some(trash_path) = &self.trash_path {
                if trash_path.try_exists().map_err(map_io_error)?
                    && !self.original_path.try_exists().map_err(map_io_error)?
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

impl Drop for TrashMoveGuard {
    fn drop(&mut self) {
        let _rollback_result = self.rollback();
    }
}
