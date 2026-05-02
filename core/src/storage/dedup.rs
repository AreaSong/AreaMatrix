use std::path::{Path, PathBuf};

use crate::{CoreError, CoreResult, DuplicateStrategy, FileEntry, StorageMode};

use super::hash;

#[derive(Clone, Debug, PartialEq)]
pub(super) enum DuplicateResolution {
    NoDuplicate,
    KeepBoth,
    Overwrite {
        existing: FileEntry,
        reason: ReplacementReason,
    },
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) enum ReplacementReason {
    DuplicateHash,
    NameConflict,
}

pub(super) fn resolve_duplicate(
    strategy: &DuplicateStrategy,
    existing: Option<FileEntry>,
) -> CoreResult<DuplicateResolution> {
    let Some(existing) = existing else {
        return Ok(DuplicateResolution::NoDuplicate);
    };

    match strategy {
        DuplicateStrategy::KeepBoth => Ok(DuplicateResolution::KeepBoth),
        DuplicateStrategy::Overwrite => Ok(DuplicateResolution::Overwrite {
            existing,
            reason: ReplacementReason::DuplicateHash,
        }),
        DuplicateStrategy::Skip | DuplicateStrategy::Ask => {
            tracing::warn!(
                existing_path = %existing.path,
                "duplicate file detected before import commit"
            );
            Err(CoreError::DuplicateFile {
                existing_path: existing.path,
            })
        }
    }
}

pub(super) fn resolve_final_path(
    directory: &Path,
    filename: &str,
    resolution: DuplicateResolution,
) -> CoreResult<PathBuf> {
    match resolution {
        DuplicateResolution::NoDuplicate | DuplicateResolution::KeepBoth => {
            resolve_numbered_path(directory, filename)
        }
        DuplicateResolution::Overwrite { .. } => Err(CoreError::Internal),
    }
}

pub(super) fn resolve_rename_path(
    directory: &Path,
    filename: &str,
    current_path: &Path,
) -> CoreResult<PathBuf> {
    let candidate = directory.join(filename);
    if candidate == current_path || !path_exists(&candidate)? {
        return Ok(candidate);
    }

    for index in 1..1000 {
        let candidate = directory.join(numbered_filename(filename, index));
        if candidate == current_path || !path_exists(&candidate)? {
            return Ok(candidate);
        }
    }

    Err(CoreError::Conflict)
}

pub(super) fn is_repo_owned(entry: &FileEntry) -> bool {
    matches!(entry.storage_mode, StorageMode::Copied | StorageMode::Moved)
}

fn resolve_numbered_path(directory: &Path, filename: &str) -> CoreResult<PathBuf> {
    let candidate = directory.join(filename);
    if !path_exists(&candidate)? {
        return Ok(candidate);
    }

    for index in 1..1000 {
        let candidate = directory.join(numbered_filename(filename, index));
        if !path_exists(&candidate)? {
            return Ok(candidate);
        }
    }

    Err(CoreError::Conflict)
}

fn numbered_filename(filename: &str, index: usize) -> String {
    if filename.starts_with('.') && filename.matches('.').count() == 1 {
        return format!("{filename}_{index}");
    }

    match filename.rsplit_once('.') {
        Some((stem, extension)) if !stem.is_empty() => format!("{stem}_{index}.{extension}"),
        _ => format!("{filename}_{index}"),
    }
}

fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(hash::map_io_error)
}
