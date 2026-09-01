use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{CoreError, CoreResult};

use super::{
    hash,
    safe_move::{
        directory_identity, ensure_directory_chain, ensure_safe_file_path, move_recoverable_file,
        move_recoverable_file_checked,
    },
};

pub(super) struct ReplacementFileGuard {
    original_path: PathBuf,
    archived_path: PathBuf,
    archive_dir: PathBuf,
    archive_dir_identity: String,
    rollback_trash_copy_path: Option<PathBuf>,
    rollback_trash_parent_identity: Option<String>,
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
        ensure_directory_chain(&archive_dir, true)?;
        let archive_dir_identity = directory_identity(&archive_dir)?;
        move_recoverable_file(original_path, archived_path)?;
        Ok(Self {
            original_path: original_path.to_path_buf(),
            archived_path: archived_path.to_path_buf(),
            archive_dir,
            archive_dir_identity,
            rollback_trash_copy_path: None,
            rollback_trash_parent_identity: None,
            trash_copy_confirmed: false,
            armed: true,
        })
    }

    pub(super) fn ensure_system_trash_copy(&mut self) -> CoreResult<bool> {
        if self.trash_copy_confirmed {
            return Ok(self.rollback_trash_copy_path.is_some());
        }

        let filename = self
            .archived_path
            .file_name()
            .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
        let trash_copy_dir = self
            .archive_dir
            .join(format!("system-trash-copy-{}", uuid::Uuid::new_v4()));
        let trash_copy_parent = trash_copy_dir
            .parent()
            .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
        ensure_directory_chain(trash_copy_parent, true)?;
        fs::create_dir(&trash_copy_dir).map_err(hash::map_io_error)?;
        ensure_directory_chain(&trash_copy_dir, false)?;
        let trash_copy_path = trash_copy_dir.join(filename);
        ensure_safe_file_path(&self.archived_path)?;
        let archived_metadata =
            fs::symlink_metadata(&self.archived_path).map_err(hash::map_io_error)?;
        if archived_metadata.file_type().is_symlink() || !archived_metadata.is_file() {
            return Err(CoreError::conflict("invalid archived file"));
        }
        let copied_size = hash::copy_to_new_file(&self.archived_path, &trash_copy_path)?;
        let expected_size = archived_metadata.len();
        if copied_size != expected_size {
            let _cleanup_result = fs::remove_file(&trash_copy_path);
            return Err(CoreError::io("io error"));
        }

        // Replacement rollback requires a path that Core can move back. Native
        // Trash APIs often return success without exposing that path, so this
        // guard deliberately uses the recoverable user-trash fallback.
        let trash_destination = match move_to_user_trash(&trash_copy_path) {
            Ok(Some(path)) => path,
            Ok(None) => return Err(CoreError::io("recoverable Trash path unavailable")),
            Err(error) => {
                if directory_identity(&trash_copy_dir).ok().is_some() {
                    let _cleanup_result = fs::remove_file(&trash_copy_path);
                    let _cleanup_result = fs::remove_dir(&trash_copy_dir);
                }
                return Err(error);
            }
        };
        let _cleanup_result = fs::remove_dir(&trash_copy_dir);
        let trash_parent = trash_destination
            .parent()
            .ok_or_else(|| CoreError::invalid_path("invalid Trash path"))?;
        let trash_parent_identity = directory_identity(trash_parent)?;
        self.rollback_trash_copy_path = Some(trash_destination);
        self.rollback_trash_parent_identity = Some(trash_parent_identity);
        self.trash_copy_confirmed = true;
        Ok(true)
    }

    pub(super) fn disarm(&mut self) {
        if directory_identity(&self.archive_dir).ok().as_deref()
            == Some(self.archive_dir_identity.as_str())
        {
            let _cleanup_result = fs::remove_file(&self.archived_path);
            let _cleanup_result = fs::remove_dir(&self.archive_dir);
        }
        self.armed = false;
    }

    fn cleanup_rollback_trash_copy(&self) {
        if let Some(trash_copy_path) = &self.rollback_trash_copy_path {
            let parent = trash_copy_path.parent().unwrap_or(trash_copy_path);
            if self.rollback_trash_parent_identity.as_deref()
                == directory_identity(parent).ok().as_deref()
            {
                let _cleanup_result = fs::remove_file(trash_copy_path);
            }
        }
    }
}

impl Drop for ReplacementFileGuard {
    fn drop(&mut self) {
        if self.armed {
            self.cleanup_rollback_trash_copy();
            if path_exists_no_follow(&self.archived_path)
                && !path_exists_no_follow(&self.original_path)
            {
                let _restore_result =
                    move_recoverable_file(&self.archived_path, &self.original_path);
            }
            if directory_identity(&self.archive_dir).ok().as_deref()
                == Some(self.archive_dir_identity.as_str())
            {
                let _cleanup_result = fs::remove_dir(&self.archive_dir);
            }
        }
    }
}

pub(crate) fn send_to_system_trash(path: &Path) -> CoreResult<Option<PathBuf>> {
    ensure_safe_file_path(path)?;
    // Every caller records a restore/undo path. A platform Trash adapter that
    // returns only `Ok(())` would make a successful delete irreversible, so the
    // path-returning user Trash is the single safe implementation here.
    move_to_user_trash(path)
}

pub(crate) fn move_to_user_trash(path: &Path) -> CoreResult<Option<PathBuf>> {
    move_to_user_trash_inner(path, None)
}

pub(crate) fn move_to_user_trash_checked(
    path: &Path,
    expected_identity: &str,
    expected_size: i64,
    expected_modified_nanos: u128,
    expected_hash: &str,
) -> CoreResult<Option<PathBuf>> {
    ensure_safe_file_path(path)?;
    move_to_user_trash_inner(
        path,
        Some((
            expected_identity,
            expected_size,
            expected_modified_nanos,
            expected_hash,
        )),
    )
}

fn move_to_user_trash_inner(
    path: &Path,
    expected: Option<(&str, i64, u128, &str)>,
) -> CoreResult<Option<PathBuf>> {
    let home = std::env::var_os("HOME").ok_or_else(|| CoreError::io("io error"))?;
    let trash_dir = PathBuf::from(home).join(".Trash");
    ensure_directory_chain(&trash_dir, true)?;
    let filename = filename_from_path(path)?;
    let destination = unique_trash_destination(&trash_dir, &filename)?;
    if let Some((identity, size, modified_nanos, hash)) = expected {
        move_recoverable_file_checked(path, &destination, identity, size, modified_nanos, hash)?;
    } else {
        move_recoverable_file(path, &destination)?;
    }
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
    match fs::symlink_metadata(path) {
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(hash::map_io_error(error)),
    }
}

fn path_exists_no_follow(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
}
