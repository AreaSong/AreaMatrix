use std::path::Path;

use crate::{CoreError, CoreResult, FileEntry, MoveToCategoryPreview, StorageMode};

use super::{
    super::dedup,
    detail::{is_indexed, preview_for_entry},
    paths::{ensure_regular_file, repo_relative_file_path},
};

pub(super) fn preview_same_category_entry(
    repo: &Path,
    entry: &FileEntry,
    new_category: &str,
) -> CoreResult<MoveToCategoryPreview> {
    if matches!(entry.storage_mode, StorageMode::Moved | StorageMode::Copied) {
        if !dedup::is_repo_owned(entry) {
            return Err(CoreError::invalid_path("invalid path"));
        }
        ensure_regular_file(&repo_relative_file_path(repo, &entry.path)?)?;
    }

    Ok(preview_for_entry(
        entry,
        new_category,
        &entry.path,
        &entry.current_name,
        is_indexed(&entry.storage_mode),
        false,
    ))
}

pub(super) fn validate_same_category_entry(repo: &Path, entry: FileEntry) -> CoreResult<FileEntry> {
    if matches!(entry.storage_mode, StorageMode::Moved | StorageMode::Copied) {
        if !dedup::is_repo_owned(&entry) {
            return Err(CoreError::invalid_path("invalid path"));
        }
        ensure_regular_file(&repo_relative_file_path(repo, &entry.path)?)?;
    }
    Ok(entry)
}
