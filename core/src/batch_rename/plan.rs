use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use crate::{
    BatchRenameConflict, BatchRenamePreviewStatus, BatchRenameRule, CoreError, CoreResult,
    FileEntry, StorageMode,
};

use super::{
    plan_name::{generate_name, sequence_width, validate_filename},
    plan_path::{
        ensure_file_and_parent_writable, ensure_indexed_source_present, ensure_regular_file,
        map_io_error, path_exists, relative_repo_path, repo_relative_file_path,
        sidecar_path_for_file,
    },
    token,
};

pub(super) use super::plan_types::{
    BatchRenamePlan, BatchRenamePlanItem, BlockedRenameChange, PlannedRenameChange,
    PlannedRenameSidecar,
};

pub(super) fn build_batch_rename_plan(
    repo: &Path,
    file_ids: &[i64],
    rule: BatchRenameRule,
) -> CoreResult<BatchRenamePlan> {
    let sequence_width = sequence_width(file_ids.len(), &rule);
    let mut items = Vec::with_capacity(file_ids.len());
    for (index, file_id) in file_ids.iter().enumerate() {
        items.push(plan_item(repo, *file_id, index, sequence_width, &rule)?);
    }
    let conflicts = mark_batch_target_conflicts(&mut items);
    let preview_token = token::preview_token(file_ids, &rule, &items);
    Ok(BatchRenamePlan {
        requested_file_count: file_ids.len() as i64,
        rule,
        preview_token,
        items,
        conflicts,
    })
}

fn plan_item(
    repo: &Path,
    file_id: i64,
    index: usize,
    sequence_width: usize,
    rule: &BatchRenameRule,
) -> CoreResult<BatchRenamePlanItem> {
    let entry = match db_entry(repo, file_id)? {
        Some(entry) => entry,
        None => return Ok(blocked_missing(file_id, "File is no longer active")),
    };
    let new_name = match generate_name(repo, &entry, index, sequence_width, rule) {
        Ok(new_name) => new_name,
        Err(error) => return Ok(blocked_from_entry(entry, None, error)),
    };
    if let Err(error) = validate_filename(&new_name) {
        return Ok(blocked_from_entry(entry, Some(new_name), error));
    }
    if matches!(entry.storage_mode, StorageMode::Indexed) {
        return plan_indexed_display_name(entry, new_name);
    }
    plan_repo_owned_rename(repo, entry, new_name)
}

fn plan_repo_owned_rename(
    repo: &Path,
    entry: FileEntry,
    new_name: String,
) -> CoreResult<BatchRenamePlanItem> {
    let current_path = match repo_relative_file_path(repo, &entry.path) {
        Ok(path) => path,
        Err(error) => return Ok(blocked_from_entry(entry, Some(new_name), error)),
    };
    if let Err(error) = ensure_regular_file(&current_path) {
        return Ok(blocked_from_entry(entry, Some(new_name), error));
    }
    if let Err(error) = ensure_file_and_parent_writable(&current_path) {
        return Ok(blocked_from_entry(entry, Some(new_name), error));
    }
    let Some(parent) = current_path.parent() else {
        return Ok(blocked_from_entry(
            entry,
            Some(new_name),
            CoreError::invalid_path("invalid path"),
        ));
    };
    let final_path = parent.join(&new_name);
    let final_relative_path = match relative_repo_path(repo, &final_path) {
        Ok(path) => path,
        Err(error) => return Ok(blocked_from_entry(entry, Some(new_name), error)),
    };
    if final_path == current_path {
        return Ok(BatchRenamePlanItem::Unchanged(planned_repo_owned(
            entry,
            current_path,
            final_path,
            final_relative_path,
            new_name,
            None,
        )));
    }
    if let Err(error) = ensure_target_available(repo, entry.id, &final_path, &final_relative_path) {
        return Ok(blocked_from_entry_with_target(
            entry,
            Some(new_name),
            Some(final_relative_path),
            error,
        ));
    }
    let note_sidecar = match plan_note_sidecar(repo, entry.id, &current_path, &final_path) {
        Ok(sidecar) => sidecar,
        Err(error) => {
            return Ok(blocked_from_entry_with_target(
                entry,
                Some(new_name),
                Some(final_relative_path),
                error,
            ))
        }
    };
    Ok(BatchRenamePlanItem::Rename(planned_repo_owned(
        entry,
        current_path,
        final_path,
        final_relative_path,
        new_name,
        note_sidecar,
    )))
}

fn plan_indexed_display_name(
    entry: FileEntry,
    new_name: String,
) -> CoreResult<BatchRenamePlanItem> {
    let current_path = PathBuf::from(&entry.path);
    if let Err(error) = ensure_indexed_source_present(&current_path) {
        return Ok(blocked_from_entry(entry, Some(new_name), error));
    }
    if new_name == entry.current_name {
        return Ok(BatchRenamePlanItem::Unchanged(planned_indexed(
            entry,
            current_path,
            new_name,
        )));
    }
    Ok(BatchRenamePlanItem::DisplayOnly(planned_indexed(
        entry,
        current_path,
        new_name,
    )))
}

fn planned_repo_owned(
    entry: FileEntry,
    current_path: PathBuf,
    final_path: PathBuf,
    final_relative_path: String,
    new_name: String,
    note_sidecar: Option<PlannedRenameSidecar>,
) -> PlannedRenameChange {
    PlannedRenameChange {
        entry,
        current_path,
        final_path: Some(final_path),
        final_relative_path: Some(final_relative_path),
        new_name,
        index_only: false,
        will_rename_file: true,
        note_sidecar,
    }
}

fn planned_indexed(
    entry: FileEntry,
    current_path: PathBuf,
    new_name: String,
) -> PlannedRenameChange {
    PlannedRenameChange {
        entry,
        current_path,
        final_path: None,
        final_relative_path: None,
        new_name,
        index_only: true,
        will_rename_file: false,
        note_sidecar: None,
    }
}

fn mark_batch_target_conflicts(items: &mut [BatchRenamePlanItem]) -> Vec<BatchRenameConflict> {
    let mut seen: BTreeMap<String, i64> = BTreeMap::new();
    let mut conflicts = Vec::new();
    let mut blocked = Vec::new();
    for (index, item) in items.iter().enumerate() {
        let Some((file_id, target_path)) = item.repo_owned_target() else {
            continue;
        };
        if let Some(conflicting_file_id) = seen.insert(target_path.to_owned(), file_id) {
            blocked.push((index, conflicting_file_id, target_path.to_owned()));
            conflicts.push(BatchRenameConflict {
                file_id,
                conflicting_file_id: Some(conflicting_file_id),
                conflict_path: Some(target_path.to_owned()),
                reason: "duplicate generated name".to_owned(),
            });
        }
    }
    for (index, conflicting_file_id, target_path) in blocked {
        if let Some(item) = items.get_mut(index) {
            item.block_as_name_conflict(Some(conflicting_file_id), target_path);
        }
    }
    conflicts
}

impl BatchRenamePlanItem {
    fn repo_owned_target(&self) -> Option<(i64, &str)> {
        match self {
            Self::Rename(change) => Some((change.entry.id, change.final_relative_path.as_deref()?)),
            _ => None,
        }
    }

    fn block_as_name_conflict(&mut self, conflicting_file_id: Option<i64>, target_path: String) {
        let Self::Rename(change) = self else {
            return;
        };
        let reason = match conflicting_file_id {
            Some(file_id) => format!("duplicate generated name with file:{file_id}"),
            None => "duplicate generated name".to_owned(),
        };
        *self = Self::Blocked(BlockedRenameChange {
            file_id: change.entry.id,
            current_path: Some(change.entry.path.clone()),
            original_name: Some(change.entry.current_name.clone()),
            new_name: Some(change.new_name.clone()),
            target_path: Some(target_path),
            storage_mode: Some(change.entry.storage_mode.clone()),
            status: BatchRenamePreviewStatus::NameConflict,
            reason,
        });
    }
}

fn ensure_target_available(
    repo: &Path,
    file_id: i64,
    final_path: &Path,
    final_relative_path: &str,
) -> CoreResult<()> {
    if path_exists(final_path)? {
        return Err(CoreError::conflict(final_relative_path.to_owned()));
    }
    if let Some(existing) = crate::db::find_active_file_by_path(repo, final_relative_path)? {
        if existing.id != file_id {
            return Err(CoreError::conflict(final_relative_path.to_owned()));
        }
    }
    Ok(())
}

fn plan_note_sidecar(
    repo: &Path,
    file_id: i64,
    current_file: &Path,
    final_file: &Path,
) -> CoreResult<Option<PlannedRenameSidecar>> {
    let Some(note_content) = crate::db::read_note_content(repo, file_id)? else {
        return Ok(None);
    };
    let current_path = sidecar_path_for_file(current_file)?;
    let final_path = sidecar_path_for_file(final_file)?;
    let sidecar_content = fs::read_to_string(&current_path).map_err(map_io_error)?;
    if sidecar_content != note_content {
        return Err(CoreError::db("database error"));
    }
    if final_path.try_exists().map_err(map_io_error)? {
        return Err(CoreError::conflict("path conflict"));
    }
    Ok(Some(PlannedRenameSidecar {
        current_path,
        final_path,
    }))
}

fn blocked_missing(file_id: i64, reason: &str) -> BatchRenamePlanItem {
    BatchRenamePlanItem::Blocked(BlockedRenameChange {
        file_id,
        current_path: None,
        original_name: None,
        new_name: None,
        target_path: None,
        storage_mode: None,
        status: BatchRenamePreviewStatus::Missing,
        reason: reason.to_owned(),
    })
}

fn blocked_from_entry(
    entry: FileEntry,
    new_name: Option<String>,
    error: CoreError,
) -> BatchRenamePlanItem {
    blocked_from_entry_with_target(entry, new_name, None, error)
}

fn blocked_from_entry_with_target(
    entry: FileEntry,
    new_name: Option<String>,
    target_path: Option<String>,
    error: CoreError,
) -> BatchRenamePlanItem {
    BatchRenamePlanItem::Blocked(BlockedRenameChange {
        file_id: entry.id,
        current_path: Some(entry.path),
        original_name: Some(entry.current_name),
        new_name,
        target_path,
        storage_mode: Some(entry.storage_mode),
        status: preview_status_from_error(&error),
        reason: error_message(error),
    })
}

fn preview_status_from_error(error: &CoreError) -> BatchRenamePreviewStatus {
    match error {
        CoreError::Conflict { .. } => BatchRenamePreviewStatus::NameConflict,
        CoreError::FileNotFound { .. } => BatchRenamePreviewStatus::Missing,
        CoreError::PermissionDenied { .. } => BatchRenamePreviewStatus::ReadOnly,
        CoreError::Io { .. } => BatchRenamePreviewStatus::ExternalChange,
        CoreError::InvalidPath { .. } | CoreError::Db { .. } => BatchRenamePreviewStatus::Error,
        _ => BatchRenamePreviewStatus::Error,
    }
}

pub(super) fn error_message(error: CoreError) -> String {
    match error {
        CoreError::Conflict { path } => format!("Conflict: {path}"),
        CoreError::FileNotFound { path } => format!("FileNotFound: {path}"),
        CoreError::PermissionDenied { path } => format!("PermissionDenied: {path}"),
        CoreError::Io { message } => format!("Io: {message}"),
        CoreError::Db { message } => format!("Db: {message}"),
        CoreError::InvalidPath { path } => format!("InvalidPath: {path}"),
        other => other.to_string(),
    }
}

fn db_entry(repo: &Path, file_id: i64) -> CoreResult<Option<FileEntry>> {
    match crate::db::get_active_file_by_id(repo, file_id) {
        Ok(entry) => Ok(Some(entry)),
        Err(CoreError::FileNotFound { .. }) => Ok(None),
        Err(error) => Err(error),
    }
}
