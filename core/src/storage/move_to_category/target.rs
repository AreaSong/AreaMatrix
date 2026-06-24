use std::path::{Path, PathBuf};

use crate::{CoreError, CoreResult, FileEntry};

use super::{
    super::{dedup, hash},
    paths::{
        ensure_regular_file, filename_from_path, path_exists, relative_repo_path,
        repo_relative_file_path,
    },
};

pub(super) struct RepoOwnedMoveTarget {
    pub(super) current_path: PathBuf,
    pub(super) final_path: PathBuf,
    pub(super) final_relative_path: String,
    pub(super) final_name: String,
}

pub(super) fn resolve_repo_owned_target(
    repo: &Path,
    entry: &FileEntry,
    target_directory: &Path,
) -> CoreResult<RepoOwnedMoveTarget> {
    let current_path = repo_relative_file_path(repo, &entry.path)?;
    ensure_regular_file(&current_path)?;
    let final_path =
        dedup::resolve_rename_path(target_directory, &entry.current_name, &current_path)?;
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

pub(super) struct CategoryDirectoryGuard {
    path: PathBuf,
    created: bool,
    armed: bool,
}

impl CategoryDirectoryGuard {
    pub(super) fn ensure(repo: &Path, category: &str) -> CoreResult<Self> {
        let path = repo.join(category);
        if path_exists(&path)? {
            if path.is_dir() {
                return Ok(Self {
                    path,
                    created: false,
                    armed: false,
                });
            }
            return Err(CoreError::conflict("path conflict"));
        }

        std::fs::create_dir(&path).map_err(hash::map_io_error)?;
        Ok(Self {
            path,
            created: true,
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

impl Drop for CategoryDirectoryGuard {
    fn drop(&mut self) {
        if self.armed && self.created {
            let _cleanup_result = std::fs::remove_dir(&self.path);
        }
    }
}
