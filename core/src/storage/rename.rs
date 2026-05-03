use std::{
    fs,
    path::{Path, PathBuf},
};

use serde_json::json;

use crate::{db, overview, CoreError, CoreResult, FileEntry, StorageMode};

use super::{dedup, hash, safe_move::move_recoverable_file, validate};

const AREA_MATRIX_DIR: &str = ".areamatrix";

pub(crate) fn rename_file(
    repo_path: String,
    file_id: i64,
    new_name: String,
) -> CoreResult<FileEntry> {
    let repo = validate_repo_path(&repo_path)?;
    db::ensure_initialized(&repo)?;
    validate::filename(&new_name)?;

    let entry = db::get_active_file_by_id(&repo, file_id)?;
    match entry.storage_mode {
        StorageMode::Moved | StorageMode::Copied => rename_repo_owned_file(&repo, entry, &new_name),
        StorageMode::Indexed => rename_indexed_file(&repo, entry, &new_name),
    }
}

fn rename_repo_owned_file(repo: &Path, entry: FileEntry, new_name: &str) -> CoreResult<FileEntry> {
    if !dedup::is_repo_owned(&entry) {
        return Err(CoreError::invalid_path("invalid path"));
    }
    let current_path = repo_relative_file_path(repo, &entry.path)?;
    ensure_regular_file(&current_path)?;
    let target_directory = current_path
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    let final_path = dedup::resolve_rename_path(target_directory, new_name, &current_path)?;
    if final_path == current_path {
        return Ok(entry);
    }

    let final_name = filename_from_path(&final_path)?;
    let final_relative_path = relative_repo_path(repo, &final_path)?;
    let detail = rename_detail(&entry, new_name, &final_relative_path, &final_name, false);
    let note_sidecar = NoteSidecarPlan::from_rename(repo, entry.id, &current_path, &final_path)?;
    move_recoverable_file(&current_path, &final_path)?;
    let mut file_guard = RenameRollbackGuard::new(final_path.clone(), current_path.clone());
    let mut note_guard = move_note_sidecar(note_sidecar, &mut file_guard)?;

    if let Err(error) =
        db::rename_active_file(repo, entry.id, &final_relative_path, &final_name, &detail)
    {
        rollback_filesystem_rename(&mut file_guard, &mut note_guard)?;
        return Err(error);
    }
    let updated = db::get_active_file_by_id(repo, entry.id)?;
    if let Err(error) = overview::regenerate_for_node(repo, &updated.category) {
        rollback_repo_owned_rename(repo, &entry, &mut file_guard, note_guard.as_mut(), &detail)?;
        return Err(error);
    }
    disarm_rename_guards(&mut file_guard, note_guard.as_mut());
    Ok(updated)
}

fn rename_indexed_file(repo: &Path, entry: FileEntry, new_name: &str) -> CoreResult<FileEntry> {
    if entry.current_name == new_name {
        return Ok(entry);
    }

    db::rename_indexed_display_name(
        repo,
        entry.id,
        new_name,
        &rename_detail(&entry, new_name, &entry.path, new_name, true),
    )?;
    db::get_active_file_by_id(repo, entry.id)
}

fn rename_detail(
    entry: &FileEntry,
    requested_name: &str,
    final_path: &str,
    final_name: &str,
    index_only: bool,
) -> serde_json::Value {
    json!({
        "from": entry.current_name,
        "to": final_name,
        "from_path": entry.path,
        "to_path": final_path,
        "from_name": entry.current_name,
        "requested_name": requested_name,
        "final_name": final_name,
        "name_conflict_resolved": requested_name != final_name,
        "storage_mode": storage_mode_detail(&entry.storage_mode),
        "index_only": index_only,
        "by": "user",
    })
}

fn rollback_repo_owned_rename(
    repo: &Path,
    entry: &FileEntry,
    file_guard: &mut RenameRollbackGuard,
    note_guard: Option<&mut RenameRollbackGuard>,
    detail: &serde_json::Value,
) -> CoreResult<()> {
    let mut note_guard = note_guard;
    rollback_borrowed_filesystem_rename(file_guard, &mut note_guard)?;
    match db::rollback_renamed_active_file(repo, entry.id, &entry.path, &entry.current_name, detail)
    {
        Ok(()) => Ok(()),
        Err(error) => {
            // Keep FS and DB aligned when metadata rollback itself fails after
            // the physical file has already been restored.
            restore_borrowed_committed_filesystem_state(file_guard, &mut note_guard)?;
            Err(error)
        }
    }
}

fn move_note_sidecar(
    note_sidecar: Option<NoteSidecarPlan>,
    file_guard: &mut RenameRollbackGuard,
) -> CoreResult<Option<RenameRollbackGuard>> {
    let Some(note_sidecar) = note_sidecar else {
        return Ok(None);
    };

    match note_sidecar.move_to_final() {
        Ok(guard) => Ok(Some(guard)),
        Err(error) => {
            file_guard.rollback()?;
            Err(error)
        }
    }
}

fn rollback_filesystem_rename(
    file_guard: &mut RenameRollbackGuard,
    note_guard: &mut Option<RenameRollbackGuard>,
) -> CoreResult<()> {
    if let Some(note_guard) = note_guard.as_mut() {
        note_guard.rollback()?;
    }
    file_guard.rollback()
}

fn rollback_borrowed_filesystem_rename(
    file_guard: &mut RenameRollbackGuard,
    note_guard: &mut Option<&mut RenameRollbackGuard>,
) -> CoreResult<()> {
    if let Some(note_guard) = note_guard.as_mut() {
        note_guard.rollback()?;
    }
    file_guard.rollback()
}

fn restore_borrowed_committed_filesystem_state(
    file_guard: &mut RenameRollbackGuard,
    note_guard: &mut Option<&mut RenameRollbackGuard>,
) -> CoreResult<()> {
    file_guard.restore_committed_state()?;
    if let Some(note_guard) = note_guard.as_mut() {
        note_guard.restore_committed_state()?;
    }
    Ok(())
}

fn disarm_rename_guards(
    file_guard: &mut RenameRollbackGuard,
    note_guard: Option<&mut RenameRollbackGuard>,
) {
    file_guard.disarm();
    if let Some(note_guard) = note_guard {
        note_guard.disarm();
    }
}

fn storage_mode_detail(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(PathBuf::from(repo_path))
}

fn repo_relative_file_path(repo: &Path, relative_path: &str) -> CoreResult<PathBuf> {
    let relative = Path::new(relative_path);
    validate_repo_relative_path(relative)?;
    Ok(repo.join(relative))
}

fn validate_repo_relative_path(path: &Path) -> CoreResult<()> {
    if path.is_absolute() || path.as_os_str().is_empty() {
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

fn ensure_regular_file(path: &Path) -> CoreResult<()> {
    let metadata = path.metadata().map_err(hash::map_io_error)?;
    if metadata.is_file() {
        Ok(())
    } else {
        Err(CoreError::file_not_found("missing file"))
    }
}

fn filename_from_path(path: &Path) -> CoreResult<String> {
    path.file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| CoreError::invalid_path("invalid path"))
}

fn relative_repo_path(repo: &Path, path: &Path) -> CoreResult<String> {
    path.strip_prefix(repo)
        .map_err(|error| CoreError::invalid_path(error.to_string()))
        .map(|relative| relative.to_string_lossy().into_owned())
}

struct NoteSidecarPlan {
    current_path: PathBuf,
    final_path: PathBuf,
}

impl NoteSidecarPlan {
    fn from_rename(
        repo: &Path,
        file_id: i64,
        current_file: &Path,
        final_file: &Path,
    ) -> CoreResult<Option<Self>> {
        let Some(note_content) = db::read_note_content(repo, file_id)? else {
            return Ok(None);
        };
        let current_path = sidecar_path_for_file(current_file)?;
        let final_path = sidecar_path_for_file(final_file)?;
        let sidecar_content = fs::read_to_string(&current_path).map_err(hash::map_io_error)?;
        if sidecar_content != note_content {
            return Err(CoreError::db("database error"));
        }
        if final_path.try_exists().map_err(hash::map_io_error)? {
            return Err(CoreError::conflict("path conflict"));
        }
        Ok(Some(Self {
            current_path,
            final_path,
        }))
    }

    fn move_to_final(self) -> CoreResult<RenameRollbackGuard> {
        move_recoverable_file(&self.current_path, &self.final_path)?;
        Ok(RenameRollbackGuard::new(self.final_path, self.current_path))
    }
}

fn sidecar_path_for_file(file_path: &Path) -> CoreResult<PathBuf> {
    let parent = file_path
        .parent()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    let file_name = file_path
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    Ok(parent.join(format!("{file_name}.md")))
}

struct RenameRollbackGuard {
    current_path: PathBuf,
    original_path: PathBuf,
    armed: bool,
}

impl RenameRollbackGuard {
    fn new(current_path: PathBuf, original_path: PathBuf) -> Self {
        Self {
            current_path,
            original_path,
            armed: true,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }

    fn rollback(&mut self) -> CoreResult<()> {
        if self.armed && self.current_path.exists() && !self.original_path.exists() {
            move_recoverable_file(&self.current_path, &self.original_path)?;
        }
        self.armed = false;
        Ok(())
    }

    fn restore_committed_state(&mut self) -> CoreResult<()> {
        if self.original_path.exists() && !self.current_path.exists() {
            move_recoverable_file(&self.original_path, &self.current_path)?;
        }
        Ok(())
    }
}

impl Drop for RenameRollbackGuard {
    fn drop(&mut self) {
        if self.armed && self.current_path.exists() && !self.original_path.exists() {
            let _restore_result = move_recoverable_file(&self.current_path, &self.original_path);
        }
    }
}
