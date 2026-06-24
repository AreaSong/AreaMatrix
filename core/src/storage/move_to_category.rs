mod detail;
mod guards;
mod paths;
mod repo_owned;
mod same_category;
mod target;

use crate::{classify, db, CoreError, CoreResult, FileEntry, MoveToCategoryPreview, StorageMode};

use self::{
    paths::validate_repo_path,
    repo_owned::{
        move_indexed_file, move_repo_owned_file, move_repo_owned_file_without_undo,
        preview_repo_owned_file,
    },
    same_category::{preview_same_category_entry, validate_same_category_entry},
};

pub(crate) fn preview_move_to_category(
    repo_path: String,
    file_id: i64,
    new_category: String,
) -> CoreResult<MoveToCategoryPreview> {
    let repo = validate_repo_path(&repo_path)?;
    db::ensure_initialized(&repo)?;
    classify::ensure_category_exists(&repo, &new_category)?;

    let entry = db::get_active_file_by_id(&repo, file_id)?;
    if entry.category == new_category {
        return preview_same_category_entry(&repo, &entry, &new_category);
    }

    match entry.storage_mode {
        StorageMode::Moved | StorageMode::Copied => {
            preview_repo_owned_file(&repo, &entry, &new_category)
        }
        StorageMode::Indexed => Ok(detail::preview_for_entry(
            &entry,
            &new_category,
            &entry.path,
            &entry.current_name,
            true,
            false,
        )),
    }
}

pub(crate) fn move_to_category(
    repo_path: String,
    file_id: i64,
    new_category: String,
) -> CoreResult<FileEntry> {
    let repo = validate_repo_path(&repo_path)?;
    db::ensure_initialized(&repo)?;
    classify::ensure_category_exists(&repo, &new_category)?;

    let entry = db::get_active_file_by_id(&repo, file_id)?;
    if entry.category == new_category {
        return validate_same_category_entry(&repo, entry);
    }

    match entry.storage_mode {
        StorageMode::Moved | StorageMode::Copied => {
            move_repo_owned_file(&repo, entry, &new_category)
        }
        StorageMode::Indexed => move_indexed_file(&repo, entry, &new_category),
    }
}

pub(crate) fn correct_repo_owned_file_category(
    repo_path: String,
    file_id: i64,
    new_category: String,
) -> CoreResult<FileEntry> {
    let repo = validate_repo_path(&repo_path)?;
    db::ensure_initialized(&repo)?;
    classify::ensure_category_exists(&repo, &new_category)?;

    let entry = db::get_active_file_by_id(&repo, file_id)?;
    if entry.category == new_category {
        return validate_same_category_entry(&repo, entry);
    }

    match entry.storage_mode {
        StorageMode::Moved | StorageMode::Copied => {
            move_repo_owned_file_without_undo(&repo, entry, &new_category)
        }
        StorageMode::Indexed => Err(CoreError::invalid_path("invalid path")),
    }
}
