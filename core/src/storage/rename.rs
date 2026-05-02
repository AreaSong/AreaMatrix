use std::path::{Path, PathBuf};

use serde_json::json;

use crate::{db, overview, CoreError, CoreResult, FileEntry};

use super::{dedup, hash, safe_move::move_recoverable_file, validate};

const AREA_MATRIX_DIR: &str = ".areamatrix";

pub(crate) fn rename_file(
    repo_path: String,
    file_id: i64,
    new_name: String,
) -> CoreResult<FileEntry> {
    let repo = validate_repo_path(&repo_path)?;
    db::ensure_initialized(&repo)?;
    validate::filename(&new_name)?;

    let entry = db::get_active_file_by_id(&repo, file_id)?;
    if !dedup::is_repo_owned(&entry) {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let current_path = repo_relative_file_path(&repo, &entry.path)?;
    ensure_regular_file(&current_path)?;
    let target_directory = current_path
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    let final_path = dedup::resolve_rename_path(target_directory, &new_name, &current_path)?;
    if final_path == current_path {
        return Ok(entry);
    }

    let final_name = filename_from_path(&final_path)?;
    let final_relative_path = relative_repo_path(&repo, &final_path)?;
    move_recoverable_file(&current_path, &final_path)?;
    let mut guard = RenameRollbackGuard::new(final_path.clone(), current_path.clone());

    db::rename_active_file(
        &repo,
        file_id,
        &final_relative_path,
        &final_name,
        &rename_detail(&entry, &new_name, &final_relative_path, &final_name),
    )?;
    guard.disarm();
    let updated = db::get_active_file_by_id(&repo, file_id)?;
    overview::regenerate_for_node(&repo, &updated.category)?;
    Ok(updated)
}

fn rename_detail(
    entry: &FileEntry,
    requested_name: &str,
    final_path: &str,
    final_name: &str,
) -> serde_json::Value {
    json!({
        "from_path": entry.path,
        "to_path": final_path,
        "from_name": entry.current_name,
        "requested_name": requested_name,
        "final_name": final_name,
        "name_conflict_resolved": requested_name != final_name,
        "by": "user",
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
        let std::path::Component::Normal(part) = component else {
            return Err(CoreError::invalid_path("invalid path"));
        };
        if part == std::ffi::OsStr::new(AREA_MATRIX_DIR) {
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

fn filename_from_path(path: &Path) -> CoreResult<String> {
    path.file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| CoreError::invalid_path("invalid path"))
}

fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|error| CoreError::invalid_path(error.to_string()))
        .map(|relative| relative.to_string_lossy().into_owned())
}

struct RenameRollbackGuard {
    current_path: PathBuf,
    original_path: PathBuf,
    armed: bool,
}

impl RenameRollbackGuard {
    fn new(current_path: PathBuf, original_path: PathBuf) -> Self {
        Self {
            current_path,
            original_path,
            armed: true,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for RenameRollbackGuard {
    fn drop(&mut self) {
        if self.armed && self.current_path.exists() && !self.original_path.exists() {
            let _restore_result = move_recoverable_file(&self.current_path, &self.original_path);
        }
    }
}
