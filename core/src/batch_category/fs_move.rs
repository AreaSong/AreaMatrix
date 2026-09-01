use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{CoreError, CoreResult};

pub(super) struct CategoryDirectoryGuard {
    path: PathBuf,
    created: bool,
    identity: Option<String>,
    armed: bool,
}

impl CategoryDirectoryGuard {
    pub(super) fn ensure(path: PathBuf) -> CoreResult<Self> {
        match fs::symlink_metadata(&path) {
            Ok(metadata) => {
                if !metadata.file_type().is_symlink() && metadata.is_dir() {
                    return Ok(Self {
                        path,
                        created: false,
                        identity: None,
                        armed: false,
                    });
                }
                return Err(CoreError::conflict("path conflict"));
            }
            Err(error) if error.kind() != std::io::ErrorKind::NotFound => {
                return Err(map_io_error(error))
            }
            Err(_) => {}
        }
        fs::create_dir(&path).map_err(map_io_error)?;
        let identity = crate::batch_journal::directory_identity(&path)
            .map_err(|error| CoreError::io(error.to_string()))?;
        Ok(Self {
            path,
            created: true,
            identity: Some(identity),
            armed: true,
        })
    }

    pub(super) fn created_path(&self) -> Option<&Path> {
        self.created.then_some(self.path.as_path())
    }

    pub(super) fn disarm(&mut self) {
        self.armed = false;
    }

    fn rollback(&mut self) -> CoreResult<()> {
        if self.armed && self.created {
            let metadata = fs::symlink_metadata(&self.path).map_err(map_io_error)?;
            if metadata.file_type().is_symlink() || !metadata.is_dir() {
                return Err(CoreError::conflict("category directory changed"));
            }
            let Some(expected_identity) = self.identity.as_deref() else {
                return Err(CoreError::conflict(
                    "category directory identity unavailable",
                ));
            };
            let actual_identity = crate::batch_journal::directory_identity(&self.path)
                .map_err(|error| CoreError::io(error.to_string()))?;
            if actual_identity != expected_identity {
                return Err(CoreError::conflict("category directory changed"));
            }
            if fs::read_dir(&self.path)
                .map_err(map_io_error)?
                .next()
                .transpose()
                .map_err(map_io_error)?
                .is_some()
            {
                return Err(CoreError::io("category directory is no longer empty"));
            }
            fs::remove_dir(&self.path).map_err(map_io_error)?;
        }
        self.armed = false;
        Ok(())
    }
}

impl Drop for CategoryDirectoryGuard {
    fn drop(&mut self) {
        if let Err(error) = self.rollback() {
            tracing::warn!(error = %error, path = %self.path.display(), "batch category directory rollback deferred");
        }
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
        let note_result = self
            .note_guard
            .as_mut()
            .map(MoveRollbackGuard::rollback)
            .unwrap_or(Ok(()));
        let file_result = self.file_guard.rollback();
        let directory_result = self.directory_guard.rollback();
        if note_result.is_ok() && file_result.is_ok() && directory_result.is_ok() {
            self.file_guard.clear_journal();
        }
        if let Err(error) = note_result {
            tracing::warn!(error = %error, "batch category sidecar rollback deferred");
        }
        if let Err(error) = file_result {
            tracing::warn!(error = %error, "batch category file rollback deferred");
        }
        if let Err(error) = directory_result {
            tracing::warn!(error = %error, "batch category directory rollback deferred");
        }
    }
}

pub(super) struct MoveRollbackGuard {
    current_path: PathBuf,
    original_path: PathBuf,
    armed: bool,
    journal: Option<PathBuf>,
    expected_hash: Option<String>,
}

impl MoveRollbackGuard {
    pub(super) fn new(
        current_path: PathBuf,
        original_path: PathBuf,
        journal: Option<PathBuf>,
        expected_hash: Option<String>,
    ) -> Self {
        Self {
            current_path,
            original_path,
            armed: true,
            journal,
            expected_hash,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
        if let Some(path) = self.journal.as_ref() {
            if let Err(error) = crate::batch_journal::remove(path) {
                tracing::warn!(error = %error, "batch category journal cleanup deferred");
            } else {
                self.journal = None;
            }
        }
    }

    pub(super) fn clear_journal(&mut self) {
        let Some(path) = self.journal.as_ref() else {
            return;
        };
        if let Err(error) = crate::batch_journal::remove(path) {
            tracing::warn!(error = %error, "batch category journal cleanup deferred");
        } else {
            self.journal = None;
        }
    }

    pub(super) fn rollback(&mut self) -> CoreResult<()> {
        if self.armed {
            match (
                safe_regular_file(&self.current_path),
                safe_regular_file(&self.original_path),
            ) {
                (true, false) => match self.expected_hash.as_deref() {
                    Some(hash) => crate::storage::move_recoverable_file_with_hash(
                        &self.current_path,
                        &self.original_path,
                        hash,
                    )?,
                    None => move_recoverable_file(&self.current_path, &self.original_path)?,
                },
                (false, true) => {}
                (false, false) => {
                    return Err(CoreError::io("batch move rollback paths are unavailable"))
                }
                (true, true) => return Err(CoreError::conflict("batch move rollback conflict")),
            }
        }
        self.armed = false;
        Ok(())
    }
}

impl Drop for MoveRollbackGuard {
    fn drop(&mut self) {
        if self.armed && safe_regular_file(&self.current_path) && !path_exists(&self.original_path)
        {
            let result = match self.expected_hash.as_deref() {
                Some(hash) => crate::storage::move_recoverable_file_with_hash(
                    &self.current_path,
                    &self.original_path,
                    hash,
                ),
                None => move_recoverable_file(&self.current_path, &self.original_path),
            };
            if let Err(error) = result {
                tracing::warn!(error = %error, "batch category file rollback deferred");
            }
        }
    }
}

fn safe_regular_file(path: &Path) -> bool {
    fs::symlink_metadata(path)
        .map(|metadata| !metadata.file_type().is_symlink() && metadata.is_file())
        .unwrap_or(false)
}

fn path_exists(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
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
