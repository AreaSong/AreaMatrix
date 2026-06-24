use std::path::{Path, PathBuf};

use crate::{CoreError, CoreResult, StorageMode};

use super::super::hash;

const AREA_MATRIX_DIR: &str = ".areamatrix";

pub(super) fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(PathBuf::from(repo_path))
}

pub(super) fn repo_relative_file_path(repo: &Path, relative_path: &str) -> CoreResult<PathBuf> {
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

pub(super) fn ensure_regular_file(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(hash::map_io_error)?;
    if metadata.is_file() {
        Ok(())
    } else {
        Err(CoreError::file_not_found("missing file"))
    }
}

pub(super) fn filename_from_path(path: &Path) -> CoreResult<String> {
    path.file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| CoreError::invalid_path("invalid path"))
}

pub(super) fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|error| CoreError::invalid_path(error.to_string()))
        .map(|relative| relative.to_string_lossy().into_owned())
}

pub(super) fn storage_mode_detail(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

pub(super) fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(hash::map_io_error)
}
