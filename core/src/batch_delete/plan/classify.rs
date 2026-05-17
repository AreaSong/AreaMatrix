use std::path::{Path, PathBuf};

use crate::{
    db, storage::dedup::is_repo_owned, BatchDeleteMode, CoreError, CoreResult, FileEntry,
    FileOrigin, StorageMode,
};

use super::{
    blocked_from_entry, inspect_current_file_state, inspect_current_optional_state,
    inspect_optional_state, path_exists, path_is_writable_dir, planned_item, skipped,
    skipped_from_entry, BatchDeletePlanItem, InspectedPathState, PathInspection,
};
use crate::batch_delete::inspect::inspect_path;

pub(super) fn plan_batch_delete_item(
    repo: &Path,
    file_id: i64,
    delete_mode: &BatchDeleteMode,
    trash_available: bool,
) -> CoreResult<BatchDeletePlanItem> {
    let entry = match active_entry(repo, file_id)? {
        Some(entry) => entry,
        None => {
            return Ok(skipped(
                file_id,
                None,
                None,
                None,
                None,
                "File is no longer active",
            ))
        }
    };
    let current_path = path_for_entry(repo, &entry)?;
    match classify_entry(&entry, &current_path) {
        EntryDeleteClass::RepoOwnedAvailable => {
            repo_owned_plan_item(entry, current_path, delete_mode, trash_available)
        }
        EntryDeleteClass::IndexOnlyAvailable => index_only_plan_item(
            entry,
            current_path,
            delete_mode,
            "Index-only entries are removed from metadata only",
        ),
        EntryDeleteClass::MetadataOnlyMissing => Ok(BatchDeletePlanItem::Missing(planned_item(
            entry,
            current_path,
            InspectedPathState::missing(),
        ))),
        EntryDeleteClass::Blocked { error, state } => Ok(blocked_from_entry(entry, state, error)),
    }
}

pub(super) fn preview_trash_available() -> CoreResult<bool> {
    let Some(home) = std::env::var_os("HOME") else {
        return Ok(false);
    };
    let trash_dir = PathBuf::from(home).join(".Trash");
    if path_exists(&trash_dir)? {
        return Ok(true);
    }
    let Some(parent) = trash_dir.parent() else {
        return Ok(false);
    };
    path_is_writable_dir(parent)
}

fn repo_owned_plan_item(
    entry: FileEntry,
    current_path: PathBuf,
    delete_mode: &BatchDeleteMode,
    trash_available: bool,
) -> CoreResult<BatchDeletePlanItem> {
    let inspected_state = inspect_current_file_state(&current_path)?;
    match delete_mode {
        BatchDeleteMode::MoveToTrash if trash_available => Ok(BatchDeletePlanItem::MoveToTrash(
            planned_item(entry, current_path, inspected_state),
        )),
        BatchDeleteMode::MoveToTrash => Ok(blocked_from_entry(
            entry,
            Some(inspected_state),
            CoreError::permission_denied("Trash is unavailable"),
        )),
        BatchDeleteMode::RemoveFromIndex => Ok(skipped_from_entry(
            entry,
            Some(inspected_state),
            "Repo-owned files must use MoveToTrash",
        )),
    }
}

fn index_only_plan_item(
    entry: FileEntry,
    current_path: PathBuf,
    delete_mode: &BatchDeleteMode,
    skipped_reason: &str,
) -> CoreResult<BatchDeletePlanItem> {
    match delete_mode {
        BatchDeleteMode::MoveToTrash => Ok(skipped_from_entry(
            entry,
            inspect_optional_state(&current_path)?,
            skipped_reason,
        )),
        BatchDeleteMode::RemoveFromIndex => {
            let inspected_state = inspect_current_optional_state(&current_path)?;
            Ok(BatchDeletePlanItem::RemoveFromIndex(planned_item(
                entry,
                current_path,
                inspected_state,
            )))
        }
    }
}

enum EntryDeleteClass {
    RepoOwnedAvailable,
    IndexOnlyAvailable,
    MetadataOnlyMissing,
    Blocked {
        error: CoreError,
        state: Option<InspectedPathState>,
    },
}

fn classify_entry(entry: &FileEntry, current_path: &Path) -> EntryDeleteClass {
    if is_repo_owned(entry) {
        return match inspect_path(current_path) {
            Ok(PathInspection::File(_)) => EntryDeleteClass::RepoOwnedAvailable,
            Ok(PathInspection::Missing) => EntryDeleteClass::MetadataOnlyMissing,
            Ok(PathInspection::Other) => EntryDeleteClass::Blocked {
                error: CoreError::file_not_found(current_path.display().to_string()),
                state: None,
            },
            Err(error) => EntryDeleteClass::Blocked { error, state: None },
        };
    }
    if matches!(entry.storage_mode, StorageMode::Indexed)
        || matches!(entry.origin, FileOrigin::Adopted | FileOrigin::External)
    {
        match inspect_path(current_path) {
            Ok(PathInspection::Other) => {
                return EntryDeleteClass::Blocked {
                    error: CoreError::file_not_found(current_path.display().to_string()),
                    state: None,
                }
            }
            Ok(PathInspection::File(_) | PathInspection::Missing) => {
                return EntryDeleteClass::IndexOnlyAvailable
            }
            Err(error) => return EntryDeleteClass::Blocked { error, state: None },
        }
    }
    EntryDeleteClass::Blocked {
        error: CoreError::permission_denied("Unsupported file entry"),
        state: None,
    }
}

fn active_entry(repo: &Path, file_id: i64) -> CoreResult<Option<FileEntry>> {
    match db::get_active_file_by_id(repo, file_id) {
        Ok(entry) => Ok(Some(entry)),
        Err(CoreError::FileNotFound { .. }) => Ok(None),
        Err(error) => Err(error),
    }
}

fn path_for_entry(repo: &Path, entry: &FileEntry) -> CoreResult<PathBuf> {
    if is_repo_owned(entry) {
        return super::super::repo_relative_file_path(repo, &entry.path);
    }
    if let Some(source_path) = &entry.source_path {
        return Ok(PathBuf::from(source_path));
    }
    Ok(PathBuf::from(&entry.path))
}
