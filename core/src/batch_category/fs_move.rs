use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{CoreError, CoreResult};

pub(super) struct CategoryDirectoryGuard {
    path: PathBuf,
    created: bool,
    armed: bool,
}

impl CategoryDirectoryGuard {
    pub(super) fn ensure(path: PathBuf) -> CoreResult<Self> {
        if path.try_exists().map_err(map_io_error)? {
            if path.is_dir() {
                return Ok(Self {
                    path,
                    created: false,
                    armed: false,
                });
            }
            return Err(CoreError::conflict("path conflict"));
        }
        fs::create_dir(&path).map_err(map_io_error)?;
        Ok(Self {
            path,
            created: true,
            armed: true,
        })
    }

    pub(super) fn disarm(&mut self) {
        self.armed = false;
    }

    fn rollback(&mut self) {
        if self.armed && self.created {
            let _cleanup_result = fs::remove_dir(&self.path);
        }
        self.armed = false;
    }
}

impl Drop for CategoryDirectoryGuard {
    fn drop(&mut self) {
        self.rollback();
    }
}

pub(super) struct AppliedFsMove {
    pub(super) note_guard: Option<MoveRollbackGuard>,
    pub(super) file_guard: MoveRollbackGuard,
    pub(super) directory_guard: CategoryDirectoryGuard,
}

impl AppliedFsMove {
    pub(super) fn disarm(&mut self) {
        if let Some(note_guard) = self.note_guard.as_mut() {
            note_guard.disarm();
        }
        self.file_guard.disarm();
        self.directory_guard.disarm();
    }
}

impl Drop for AppliedFsMove {
    fn drop(&mut self) {
        if let Some(note_guard) = self.note_guard.as_mut() {
            let _rollback_result = note_guard.rollback();
        }
        let _rollback_result = self.file_guard.rollback();
        self.directory_guard.rollback();
    }
}

pub(super) struct MoveRollbackGuard {
    current_path: PathBuf,
    original_path: PathBuf,
    armed: bool,
}

impl MoveRollbackGuard {
    pub(super) fn new(current_path: PathBuf, original_path: PathBuf) -> Self {
        Self {
            current_path,
            original_path,
            armed: true,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }

    pub(super) fn rollback(&mut self) -> CoreResult<()> {
        if self.armed && self.current_path.exists() && !self.original_path.exists() {
            move_recoverable_file(&self.current_path, &self.original_path)?;
        }
        self.armed = false;
        Ok(())
    }
}

impl Drop for MoveRollbackGuard {
    fn drop(&mut self) {
        if self.armed && self.current_path.exists() && !self.original_path.exists() {
            let _restore_result = move_recoverable_file(&self.current_path, &self.original_path);
        }
    }
}

pub(super) fn move_recoverable_file(current_path: &Path, destination: &Path) -> CoreResult<()> {
    move_checked_file(current_path, destination)
}

pub(super) fn move_checked_file(current_path: &Path, destination: &Path) -> CoreResult<()> {
    if !current_path.try_exists().map_err(map_io_error)? {
        return Err(CoreError::file_not_found(
            current_path.display().to_string(),
        ));
    }
    if destination.try_exists().map_err(map_io_error)? {
        return Err(CoreError::conflict(destination.display().to_string()));
    }
    move_file_no_replace(current_path, destination)
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

pub(super) fn map_io_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::AlreadyExists => CoreError::conflict("path conflict"),
        std::io::ErrorKind::NotFound => CoreError::file_not_found("missing file"),
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}
