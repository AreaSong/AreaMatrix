use std::{
    ffi::OsStr,
    path::{Component, Path, PathBuf},
};

use crate::{CoreError, CoreResult};

use super::AREA_MATRIX_DIR;

const STAGING_DIR: &str = "staging";

pub(super) fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::permission_denied("repository path is required"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::permission_denied("repository path is invalid"));
    }
    Ok(repo)
}

pub(super) fn ensure_staging_file_matches(repo: &Path, relative_path: &str) -> CoreResult<()> {
    let absolute = staging_file_path(repo, relative_path)?;
    if absolute.try_exists().map_err(map_io_error)? {
        return Ok(());
    }
    Err(CoreError::staging_recovery_required(
        relative_path.to_owned(),
    ))
}

pub(super) fn ensure_existing_replace_target(path: &Path) -> CoreResult<()> {
    if path.try_exists().map_err(map_io_error)? {
        return Ok(());
    }
    Err(CoreError::file_not_found("missing file"))
}

pub(super) fn repo_relative_file_path(repo: &Path, relative_path: &str) -> CoreResult<PathBuf> {
    let relative = Path::new(relative_path);
    validate_repo_relative_path(relative, false)?;
    Ok(repo.join(relative))
}

pub(super) fn staging_file_path(repo: &Path, relative_path: &str) -> CoreResult<PathBuf> {
    let relative = Path::new(relative_path);
    validate_staging_relative_path(relative)?;
    Ok(repo.join(relative))
}

pub(super) fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|error| CoreError::invalid_path(error.to_string()))
        .map(|relative| relative.to_string_lossy().into_owned())
}

pub(super) fn resolve_keep_both_path(
    repo: &Path,
    target_path: &str,
    force_numbered: bool,
) -> CoreResult<PathBuf> {
    let original = repo_relative_file_path(repo, target_path)?;
    let parent = original
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    let filename = filename_from_path(&original)?;
    let start_index = usize::from(force_numbered);
    resolve_numbered_path(parent, &filename, start_index)
}

pub(super) fn filename_from_path(path: &Path) -> CoreResult<String> {
    path.file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| CoreError::invalid_path("invalid path"))
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

fn validate_repo_relative_path(path: &Path, allow_empty: bool) -> CoreResult<()> {
    if path.is_absolute() || (!allow_empty && path.as_os_str().is_empty()) {
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

fn validate_staging_relative_path(path: &Path) -> CoreResult<()> {
    if path.is_absolute() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    let mut components = path.components();
    if components.next() != Some(Component::Normal(OsStr::new(AREA_MATRIX_DIR)))
        || components.next() != Some(Component::Normal(OsStr::new(STAGING_DIR)))
    {
        return Err(CoreError::invalid_path("invalid staging path"));
    }
    let mut has_filename = false;
    for component in components {
        let Component::Normal(part) = component else {
            return Err(CoreError::invalid_path("invalid staging path"));
        };
        if part.is_empty() {
            return Err(CoreError::invalid_path("invalid staging path"));
        }
        has_filename = true;
    }
    if has_filename {
        Ok(())
    } else {
        Err(CoreError::invalid_path("invalid staging path"))
    }
}

fn resolve_numbered_path(
    directory: &Path,
    filename: &str,
    start_index: usize,
) -> CoreResult<PathBuf> {
    for index in start_index..1000 {
        let candidate = if index == 0 {
            directory.join(filename)
        } else {
            directory.join(numbered_filename(filename, index))
        };
        if !candidate.try_exists().map_err(map_io_error)? {
            return Ok(candidate);
        }
    }
    Err(CoreError::conflict("path conflict"))
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

fn is_area_matrix_component(component: Component<'_>) -> bool {
    matches!(component, Component::Normal(value) if value == AREA_MATRIX_DIR)
}
