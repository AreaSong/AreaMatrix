use std::path::Path;

use crate::{db, CoreError, CoreResult, FileEntry, MoveToCategoryPreview};

use super::{
    super::{dedup, safe_move::move_recoverable_file},
    detail::{move_detail, preview_for_entry},
    guards::{move_note_sidecar, rollback_filesystem_move, MoveRollbackGuard, NoteSidecarPlan},
    target::{preview_category_directory, resolve_repo_owned_target, CategoryDirectoryGuard},
};

pub(super) fn move_repo_owned_file(
    repo: &Path,
    entry: FileEntry,
    new_category: &str,
) -> CoreResult<FileEntry> {
    move_repo_owned_file_inner(repo, entry, new_category, RepoOwnedMoveMode::WithUndo)
}

pub(super) fn move_repo_owned_file_without_undo(
    repo: &Path,
    entry: FileEntry,
    new_category: &str,
) -> CoreResult<FileEntry> {
    move_repo_owned_file_inner(repo, entry, new_category, RepoOwnedMoveMode::WithoutUndo)
}

pub(super) fn preview_repo_owned_file(
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

pub(super) fn move_indexed_file(
    repo: &Path,
    entry: FileEntry,
    new_category: &str,
) -> CoreResult<FileEntry> {
    db::move_indexed_file_to_category(
        repo,
        entry.id,
        new_category,
        &move_detail(&entry, new_category, &entry.path, &entry.current_name, true),
    )?;
    db::get_active_file_by_id(repo, entry.id)
}

enum RepoOwnedMoveMode {
    WithUndo,
    WithoutUndo,
}

fn move_repo_owned_file_inner(
    repo: &Path,
    entry: FileEntry,
    new_category: &str,
    mode: RepoOwnedMoveMode,
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

    let result = match mode {
        RepoOwnedMoveMode::WithUndo => db::move_repo_owned_file_to_category(
            repo,
            entry.id,
            &target.final_relative_path,
            &target.final_name,
            new_category,
            &detail,
        ),
        RepoOwnedMoveMode::WithoutUndo => db::correct_repo_owned_file_category(
            repo,
            entry.id,
            &target.final_relative_path,
            &target.final_name,
            new_category,
            &detail,
        ),
    };
    if let Err(error) = result {
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
