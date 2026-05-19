use std::{
    ffi::OsStr,
    fs::Metadata,
    path::{Component, Path, PathBuf},
};

use crate::{CoreError, CoreResult};

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
        let Component::Normal(part) = component else {
            return Err(CoreError::invalid_path("invalid path"));
        };
        if part == OsStr::new(super::AREA_MATRIX_DIR) {
            return Err(CoreError::invalid_path("invalid path"));
        }
    }
    Ok(())
}

pub(super) fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|error| CoreError::invalid_path(error.to_string()))
        .map(|relative| relative.to_string_lossy().into_owned())
}

pub(super) fn ensure_regular_file(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(map_io_error)?;
    if metadata.is_file() {
        Ok(())
    } else {
        Err(CoreError::file_not_found("missing file"))
    }
}

pub(super) fn ensure_file_and_parent_writable(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(map_io_error)?;
    if !metadata_allows_write(&metadata) {
        return Err(CoreError::permission_denied(path.display().to_string()));
    }
    let parent = path
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    ensure_directory_writable(parent)
}

fn ensure_directory_writable(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(map_io_error)?;
    if !metadata.is_dir() {
        return Err(CoreError::conflict(path.display().to_string()));
    }
    if metadata_allows_write(&metadata) {
        Ok(())
    } else {
        Err(CoreError::permission_denied(path.display().to_string()))
    }
}

pub(super) fn ensure_indexed_source_present(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(map_io_error)?;
    if metadata.is_file() {
        Ok(())
    } else {
        Err(CoreError::file_not_found("missing file"))
    }
}

#[cfg(unix)]
fn metadata_allows_write(metadata: &Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt;

    metadata.permissions().mode() & 0o222 != 0
}

#[cfg(not(unix))]
fn metadata_allows_write(metadata: &Metadata) -> bool {
    !metadata.permissions().readonly()
}

pub(super) fn sidecar_path_for_file(file_path: &Path) -> CoreResult<PathBuf> {
    let parent = file_path
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    let file_name = file_path
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    Ok(parent.join(format!("{file_name}.md")))
}

pub(super) fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(map_io_error)
}

pub(super) fn map_io_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::AlreadyExists => CoreError::conflict("path conflict"),
        std::io::ErrorKind::NotFound => CoreError::file_not_found("missing file"),
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}
