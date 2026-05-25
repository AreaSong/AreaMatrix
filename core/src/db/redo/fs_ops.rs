use std::{
    ffi::OsStr,
    fs,
    path::{Component, Path, PathBuf},
};

use crate::{storage, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const REDO_ROLLBACK_RECOVERY_DIR: &str = "redo-rollback-recovery";

pub(super) struct FileMoveRollbackGuard {
    current_path: PathBuf,
    original_path: PathBuf,
    recovery_dir: PathBuf,
    armed: bool,
}

impl FileMoveRollbackGuard {
    fn new(current_path: PathBuf, original_path: PathBuf, recovery_dir: PathBuf) -> Self {
        Self {
            current_path,
            original_path,
            recovery_dir,
            armed: true,
        }
    }

    pub(super) fn disarm(&mut self) {
        self.armed = false;
    }

    pub(super) fn rollback(&mut self) -> CoreResult<()> {
        if !self.armed {
            return Ok(());
        }

        let current_exists = path_exists(&self.current_path)?;
        let original_exists = path_exists(&self.original_path)?;
        match (current_exists, original_exists) {
            (true, false) => {
                if let Err(error) = move_file_no_replace(&self.current_path, &self.original_path) {
                    return Err(self.quarantine_current_path(error));
                }
                self.armed = false;
                Ok(())
            }
            (false, true) => {
                self.armed = false;
                Ok(())
            }
            (true, true) => {
                let error = CoreError::io(format!(
                    "redo rollback destination occupied: {}",
                    self.original_path.display()
                ));
                Err(self.quarantine_current_path(error))
            }
            (false, false) => Err(CoreError::io(format!(
                "redo rollback source missing: {}",
                self.current_path.display()
            ))),
        }
    }

    fn quarantine_current_path(&mut self, error: CoreError) -> CoreError {
        match self.recovery_path().and_then(|recovery_path| {
            move_file_no_replace(&self.current_path, &recovery_path)?;
            Ok(recovery_path)
        }) {
            Ok(recovery_path) => {
                self.current_path = recovery_path.clone();
                self.armed = false;
                CoreError::io(format!(
                    "{error}; recovered redo file at {}",
                    recovery_path.display()
                ))
            }
            Err(recovery_error) => CoreError::io(format!("{error}; {recovery_error}")),
        }
    }

    fn recovery_path(&self) -> CoreResult<PathBuf> {
        fs::create_dir_all(&self.recovery_dir).map_err(map_io_error)?;
        let filename = self
            .current_path
            .file_name()
            .and_then(|value| value.to_str())
            .filter(|value| !value.is_empty())
            .unwrap_or("redo-file");
        Ok(self
            .recovery_dir
            .join(format!("{}-{filename}", uuid::Uuid::new_v4())))
    }
}

pub(super) fn rollback_guards_or_error(
    guards: &mut [FileMoveRollbackGuard],
    original_error: CoreError,
) -> CoreError {
    match rollback_guards(guards) {
        Ok(()) => original_error,
        Err(error) => error,
    }
}

pub(super) fn rollback_guards(guards: &mut [FileMoveRollbackGuard]) -> CoreResult<()> {
    let mut first_error = None;
    for guard in guards {
        if let Err(error) = guard.rollback() {
            if first_error.is_none() {
                first_error = Some(error);
            }
        }
    }
    if let Some(error) = first_error {
        return Err(redo_rollback_error(error));
    }
    Ok(())
}

fn redo_rollback_error(error: CoreError) -> CoreError {
    CoreError::io(format!("redo rollback failed: {error}"))
}

impl Drop for FileMoveRollbackGuard {
    fn drop(&mut self) {
        // Drop cannot report recovery failures; explicit redo error paths call
        // `rollback` and propagate the result before this best-effort retry.
        let _rollback_result = self.rollback();
    }
}

pub(super) fn repo_relative_path(repo: &Path, relative_path: &str) -> CoreResult<PathBuf> {
    let relative = Path::new(relative_path);
    validate_repo_relative_path(relative)?;
    Ok(repo.join(relative))
}

pub(super) fn move_checked_path(
    repo: &Path,
    current_path: &Path,
    destination: &Path,
) -> CoreResult<FileMoveRollbackGuard> {
    if !current_path.try_exists().map_err(map_io_error)? {
        return Err(CoreError::file_not_found(
            current_path.display().to_string(),
        ));
    }
    ensure_regular_file(current_path)?;
    if destination.try_exists().map_err(map_io_error)? {
        return Err(CoreError::conflict(destination.display().to_string()));
    }
    move_file_no_replace(current_path, destination)?;
    Ok(FileMoveRollbackGuard::new(
        destination.to_path_buf(),
        current_path.to_path_buf(),
        redo_rollback_recovery_dir(repo),
    ))
}

pub(super) fn move_path_to_user_trash(
    repo: &Path,
    path: &Path,
) -> CoreResult<FileMoveRollbackGuard> {
    ensure_regular_file(path)?;
    let trash_path = storage::move_to_user_trash(path)?
        .ok_or_else(|| CoreError::io("trash path unavailable"))?;
    Ok(FileMoveRollbackGuard::new(
        trash_path,
        path.to_path_buf(),
        redo_rollback_recovery_dir(repo),
    ))
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

fn redo_rollback_recovery_dir(repo: &Path) -> PathBuf {
    repo.join(AREA_MATRIX_DIR)
        .join("staging")
        .join(REDO_ROLLBACK_RECOVERY_DIR)
}

fn ensure_regular_file(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(map_io_error)?;
    if metadata.is_file() {
        Ok(())
    } else {
        Err(CoreError::conflict("File changed after undo"))
    }
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
