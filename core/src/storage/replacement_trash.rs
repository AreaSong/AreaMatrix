use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{CoreError, CoreResult};

use super::{hash, safe_move::move_recoverable_file};

pub(super) struct ReplacementFileGuard {
    original_path: PathBuf,
    archived_path: PathBuf,
    archive_dir: PathBuf,
    rollback_trash_copy_path: Option<PathBuf>,
    trash_copy_confirmed: bool,
    armed: bool,
}

impl ReplacementFileGuard {
    pub(super) fn archive(original_path: &Path, archived_path: &Path) -> CoreResult<Self> {
        if !path_exists(original_path)? {
            return Err(CoreError::file_not_found("missing file"));
        }
        let archive_dir = archived_path
            .parent()
            .ok_or_else(|| CoreError::invalid_path("invalid path"))?
            .to_path_buf();
        fs::create_dir_all(&archive_dir).map_err(hash::map_io_error)?;
        move_recoverable_file(original_path, archived_path)?;
        Ok(Self {
            original_path: original_path.to_path_buf(),
            archived_path: archived_path.to_path_buf(),
            archive_dir,
            rollback_trash_copy_path: None,
            trash_copy_confirmed: false,
            armed: true,
        })
    }

    pub(super) fn ensure_system_trash_copy(&mut self) -> CoreResult<()> {
        if self.trash_copy_confirmed {
            return Ok(());
        }

        let filename = self
            .archived_path
            .file_name()
            .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
        let trash_copy_dir = self
            .archive_dir
            .join(format!("system-trash-copy-{}", uuid::Uuid::new_v4()));
        fs::create_dir(&trash_copy_dir).map_err(hash::map_io_error)?;
        let trash_copy_path = trash_copy_dir.join(filename);
        let copied_size = hash::copy_to_new_file(&self.archived_path, &trash_copy_path)?;
        let expected_size = self
            .archived_path
            .metadata()
            .map_err(hash::map_io_error)?
            .len();
        if copied_size != expected_size {
            let _cleanup_result = fs::remove_file(&trash_copy_path);
            return Err(CoreError::io("io error"));
        }

        let trash_destination = match send_to_system_trash(&trash_copy_path) {
            Ok(path) => path,
            Err(error) => {
                let _cleanup_result = fs::remove_file(&trash_copy_path);
                let _cleanup_result = fs::remove_dir(&trash_copy_dir);
                return Err(error);
            }
        };
        let _cleanup_result = fs::remove_dir(&trash_copy_dir);
        self.rollback_trash_copy_path = trash_destination;
        self.trash_copy_confirmed = true;
        Ok(())
    }

    pub(super) fn disarm(&mut self) {
        let _cleanup_result = fs::remove_file(&self.archived_path);
        let _cleanup_result = fs::remove_dir(&self.archive_dir);
        self.armed = false;
    }

    fn cleanup_rollback_trash_copy(&self) {
        if let Some(trash_copy_path) = &self.rollback_trash_copy_path {
            let _cleanup_result = fs::remove_file(trash_copy_path);
        }
    }
}

impl Drop for ReplacementFileGuard {
    fn drop(&mut self) {
        if self.armed {
            self.cleanup_rollback_trash_copy();
            if self.archived_path.exists() && !self.original_path.exists() {
                let _restore_result =
                    move_recoverable_file(&self.archived_path, &self.original_path);
            }
            let _cleanup_result = fs::remove_dir(&self.archive_dir);
        }
    }
}

pub(crate) fn send_to_system_trash(path: &Path) -> CoreResult<Option<PathBuf>> {
    if std::env::var_os("AREAMATRIX_TEST_FORCE_USER_TRASH").is_some() {
        return move_to_user_trash(path);
    }

    match trash::delete(path) {
        Ok(()) => Ok(None),
        Err(error) => {
            tracing::warn!(
                path = %path.display(),
                error = %error,
                "system trash API failed; falling back to user trash directory"
            );
            move_to_user_trash(path)
        }
    }
}

pub(crate) fn move_to_user_trash(path: &Path) -> CoreResult<Option<PathBuf>> {
    let home = std::env::var_os("HOME").ok_or_else(|| CoreError::io("io error"))?;
    let trash_dir = PathBuf::from(home).join(".Trash");
    fs::create_dir_all(&trash_dir).map_err(hash::map_io_error)?;
    let filename = filename_from_path(path)?;
    let destination = unique_trash_destination(&trash_dir, &filename)?;
    move_recoverable_file(path, &destination)?;
    Ok(Some(destination))
}

fn unique_trash_destination(trash_dir: &Path, filename: &str) -> CoreResult<PathBuf> {
    let candidate = trash_dir.join(filename);
    if !path_exists(&candidate)? {
        return Ok(candidate);
    }

    for index in 1..1000 {
        let candidate = trash_dir.join(numbered_filename(filename, index));
        if !path_exists(&candidate)? {
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

fn filename_from_path(path: &Path) -> CoreResult<String> {
    path.file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| CoreError::invalid_path("invalid path"))
}

fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(hash::map_io_error)
}
