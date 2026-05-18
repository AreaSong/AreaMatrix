use std::{
    fs,
    path::{Path, PathBuf},
};

use serde_json::{json, Value};

use crate::{classify, db, CoreError, CoreResult, FileEntry, MoveToCategoryPreview, StorageMode};

use super::{dedup, hash, safe_move::move_recoverable_file};

const AREA_MATRIX_DIR: &str = ".areamatrix";

pub(crate) fn preview_move_to_category(
    repo_path: String,
    file_id: i64,
    new_category: String,
) -> CoreResult<MoveToCategoryPreview> {
    let repo = validate_repo_path(&repo_path)?;
    db::ensure_initialized(&repo)?;
    classify::ensure_category_exists(&repo, &new_category)?;

    let entry = db::get_active_file_by_id(&repo, file_id)?;
    if entry.category == new_category {
        return preview_same_category_entry(&repo, &entry, &new_category);
    }

    match entry.storage_mode {
        StorageMode::Moved | StorageMode::Copied => {
            preview_repo_owned_file(&repo, &entry, &new_category)
        }
        StorageMode::Indexed => Ok(preview_for_entry(
            &entry,
            &new_category,
            &entry.path,
            &entry.current_name,
            true,
            false,
        )),
    }
}

pub(crate) fn move_to_category(
    repo_path: String,
    file_id: i64,
    new_category: String,
) -> CoreResult<FileEntry> {
    let repo = validate_repo_path(&repo_path)?;
    db::ensure_initialized(&repo)?;
    classify::ensure_category_exists(&repo, &new_category)?;

    let entry = db::get_active_file_by_id(&repo, file_id)?;
    if entry.category == new_category {
        return validate_same_category_entry(&repo, entry);
    }

    match entry.storage_mode {
        StorageMode::Moved | StorageMode::Copied => {
            move_repo_owned_file(&repo, entry, &new_category)
        }
        StorageMode::Indexed => move_indexed_file(&repo, entry, &new_category),
    }
}

pub(crate) fn correct_repo_owned_file_category(
    repo_path: String,
    file_id: i64,
    new_category: String,
) -> CoreResult<FileEntry> {
    let repo = validate_repo_path(&repo_path)?;
    db::ensure_initialized(&repo)?;
    classify::ensure_category_exists(&repo, &new_category)?;

    let entry = db::get_active_file_by_id(&repo, file_id)?;
    if entry.category == new_category {
        return validate_same_category_entry(&repo, entry);
    }

    match entry.storage_mode {
        StorageMode::Moved | StorageMode::Copied => {
            move_repo_owned_file_without_undo(&repo, entry, &new_category)
        }
        StorageMode::Indexed => Err(CoreError::invalid_path("invalid path")),
    }
}

fn move_repo_owned_file(
    repo: &Path,
    entry: FileEntry,
    new_category: &str,
) -> CoreResult<FileEntry> {
    if !dedup::is_repo_owned(&entry) {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let mut target_directory = CategoryDirectoryGuard::ensure(repo, new_category)?;
    let target = resolve_repo_owned_target(repo, &entry, target_directory.path())?;
    let detail = move_detail(
        &entry,
        new_category,
        &target.final_relative_path,
        &target.final_name,
        false,
    );
    let note_sidecar =
        NoteSidecarPlan::from_move(repo, entry.id, &target.current_path, &target.final_path)?;

    move_recoverable_file(&target.current_path, &target.final_path)?;
    let mut file_guard = MoveRollbackGuard::new(target.final_path.clone(), target.current_path);
    let mut note_guard = move_note_sidecar(note_sidecar, &mut file_guard)?;

    if let Err(error) = db::move_repo_owned_file_to_category(
        repo,
        entry.id,
        &target.final_relative_path,
        &target.final_name,
        new_category,
        &detail,
    ) {
        rollback_filesystem_move(&mut file_guard, &mut note_guard)?;
        return Err(error);
    }

    file_guard.disarm();
    if let Some(note_guard) = note_guard.as_mut() {
        note_guard.disarm();
    }
    target_directory.disarm();
    db::get_active_file_by_id(repo, entry.id)
}

fn move_repo_owned_file_without_undo(
    repo: &Path,
    entry: FileEntry,
    new_category: &str,
) -> CoreResult<FileEntry> {
    if !dedup::is_repo_owned(&entry) {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let mut target_directory = CategoryDirectoryGuard::ensure(repo, new_category)?;
    let target = resolve_repo_owned_target(repo, &entry, target_directory.path())?;
    let detail = move_detail(
        &entry,
        new_category,
        &target.final_relative_path,
        &target.final_name,
        false,
    );
    let note_sidecar =
        NoteSidecarPlan::from_move(repo, entry.id, &target.current_path, &target.final_path)?;

    move_recoverable_file(&target.current_path, &target.final_path)?;
    let mut file_guard = MoveRollbackGuard::new(target.final_path.clone(), target.current_path);
    let mut note_guard = move_note_sidecar(note_sidecar, &mut file_guard)?;

    if let Err(error) = db::correct_repo_owned_file_category(
        repo,
        entry.id,
        &target.final_relative_path,
        &target.final_name,
        new_category,
        &detail,
    ) {
        rollback_filesystem_move(&mut file_guard, &mut note_guard)?;
        return Err(error);
    }

    file_guard.disarm();
    if let Some(note_guard) = note_guard.as_mut() {
        note_guard.disarm();
    }
    target_directory.disarm();
    db::get_active_file_by_id(repo, entry.id)
}

fn preview_repo_owned_file(
    repo: &Path,
    entry: &FileEntry,
    new_category: &str,
) -> CoreResult<MoveToCategoryPreview> {
    if !dedup::is_repo_owned(entry) {
        return Err(CoreError::invalid_path("invalid path"));
    }

    let target_directory = preview_category_directory(repo, new_category)?;
    let target = resolve_repo_owned_target(repo, entry, &target_directory)?;
    NoteSidecarPlan::from_move(repo, entry.id, &target.current_path, &target.final_path)?;

    Ok(preview_for_entry(
        entry,
        new_category,
        &target.final_relative_path,
        &target.final_name,
        false,
        target.final_path != target.current_path,
    ))
}

fn move_indexed_file(repo: &Path, entry: FileEntry, new_category: &str) -> CoreResult<FileEntry> {
    db::move_indexed_file_to_category(
        repo,
        entry.id,
        new_category,
        &move_detail(&entry, new_category, &entry.path, &entry.current_name, true),
    )?;
    db::get_active_file_by_id(repo, entry.id)
}

fn preview_same_category_entry(
    repo: &Path,
    entry: &FileEntry,
    new_category: &str,
) -> CoreResult<MoveToCategoryPreview> {
    if matches!(entry.storage_mode, StorageMode::Moved | StorageMode::Copied) {
        if !dedup::is_repo_owned(entry) {
            return Err(CoreError::invalid_path("invalid path"));
        }
        ensure_regular_file(&repo_relative_file_path(repo, &entry.path)?)?;
    }

    Ok(preview_for_entry(
        entry,
        new_category,
        &entry.path,
        &entry.current_name,
        entry.storage_mode == StorageMode::Indexed,
        false,
    ))
}

fn validate_same_category_entry(repo: &Path, entry: FileEntry) -> CoreResult<FileEntry> {
    if matches!(entry.storage_mode, StorageMode::Moved | StorageMode::Copied) {
        if !dedup::is_repo_owned(&entry) {
            return Err(CoreError::invalid_path("invalid path"));
        }
        ensure_regular_file(&repo_relative_file_path(repo, &entry.path)?)?;
    }
    Ok(entry)
}

fn preview_for_entry(
    entry: &FileEntry,
    new_category: &str,
    target_path: &str,
    target_name: &str,
    index_only: bool,
    will_move_file: bool,
) -> MoveToCategoryPreview {
    MoveToCategoryPreview {
        file_id: entry.id,
        from_category: entry.category.clone(),
        to_category: new_category.to_owned(),
        current_path: entry.path.clone(),
        target_path: target_path.to_owned(),
        target_name: target_name.to_owned(),
        storage_mode: entry.storage_mode.clone(),
        index_only,
        name_conflict_resolved: target_name != entry.current_name,
        will_move_file,
    }
}

fn move_detail(
    entry: &FileEntry,
    new_category: &str,
    final_path: &str,
    final_name: &str,
    index_only: bool,
) -> Value {
    let mut detail = json!({
        "from_category": entry.category,
        "to_category": new_category,
        "from_path": entry.path,
        "to_path": final_path,
        "final_name": final_name,
        "name_conflict_resolved": final_name != entry.current_name,
        "storage_mode": storage_mode_detail(&entry.storage_mode),
        "index_only": index_only,
        "by": "user",
    });

    if final_name != entry.current_name {
        detail["renamed_to"] = json!(final_name);
    }
    detail
}

fn move_note_sidecar(
    note_sidecar: Option<NoteSidecarPlan>,
    file_guard: &mut MoveRollbackGuard,
) -> CoreResult<Option<MoveRollbackGuard>> {
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

fn rollback_filesystem_move(
    file_guard: &mut MoveRollbackGuard,
    note_guard: &mut Option<MoveRollbackGuard>,
) -> CoreResult<()> {
    if let Some(note_guard) = note_guard.as_mut() {
        note_guard.rollback()?;
    }
    file_guard.rollback()
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

struct RepoOwnedMoveTarget {
    current_path: PathBuf,
    final_path: PathBuf,
    final_relative_path: String,
    final_name: String,
}

fn resolve_repo_owned_target(
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

fn preview_category_directory(repo: &Path, category: &str) -> CoreResult<PathBuf> {
    let path = repo.join(category);
    if path_exists(&path)? {
        if path.is_dir() {
            return Ok(path);
        }
        return Err(CoreError::conflict("path conflict"));
    }
    Ok(path)
}

struct CategoryDirectoryGuard {
    path: PathBuf,
    created: bool,
    armed: bool,
}

impl CategoryDirectoryGuard {
    fn ensure(repo: &Path, category: &str) -> CoreResult<Self> {
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

        fs::create_dir(&path).map_err(hash::map_io_error)?;
        Ok(Self {
            path,
            created: true,
            armed: true,
        })
    }

    fn path(&self) -> &Path {
        &self.path
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for CategoryDirectoryGuard {
    fn drop(&mut self) {
        if self.armed && self.created {
            let _cleanup_result = fs::remove_dir(&self.path);
        }
    }
}

struct NoteSidecarPlan {
    current_path: PathBuf,
    final_path: PathBuf,
}

impl NoteSidecarPlan {
    fn from_move(
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

    fn move_to_final(self) -> CoreResult<MoveRollbackGuard> {
        move_recoverable_file(&self.current_path, &self.final_path)?;
        Ok(MoveRollbackGuard::new(self.final_path, self.current_path))
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

struct MoveRollbackGuard {
    current_path: PathBuf,
    original_path: PathBuf,
    armed: bool,
}

impl MoveRollbackGuard {
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
}

impl Drop for MoveRollbackGuard {
    fn drop(&mut self) {
        if self.armed && self.current_path.exists() && !self.original_path.exists() {
            let _restore_result = move_recoverable_file(&self.current_path, &self.original_path);
        }
    }
}

fn path_exists(path: &Path) -> CoreResult<bool> {
    path.try_exists().map_err(hash::map_io_error)
}
