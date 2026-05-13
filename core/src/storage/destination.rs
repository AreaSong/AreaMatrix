use std::{
    fs,
    path::{Path, PathBuf},
};

use serde_json::json;

use crate::{db, CoreError, CoreResult, FileEntry, StorageMode};

use super::{dedup, hash, replacement_trash::ReplacementFileGuard};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const TRASH_PENDING_DIR: &str = "trash-pending";
const SYSTEM_TRASH_SCHEME: &str = "system-trash://";

pub(super) struct ImportDestinationPlan {
    directory_guard: CreatedDirectoryGuard,
    pub(super) final_path: PathBuf,
    pub(super) final_relative_path: String,
    pub(super) final_name: String,
    pub(super) category: String,
    replacement: Option<ReplacementPlan>,
}

impl ImportDestinationPlan {
    pub(super) fn prepare(
        repo: &Path,
        target_relative_dir: &str,
        target_category: &str,
        target_filename: &str,
        duplicate_resolution: dedup::DuplicateResolution,
    ) -> CoreResult<Self> {
        match duplicate_resolution {
            dedup::DuplicateResolution::Overwrite { existing, reason } => {
                Self::prepare_replacement(
                    repo,
                    target_relative_dir,
                    target_category,
                    target_filename,
                    existing,
                    reason,
                )
            }
            resolution => Self::prepare_new_file(
                repo,
                target_relative_dir,
                target_category,
                target_filename,
                resolution,
            ),
        }
    }

    pub(super) fn replacement(&self) -> Option<&ReplacementPlan> {
        self.replacement.as_ref()
    }

    pub(super) fn archive_replacement(&self) -> CoreResult<Option<ReplacementFileGuard>> {
        let Some(replacement) = &self.replacement else {
            return Ok(None);
        };
        let Some(archived_path) = &replacement.archived_path else {
            return Ok(None);
        };
        ReplacementFileGuard::archive(&self.final_path, archived_path).map(Some)
    }

    pub(super) fn disarm(mut self) {
        self.directory_guard.disarm();
    }

    fn prepare_new_file(
        repo: &Path,
        target_relative_dir: &str,
        target_category: &str,
        target_filename: &str,
        duplicate_resolution: dedup::DuplicateResolution,
    ) -> CoreResult<Self> {
        let directory_guard = CreatedDirectoryGuard::ensure(repo, target_relative_dir)?;
        let final_path = dedup::resolve_final_path(
            directory_guard.path(),
            target_filename,
            duplicate_resolution,
        )?;
        let final_name = filename_from_path(&final_path)?;

        Ok(Self {
            final_relative_path: relative_repo_path(repo, &final_path)?,
            directory_guard,
            final_path,
            final_name,
            category: target_category.to_owned(),
            replacement: None,
        })
    }

    fn prepare_replacement(
        repo: &Path,
        target_relative_dir: &str,
        target_category: &str,
        target_filename: &str,
        existing: FileEntry,
        reason: dedup::ReplacementReason,
    ) -> CoreResult<Self> {
        if dedup::is_repo_owned(&existing) {
            Self::prepare_repo_owned_replacement(repo, existing, reason)
        } else {
            Self::prepare_metadata_replacement(
                repo,
                target_relative_dir,
                target_category,
                target_filename,
                existing,
                reason,
            )
        }
    }

    fn prepare_repo_owned_replacement(
        repo: &Path,
        existing: FileEntry,
        reason: dedup::ReplacementReason,
    ) -> CoreResult<Self> {
        let relative_dir = parent_relative_dir(&existing.path)?;
        let directory_guard = CreatedDirectoryGuard::ensure(repo, &relative_dir)?;
        let final_path = repo_relative_file_path(repo, &existing.path)?;
        if !path_exists(&final_path)? {
            return Err(CoreError::file_not_found("missing file"));
        }
        let final_name = filename_from_path(&final_path)?;
        let (archived_relative_path, archived_path) = replacement_archive_path(repo, &final_name);

        Ok(Self {
            final_relative_path: existing.path.clone(),
            final_path,
            final_name,
            category: existing.category.clone(),
            directory_guard,
            replacement: Some(ReplacementPlan {
                existing,
                reason,
                archived_relative_path,
                archived_path: Some(archived_path),
            }),
        })
    }

    fn prepare_metadata_replacement(
        repo: &Path,
        target_relative_dir: &str,
        target_category: &str,
        target_filename: &str,
        existing: FileEntry,
        reason: dedup::ReplacementReason,
    ) -> CoreResult<Self> {
        let directory_guard = CreatedDirectoryGuard::ensure(repo, target_relative_dir)?;
        let final_path = dedup::resolve_final_path(
            directory_guard.path(),
            target_filename,
            dedup::DuplicateResolution::NoDuplicate,
        )?;
        let final_name = filename_from_path(&final_path)?;
        let archived_relative_path = replacement_trash_marker(&existing.current_name);

        Ok(Self {
            final_relative_path: relative_repo_path(repo, &final_path)?,
            final_path,
            final_name,
            category: target_category.to_owned(),
            directory_guard,
            replacement: Some(ReplacementPlan {
                existing,
                reason,
                archived_relative_path,
                archived_path: None,
            }),
        })
    }
}

pub(super) struct ReplacementPlan {
    existing: FileEntry,
    reason: dedup::ReplacementReason,
    archived_relative_path: String,
    archived_path: Option<PathBuf>,
}

impl ReplacementPlan {
    pub(super) fn prepare_for_existing(repo: &Path, existing: FileEntry) -> CoreResult<Self> {
        if !dedup::is_repo_owned(&existing) {
            return Ok(Self::metadata_only(
                existing,
                dedup::ReplacementReason::DuplicateHash,
            ));
        }

        let original_path = repo_relative_file_path(repo, &existing.path)?;
        if !path_exists(&original_path)? {
            return Err(CoreError::file_not_found("missing file"));
        }

        let (archived_relative_path, archived_path) =
            replacement_archive_path(repo, &existing.current_name);
        Ok(Self {
            reason: dedup::ReplacementReason::DuplicateHash,
            archived_relative_path,
            archived_path: Some(archived_path),
            existing,
        })
    }

    pub(super) fn metadata_only(existing: FileEntry, reason: dedup::ReplacementReason) -> Self {
        Self {
            reason,
            archived_relative_path: replacement_trash_marker(&existing.current_name),
            archived_path: None,
            existing,
        }
    }

    pub(super) fn db_row(&self) -> db::ReplacementImportRow {
        db::ReplacementImportRow {
            existing_id: self.existing.id,
            archived_path: self.archived_relative_path.clone(),
        }
    }

    pub(super) fn archive_existing_file(
        &self,
        repo: &Path,
    ) -> CoreResult<Option<ReplacementFileGuard>> {
        let Some(archived_path) = &self.archived_path else {
            return Ok(None);
        };
        let original_path = repo_relative_file_path(repo, &self.existing.path)?;
        ReplacementFileGuard::archive(&original_path, archived_path).map(Some)
    }

    pub(super) fn deleted_change_detail(&self) -> serde_json::Value {
        json!({
            "hard": false,
            "by": "user",
            "reason": self.reason_detail(),
            "from_path": self.existing.path,
            "archived_path": self.archived_relative_path,
            "trash_location": "system",
            "trashed": true,
            "storage_mode": storage_mode_detail(&self.existing.storage_mode),
            "safe_replace": true,
        })
    }

    pub(super) fn replaced_file_id(&self) -> i64 {
        self.existing.id
    }

    pub(super) fn replaced_path(&self) -> &str {
        &self.existing.path
    }

    pub(super) fn replaced_updated_at(&self) -> i64 {
        self.existing.updated_at
    }

    pub(super) fn reason_detail(&self) -> &'static str {
        match self.reason {
            dedup::ReplacementReason::DuplicateHash => "duplicate_overwrite",
            dedup::ReplacementReason::NameConflict => "name_conflict_replace",
        }
    }
}

struct CreatedDirectoryGuard {
    final_path: PathBuf,
    created: Vec<PathBuf>,
    armed: bool,
}

impl CreatedDirectoryGuard {
    fn ensure(repo: &Path, relative_dir: &str) -> CoreResult<Self> {
        let mut current = repo.to_path_buf();
        let mut created = Vec::new();
        for component in Path::new(relative_dir).components() {
            let std::path::Component::Normal(part) = component else {
                return Err(CoreError::invalid_path("invalid path"));
            };
            current.push(part);
            if path_exists(&current)? {
                if current.is_dir() {
                    continue;
                }
                return Err(CoreError::invalid_path("invalid path"));
            }
            fs::create_dir(&current).map_err(hash::map_io_error)?;
            created.push(current.clone());
        }

        Ok(Self {
            final_path: current,
            created,
            armed: true,
        })
    }

    fn path(&self) -> &Path {
        &self.final_path
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for CreatedDirectoryGuard {
    fn drop(&mut self) {
        if self.armed {
            for directory in self.created.iter().rev() {
                // Only empty directories created by this import are removed.
                let _cleanup_result = fs::remove_dir(directory);
            }
        }
    }
}

fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|error| CoreError::invalid_path(error.to_string()))
        .map(|relative| relative.to_string_lossy().into_owned())
}

fn repo_relative_file_path(repo: &Path, relative_path: &str) -> CoreResult<PathBuf> {
    let relative = Path::new(relative_path);
    validate_repo_relative_path(relative, false)?;
    Ok(repo.join(relative))
}

fn parent_relative_dir(relative_path: &str) -> CoreResult<String> {
    let relative = Path::new(relative_path);
    validate_repo_relative_path(relative, false)?;
    let Some(parent) = relative.parent() else {
        return Ok(String::new());
    };
    if parent.as_os_str().is_empty() {
        return Ok(String::new());
    }
    validate_repo_relative_path(parent, true)?;
    Ok(parent.to_string_lossy().into_owned())
}

fn validate_repo_relative_path(path: &Path, allow_empty: bool) -> CoreResult<()> {
    if path.is_absolute() || (!allow_empty && path.as_os_str().is_empty()) {
        return Err(CoreError::invalid_path("invalid path"));
    }
    for component in path.components() {
        let std::path::Component::Normal(part) = component else {
            return Err(CoreError::invalid_path("invalid path"));
        };
        if part == std::ffi::OsStr::new(AREA_MATRIX_DIR) {
            return Err(CoreError::invalid_path("invalid path"));
        }
    }
    Ok(())
}

fn filename_from_path(path: &Path) -> CoreResult<String> {
    path.file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| CoreError::invalid_path("invalid path"))
}

fn replacement_archive_path(repo: &Path, filename: &str) -> (String, PathBuf) {
    let replacement_id = format!("replace-{}", uuid::Uuid::new_v4());
    let marker = format!("{SYSTEM_TRASH_SCHEME}{replacement_id}/{filename}");
    let archive_path = repo
        .join(AREA_MATRIX_DIR)
        .join(TRASH_PENDING_DIR)
        .join(replacement_id)
        .join(filename);
    (marker, archive_path)
}

fn replacement_trash_marker(filename: &str) -> String {
    format!(
        "{SYSTEM_TRASH_SCHEME}metadata-only-{}/{}",
        uuid::Uuid::new_v4(),
        filename
    )
}

fn storage_mode_detail(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(hash::map_io_error)
}
