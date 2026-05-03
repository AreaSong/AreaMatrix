use std::{
    ffi::OsStr,
    fs,
    path::{Component, Path, PathBuf},
};

use serde_json::json;

use crate::{db, CoreError, CoreResult, FileEntry, FileOrigin, StorageMode};

use super::{
    dedup, hash, replacement_trash::send_to_system_trash, safe_move::move_recoverable_file,
};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const ARCHIVES_DIR: &str = "archives";

pub(crate) fn delete_file(repo_path: String, file_id: i64) -> CoreResult<()> {
    let repo = validate_repo_path(&repo_path)?;
    db::ensure_initialized(&repo)?;
    let entry = db::get_active_file_by_id(&repo, file_id)?;
    ensure_repo_owned_entry(&entry)?;

    let target_path = repo_relative_file_path(&repo, &entry.path)?;
    ensure_regular_file(&target_path)?;
    let archive_path = delete_archive_path(&repo, &target_path)?;
    let detail = delete_detail(&entry);
    let mut guard = DeleteArchiveGuard::archive(target_path, archive_path)?;

    db::soft_delete_repo_owned_file(&repo, entry.id, &detail)?;
    if let Err(error) = send_to_system_trash(guard.archived_path()) {
        guard.rollback()?;
        db::rollback_deleted_repo_owned_file(&repo, entry.id, &detail)?;
        return Err(error);
    }

    guard.disarm();
    Ok(())
}

pub(crate) fn remove_index_entry(repo_path: String, file_id: i64) -> CoreResult<()> {
    let repo = validate_repo_path(&repo_path)?;
    db::ensure_initialized(&repo)?;
    let entry = db::get_active_file_by_id(&repo, file_id)?;
    ensure_index_removable_entry(&entry)?;
    db::remove_index_entry_row(&repo, entry.id, &remove_index_detail(&entry))
}

fn ensure_repo_owned_entry(entry: &FileEntry) -> CoreResult<()> {
    if dedup::is_repo_owned(entry) {
        Ok(())
    } else {
        Err(CoreError::permission_denied("permission denied"))
    }
}

fn ensure_index_removable_entry(entry: &FileEntry) -> CoreResult<()> {
    if matches!(entry.storage_mode, StorageMode::Indexed)
        || matches!(entry.origin, FileOrigin::Adopted | FileOrigin::External)
    {
        Ok(())
    } else {
        Err(CoreError::permission_denied("permission denied"))
    }
}

fn delete_detail(entry: &FileEntry) -> serde_json::Value {
    json!({
        "hard": false,
        "by": "user",
        "from_path": entry.path,
        "storage_mode": storage_mode_detail(&entry.storage_mode),
        "trash_location": "system",
        "trashed": true,
    })
}

fn remove_index_detail(entry: &FileEntry) -> serde_json::Value {
    json!({
        "by": "user",
        "index_only": true,
        "path": entry.path,
        "storage_mode": storage_mode_detail(&entry.storage_mode),
        "origin": origin_detail(&entry.origin),
    })
}

fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(PathBuf::from(repo_path))
}

fn repo_relative_file_path(repo: &Path, relative_path: &str) -> CoreResult<PathBuf> {
    let relative = Path::new(relative_path);
    validate_repo_relative_path(relative)?;
    Ok(repo.join(relative))
}

fn validate_repo_relative_path(path: &Path) -> CoreResult<()> {
    if path.is_absolute() || path.as_os_str().is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    for component in path.components() {
        let Component::Normal(part) = component else {
            return Err(CoreError::invalid_path("invalid path"));
        };
        if part == OsStr::new(AREA_MATRIX_DIR) {
            return Err(CoreError::invalid_path("invalid path"));
        }
    }
    Ok(())
}

fn ensure_regular_file(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(hash::map_io_error)?;
    if metadata.is_file() {
        Ok(())
    } else {
        Err(CoreError::file_not_found("missing file"))
    }
}

fn delete_archive_path(repo: &Path, target_path: &Path) -> CoreResult<PathBuf> {
    let file_name = target_path
        .file_name()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    Ok(repo
        .join(AREA_MATRIX_DIR)
        .join(ARCHIVES_DIR)
        .join(format!("delete-{}", uuid::Uuid::new_v4()))
        .join(file_name))
}

fn storage_mode_detail(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

fn origin_detail(origin: &FileOrigin) -> &'static str {
    match origin {
        FileOrigin::Imported => "imported",
        FileOrigin::Adopted => "adopted",
        FileOrigin::External => "external",
    }
}

struct DeleteArchiveGuard {
    original_path: PathBuf,
    archived_path: PathBuf,
    archive_dir: PathBuf,
    armed: bool,
}

impl DeleteArchiveGuard {
    fn archive(original_path: PathBuf, archived_path: PathBuf) -> CoreResult<Self> {
        let archive_dir = archived_path
            .parent()
            .ok_or_else(|| CoreError::invalid_path("invalid path"))?
            .to_path_buf();
        fs::create_dir_all(&archive_dir).map_err(hash::map_io_error)?;
        move_recoverable_file(&original_path, &archived_path)?;
        Ok(Self {
            original_path,
            archived_path,
            archive_dir,
            armed: true,
        })
    }

    fn archived_path(&self) -> &Path {
        &self.archived_path
    }

    fn rollback(&mut self) -> CoreResult<()> {
        if self.armed && self.archived_path.exists() && !self.original_path.exists() {
            move_recoverable_file(&self.archived_path, &self.original_path)?;
        }
        self.cleanup_archive_dir();
        self.armed = false;
        Ok(())
    }

    fn disarm(&mut self) {
        self.cleanup_archive_dir();
        self.armed = false;
    }

    fn cleanup_archive_dir(&self) {
        let _cleanup_result = fs::remove_dir(&self.archive_dir);
    }
}

impl Drop for DeleteArchiveGuard {
    fn drop(&mut self) {
        if self.armed && self.archived_path.exists() && !self.original_path.exists() {
            let _restore_result = move_recoverable_file(&self.archived_path, &self.original_path);
        }
        self.cleanup_archive_dir();
    }
}
