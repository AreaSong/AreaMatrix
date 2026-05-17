use std::{
    ffi::OsStr,
    fs,
    fs::Metadata,
    path::{Component, Path, PathBuf},
};

use crate::{storage, CoreError, CoreResult, FileEntry};

use super::plan::PlannedSidecarMove;

const AREA_MATRIX_DIR: &str = ".areamatrix";

pub(super) struct RepoOwnedMoveTarget {
    pub(super) current_path: PathBuf,
    pub(super) final_path: PathBuf,
    pub(super) final_relative_path: String,
    pub(super) final_name: String,
}

pub(super) fn resolve_repo_owned_target(
    repo: &Path,
    target_directory: &Path,
    entry: &FileEntry,
) -> CoreResult<RepoOwnedMoveTarget> {
    let current_path = repo_relative_file_path(repo, &entry.path)?;
    ensure_regular_file(&current_path)?;
    let final_path =
        storage::dedup::resolve_rename_path(target_directory, &entry.current_name, &current_path)?;
    let final_name = filename_from_path(&final_path)?;
    let final_relative_path = relative_repo_path(repo, &final_path)?;
    Ok(RepoOwnedMoveTarget {
        current_path,
        final_path,
        final_relative_path,
        final_name,
    })
}

pub(super) fn preview_category_directory(repo: &Path, category: &str) -> CoreResult<PathBuf> {
    let path = repo.join(category);
    if path_exists(&path)? {
        if path.is_dir() {
            return Ok(path);
        }
        return Err(CoreError::conflict("path conflict"));
    }
    Ok(path)
}

pub(super) fn ensure_category_directory_writable(path: &Path) -> CoreResult<()> {
    if path_exists(path)? {
        return ensure_directory_writable(path);
    }
    let parent = path
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    ensure_directory_writable(parent)
}

pub(super) fn plan_note_sidecar(
    repo: &Path,
    file_id: i64,
    current_file: &Path,
    final_file: &Path,
) -> CoreResult<Option<PlannedSidecarMove>> {
    let Some(note_content) = crate::db::read_note_content(repo, file_id)? else {
        return Ok(None);
    };
    let current_path = sidecar_path_for_file(current_file)?;
    let final_path = sidecar_path_for_file(final_file)?;
    let sidecar_content = fs::read_to_string(&current_path).map_err(map_io_error)?;
    if sidecar_content != note_content {
        return Err(CoreError::db("database error"));
    }
    if final_path.try_exists().map_err(map_io_error)? {
        return Err(CoreError::conflict("path conflict"));
    }
    Ok(Some(PlannedSidecarMove {
        current_path,
        final_path,
    }))
}

pub(super) fn ensure_repo_owned_file(repo: &Path, entry: &FileEntry) -> CoreResult<()> {
    let current_path = repo_relative_file_path(repo, &entry.path)?;
    ensure_regular_file(&current_path)
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
    let metadata = path.metadata().map_err(map_io_error)?;
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

fn sidecar_path_for_file(file_path: &Path) -> CoreResult<PathBuf> {
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

fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(map_io_error)
}

fn ensure_directory_writable(path: &Path) -> CoreResult<()> {
    let metadata = fs::metadata(path).map_err(map_io_error)?;
    if !metadata.is_dir() {
        return Err(CoreError::conflict(path.display().to_string()));
    }
    if metadata_allows_write(&metadata) {
        Ok(())
    } else {
        Err(CoreError::permission_denied(path.display().to_string()))
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
