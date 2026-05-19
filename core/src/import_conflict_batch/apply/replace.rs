use std::path::{Path, PathBuf};

use crate::{db, storage, CoreError, CoreResult, FileEntry, ImportConflictBatchResultStatus};

use super::{
    deleted_detail, ensure_parent_dir, import_detail, required_final_name, required_final_path,
    required_staging, successful_write_result, AppliedImportConflictItem, ImportConflictRollback,
};
use crate::import_conflict_batch::{
    path, strategy_detail, PlannedImportConflict, AREA_MATRIX_DIR, TRASH_PENDING_DIR,
};

pub(super) fn apply_replace(
    repo: &Path,
    item: &PlannedImportConflict,
    session_status: &str,
) -> CoreResult<AppliedImportConflictItem> {
    let context = ReplaceContext::new(repo, item)?;
    let mut archive = ExistingArchive::archive(repo, context.existing)?;
    storage::move_recoverable_file(&context.staging_path, &context.final_absolute_path)?;
    let result = resolve_replacement(repo, item, &context, archive.path());
    match result {
        Ok(()) => finish_replace(item, &context, &mut archive, session_status),
        Err(error) => Err(rollback_failed_replace(context, archive, error)),
    }
}

struct ReplaceContext<'a> {
    repo: &'a Path,
    staging: &'a FileEntry,
    existing: &'a FileEntry,
    final_path: &'a str,
    final_name: &'a str,
    staging_path: PathBuf,
    final_absolute_path: PathBuf,
}

impl<'a> ReplaceContext<'a> {
    fn new(repo: &'a Path, item: &'a PlannedImportConflict) -> CoreResult<Self> {
        let staging = required_staging(item)?;
        let existing = item
            .existing
            .as_ref()
            .ok_or_else(|| CoreError::conflict("missing replace target"))?;
        let final_path = required_final_path(item)?;
        let final_name = required_final_name(item)?;
        let staging_path = path::staging_file_path(repo, &staging.path)?;
        let final_absolute_path = path::repo_relative_file_path(repo, final_path)?;
        path::ensure_existing_replace_target(&final_absolute_path)?;
        Ok(Self {
            repo,
            staging,
            existing,
            final_path,
            final_name,
            staging_path,
            final_absolute_path,
        })
    }
}

fn resolve_replacement(
    repo: &Path,
    item: &PlannedImportConflict,
    context: &ReplaceContext<'_>,
    archive_path: &Path,
) -> CoreResult<()> {
    let archived_relative_path = path::relative_repo_path(repo, archive_path)?;
    let import_detail = import_detail(
        item,
        context.staging,
        context.final_path,
        strategy_detail(&item.strategy),
        Some(context.existing),
    );
    let deleted_detail = deleted_detail(context.existing, &archived_relative_path);
    db::resolve_import_conflict_item(
        repo,
        db::ImportConflictApplyItem {
            conflict: &item.row,
            final_path: Some(context.final_path),
            final_name: Some(context.final_name),
            change_detail: Some(&import_detail),
            replaced: Some(db::ImportConflictReplacement {
                archived_path: &archived_relative_path,
                deleted_detail: &deleted_detail,
            }),
            decision: strategy_detail(&item.strategy),
        },
    )
}

fn finish_replace(
    item: &PlannedImportConflict,
    context: &ReplaceContext<'_>,
    archive: &mut ExistingArchive,
    session_status: &str,
) -> CoreResult<AppliedImportConflictItem> {
    let archived_path = path::relative_repo_path(context.repo, archive.path())?;
    archive.disarm();
    let mut applied = successful_write_result(
        item,
        ImportConflictBatchResultStatus::Replaced,
        context.staging.id,
        context.final_path,
        vec![context.existing.id, context.staging.id],
        vec!["deleted".to_owned(), "imported".to_owned()],
    );
    applied.rollback = Some(ImportConflictRollback::Replace {
        row: item.row.clone(),
        final_path: context.final_path.to_owned(),
        archived_path,
        staging_path: context.staging.path.clone(),
        staging_name: context.staging.current_name.clone(),
        session_status: session_status.to_owned(),
    });
    Ok(applied)
}

fn rollback_failed_replace(
    context: ReplaceContext<'_>,
    archive: ExistingArchive,
    error: CoreError,
) -> CoreError {
    let rollback = rollback_replace(&context.final_absolute_path, &context.staging_path, archive);
    rollback.err().unwrap_or(error)
}

struct ExistingArchive {
    path: PathBuf,
    original_path: PathBuf,
    armed: bool,
}

impl ExistingArchive {
    fn archive(repo: &Path, existing: &FileEntry) -> CoreResult<Self> {
        let original_path = path::repo_relative_file_path(repo, &existing.path)?;
        let archive_path = repo
            .join(AREA_MATRIX_DIR)
            .join(TRASH_PENDING_DIR)
            .join(format!("import-conflict-{}", uuid::Uuid::new_v4()))
            .join(&existing.current_name);
        ensure_parent_dir(&archive_path)?;
        storage::move_recoverable_file(&original_path, &archive_path)?;
        Ok(Self {
            path: archive_path,
            original_path,
            armed: true,
        })
    }

    fn path(&self) -> &Path {
        &self.path
    }

    fn disarm(&mut self) {
        self.armed = false;
    }

    fn rollback(mut self) -> CoreResult<()> {
        self.restore()?;
        self.armed = false;
        Ok(())
    }

    fn restore(&self) -> CoreResult<()> {
        if self.armed && self.path.exists() && !self.original_path.exists() {
            storage::move_recoverable_file(&self.path, &self.original_path)?;
        }
        Ok(())
    }
}

impl Drop for ExistingArchive {
    fn drop(&mut self) {
        let _restore_result = self.restore();
    }
}

fn rollback_replace(
    final_path: &Path,
    staging_path: &Path,
    archive: ExistingArchive,
) -> CoreResult<()> {
    let staging_restore = restore_staging_after_replace_failure(final_path, staging_path);
    let archive_restore = archive.rollback().err();
    match (staging_restore, archive_restore) {
        (Some(error), _) | (_, Some(error)) => Err(error),
        (None, None) => Ok(()),
    }
}

fn restore_staging_after_replace_failure(
    final_path: &Path,
    staging_path: &Path,
) -> Option<CoreError> {
    if final_path.exists() && !staging_path.exists() {
        return storage::move_recoverable_file(final_path, staging_path).err();
    }
    None
}
