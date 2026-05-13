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
        Self::create(repo, "copy-import", StagingCleanup::Delete)
    }

    pub(super) fn create_for_move(repo: &Path, source: PathBuf) -> CoreResult<Self> {
        Self::create(repo, "move-import", StagingCleanup::RestoreSource(source))
    }

    fn create(repo: &Path, prefix: &str, cleanup: StagingCleanup) -> CoreResult<Self> {
        let staging_dir = repo.join(AREA_MATRIX_DIR).join(STAGING_DIR);
        fs::create_dir_all(&staging_dir).map_err(hash::map_io_error)?;
        Ok(Self {
            path: staging_dir.join(format!("{}-{}", prefix, uuid::Uuid::new_v4())),
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
    move_file_no_replace(source, staging)
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

pub(super) fn move_recoverable_file(current_path: &Path, source: &Path) -> CoreResult<()> {
    move_file_no_replace(current_path, source)
}

fn move_file_no_replace(current_path: &Path, destination: &Path) -> CoreResult<()> {
    match fs::hard_link(current_path, destination) {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            return Err(CoreError::conflict("path conflict"));
        }
        Err(_) => copy_to_new_destination(current_path, destination)?,
    }

    match fs::remove_file(current_path) {
        Ok(()) => Ok(()),
        Err(error) => {
            let _cleanup_result = fs::remove_file(destination);
            Err(hash::map_io_error(error))
        }
    }
}

fn copy_to_new_destination(current_path: &Path, destination: &Path) -> CoreResult<()> {
    let expected_size = current_path.metadata().map_err(hash::map_io_error)?.len();
    let copied_size = hash::copy_to_new_file(current_path, destination)?;
    if copied_size != expected_size {
        let _cleanup_result = fs::remove_file(destination);
        return Err(CoreError::io("io error"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;

    #[test]
    fn resolve_name_conflict_safe_move_refuses_existing_destination_without_overwrite() {
        let dir = tempfile::tempdir().expect("create safe-move tempdir");
        let source = dir.path().join("source.pdf");
        let destination = dir.path().join("target.pdf");
        fs::write(&source, b"new content").expect("write source file");
        fs::write(&destination, b"existing content").expect("write existing destination");

        let result = move_recoverable_file(&source, &destination);

        assert!(matches!(result, Err(CoreError::Conflict { .. })));
        assert_eq!(
            fs::read(&source).expect("source remains readable after refused move"),
            b"new content"
        );
        assert_eq!(
            fs::read(&destination).expect("destination remains unmodified"),
            b"existing content"
        );
    }
}
