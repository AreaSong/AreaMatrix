use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{CoreError, CoreResult, StorageMode};

use super::hash;

const AREA_MATRIX_DIR: &str = ".areamatrix";
const STAGING_DIR: &str = "staging";

pub(super) struct StagingFileGuard {
    path: PathBuf,
    cleanup: StagingCleanup,
    armed: bool,
}

impl StagingFileGuard {
    pub(super) fn create_for_copy(repo: &Path) -> CoreResult<Self> {
        Self::create(repo, StagingCleanup::Delete)
    }

    pub(super) fn create_for_move(repo: &Path, source: PathBuf) -> CoreResult<Self> {
        Self::create(repo, StagingCleanup::RestoreSource(source))
    }

    fn create(repo: &Path, cleanup: StagingCleanup) -> CoreResult<Self> {
        let staging_dir = repo.join(AREA_MATRIX_DIR).join(STAGING_DIR);
        fs::create_dir_all(&staging_dir).map_err(hash::map_io_error)?;
        Ok(Self {
            path: staging_dir.join(format!("import-{}", uuid::Uuid::new_v4())),
            cleanup,
            armed: true,
        })
    }

    pub(super) fn path(&self) -> &Path {
        &self.path
    }

    pub(super) fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for StagingFileGuard {
    fn drop(&mut self) {
        if self.armed {
            match &self.cleanup {
                StagingCleanup::Delete => {
                    // Best-effort cleanup for the internal staging file created by this import.
                    let _cleanup_result = fs::remove_file(&self.path);
                }
                StagingCleanup::RestoreSource(source) => {
                    restore_staged_source_or_keep_recoverable(&self.path, source);
                }
            }
        }
    }
}

enum StagingCleanup {
    Delete,
    RestoreSource(PathBuf),
}

pub(super) enum FinalFileGuard {
    Delete {
        path: PathBuf,
        armed: bool,
    },
    RestoreSource {
        path: PathBuf,
        source: PathBuf,
        armed: bool,
    },
}

impl FinalFileGuard {
    pub(super) fn new(mode: &StorageMode, path: PathBuf, source: PathBuf) -> Self {
        match mode {
            StorageMode::Moved => Self::RestoreSource {
                path,
                source,
                armed: true,
            },
            StorageMode::Copied | StorageMode::Indexed => Self::Delete { path, armed: true },
        }
    }

    pub(super) fn disarm(&mut self) {
        match self {
            Self::Delete { armed, .. } | Self::RestoreSource { armed, .. } => *armed = false,
        }
    }
}

impl Drop for FinalFileGuard {
    fn drop(&mut self) {
        match self {
            Self::Delete { path, armed } if *armed => {
                // This path is created from AreaMatrix staging during the current attempt.
                let _cleanup_result = fs::remove_file(path);
            }
            Self::RestoreSource {
                path,
                source,
                armed,
            } if *armed => {
                restore_staged_source_or_keep_recoverable(path, source);
            }
            _ => {}
        }
    }
}

pub(super) fn move_source_to_staging(source: &Path, staging: &Path) -> CoreResult<()> {
    match fs::rename(source, staging) {
        Ok(()) => Ok(()),
        Err(error) if is_cross_device_error(&error) => copy_then_remove_source(source, staging),
        Err(error) => Err(hash::map_io_error(error)),
    }
}

fn copy_then_remove_source(source: &Path, staging: &Path) -> CoreResult<()> {
    let expected_size = source.metadata().map_err(hash::map_io_error)?.len();
    let copied_size = hash::copy_to_new_file(source, staging)?;
    if copied_size != expected_size {
        let _cleanup_result = fs::remove_file(staging);
        return Err(CoreError::Io);
    }
    if let Err(error) = fs::remove_file(source) {
        let _cleanup_result = fs::remove_file(staging);
        return Err(hash::map_io_error(error));
    }
    Ok(())
}

fn restore_staged_source_or_keep_recoverable(current_path: &Path, source: &Path) {
    if !current_path.exists() {
        return;
    }
    if source.exists() {
        let _cleanup_result = fs::remove_file(current_path);
        return;
    }
    let _restore_result = move_recoverable_file(current_path, source);
}

fn move_recoverable_file(current_path: &Path, source: &Path) -> CoreResult<()> {
    match fs::rename(current_path, source) {
        Ok(()) => Ok(()),
        Err(error) if is_cross_device_error(&error) => {
            copy_then_remove_recoverable(current_path, source)
        }
        Err(error) => Err(hash::map_io_error(error)),
    }
}

fn copy_then_remove_recoverable(current_path: &Path, source: &Path) -> CoreResult<()> {
    let expected_size = current_path.metadata().map_err(hash::map_io_error)?.len();
    let copied_size = hash::copy_to_new_file(current_path, source)?;
    if copied_size != expected_size {
        let _cleanup_result = fs::remove_file(source);
        return Err(CoreError::Io);
    }
    fs::remove_file(current_path).map_err(hash::map_io_error)
}

#[cfg(unix)]
fn is_cross_device_error(error: &std::io::Error) -> bool {
    error.raw_os_error() == Some(18)
}

#[cfg(windows)]
fn is_cross_device_error(error: &std::io::Error) -> bool {
    error.raw_os_error() == Some(17)
}
