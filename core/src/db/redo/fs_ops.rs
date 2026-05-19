use std::{
    ffi::OsStr,
    fs,
    path::{Component, Path, PathBuf},
};

use crate::{storage, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";

pub(super) struct FileMoveRollbackGuard {
    current_path: PathBuf,
    original_path: PathBuf,
    armed: bool,
}

impl FileMoveRollbackGuard {
    fn new(current_path: PathBuf, original_path: PathBuf) -> Self {
        Self {
            current_path,
            original_path,
            armed: true,
        }
    }

    pub(super) fn disarm(&mut self) {
        self.armed = false;
    }

    pub(super) fn rollback(&mut self) {
        if self.armed && self.current_path.exists() && !self.original_path.exists() {
            let _restore_result = move_file_no_replace(&self.current_path, &self.original_path);
        }
        self.armed = false;
    }
}

impl Drop for FileMoveRollbackGuard {
    fn drop(&mut self) {
        self.rollback();
    }
}

pub(super) fn repo_relative_path(repo: &Path, relative_path: &str) -> CoreResult<PathBuf> {
    let relative = Path::new(relative_path);
    validate_repo_relative_path(relative)?;
    Ok(repo.join(relative))
}

pub(super) fn move_checked_path(
    current_path: &Path,
    destination: &Path,
) -> CoreResult<FileMoveRollbackGuard> {
    if !current_path.try_exists().map_err(map_io_error)? {
        return Err(CoreError::file_not_found(
            current_path.display().to_string(),
        ));
    }
    if destination.try_exists().map_err(map_io_error)? {
        return Err(CoreError::conflict(destination.display().to_string()));
    }
    move_file_no_replace(current_path, destination)?;
    Ok(FileMoveRollbackGuard::new(
        destination.to_path_buf(),
        current_path.to_path_buf(),
    ))
}

pub(super) fn move_path_to_user_trash(path: &Path) -> CoreResult<FileMoveRollbackGuard> {
    let trash_path = storage::move_to_user_trash(path)?
        .ok_or_else(|| CoreError::io("trash path unavailable"))?;
    Ok(FileMoveRollbackGuard::new(trash_path, path.to_path_buf()))
}

pub(super) fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(map_io_error)
}

pub(super) fn map_io_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::NotFound => CoreError::file_not_found(error.to_string()),
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied(error.to_string()),
        std::io::ErrorKind::AlreadyExists => CoreError::conflict(error.to_string()),
        _ => CoreError::io(error.to_string()),
    }
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

fn move_file_no_replace(current_path: &Path, destination: &Path) -> CoreResult<()> {
    match fs::hard_link(current_path, destination) {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            return Err(CoreError::conflict(destination.display().to_string()));
        }
        Err(_) => copy_to_new_destination(current_path, destination)?,
    }
    fs::remove_file(current_path).map_err(|error| {
        let _cleanup_result = fs::remove_file(destination);
        map_io_error(error)
    })
}

fn copy_to_new_destination(current_path: &Path, destination: &Path) -> CoreResult<()> {
    let expected_size = current_path.metadata().map_err(map_io_error)?.len();
    let copied_size = fs::copy(current_path, destination).map_err(map_io_error)?;
    if copied_size != expected_size {
        let _cleanup_result = fs::remove_file(destination);
        return Err(CoreError::io("io error"));
    }
    Ok(())
}
