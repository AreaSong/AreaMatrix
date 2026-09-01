use std::path::{Path, PathBuf};

use serde_json::{json, Value};

use crate::{
    BatchRenameItemResult, BatchRenameReport, BatchRenameResultStatus, CoreError, CoreResult,
    FileEntry,
};

use super::plan::{error_message, BatchRenamePlan, BatchRenamePlanItem, PlannedRenameChange};

pub(super) fn apply_batch_rename_plan(
    repo: &Path,
    plan: BatchRenamePlan,
) -> CoreResult<BatchRenameReport> {
    let (report, mut fs_renames) = crate::db::with_batch_rename_transaction(repo, |tx| {
        let mut execution = BatchRenameExecution::new(&plan);
        for item in plan.items {
            execution.push(apply_item(repo, tx, item)?);
        }
        if execution.has_successful_write() {
            execution.undo_token = Some(crate::db::insert_batch_rename_undo_action_in_tx(
                tx,
                &execution.undo_items,
            )?);
        }
        let fs_renames = std::mem::take(&mut execution.fs_renames);
        Ok((execution.into_report(), fs_renames))
    })?;
    for fs_rename in &mut fs_renames {
        fs_rename.disarm();
    }
    Ok(report)
}

struct BatchRenameExecution {
    requested_file_count: i64,
    renamed_count: i64,
    display_name_updated_count: i64,
    unchanged_count: i64,
    skipped_count: i64,
    failed_count: i64,
    item_results: Vec<BatchRenameItemResult>,
    updated_files: Vec<FileEntry>,
    undo_items: Vec<crate::db::BatchRenameUndoItem>,
    fs_renames: Vec<AppliedFsRename>,
    undo_token: Option<String>,
}

impl BatchRenameExecution {
    fn new(plan: &BatchRenamePlan) -> Self {
        Self {
            requested_file_count: plan.requested_file_count,
            renamed_count: 0,
            display_name_updated_count: 0,
            unchanged_count: 0,
            skipped_count: 0,
            failed_count: 0,
            item_results: Vec::new(),
            updated_files: Vec::new(),
            undo_items: Vec::new(),
            fs_renames: Vec::new(),
            undo_token: None,
        }
    }

    fn push(&mut self, result: AppliedBatchRenameItem) {
        match result.report.status {
            BatchRenameResultStatus::Renamed => self.renamed_count += 1,
            BatchRenameResultStatus::DisplayNameUpdated => self.display_name_updated_count += 1,
            BatchRenameResultStatus::Unchanged => self.unchanged_count += 1,
            BatchRenameResultStatus::Skipped => self.skipped_count += 1,
            BatchRenameResultStatus::Failed => self.failed_count += 1,
        }
        if let Some(entry) = result.updated_file {
            self.updated_files.push(entry);
        }
        if let Some(undo_item) = result.undo_item {
            self.undo_items.push(undo_item);
        }
        if let Some(fs_rename) = result.fs_rename {
            self.fs_renames.push(fs_rename);
        }
        self.item_results.push(result.report);
    }

    fn has_successful_write(&self) -> bool {
        self.renamed_count > 0 || self.display_name_updated_count > 0
    }

    fn into_report(self) -> BatchRenameReport {
        BatchRenameReport {
            requested_file_count: self.requested_file_count,
            renamed_count: self.renamed_count,
            display_name_updated_count: self.display_name_updated_count,
            unchanged_count: self.unchanged_count,
            skipped_count: self.skipped_count,
            failed_count: self.failed_count,
            item_results: self.item_results,
            updated_files: self.updated_files,
            undo_token: self.undo_token,
        }
    }
}

struct AppliedBatchRenameItem {
    report: BatchRenameItemResult,
    updated_file: Option<FileEntry>,
    undo_item: Option<crate::db::BatchRenameUndoItem>,
    fs_rename: Option<AppliedFsRename>,
}

fn apply_item(
    repo: &Path,
    tx: &mut rusqlite::Transaction<'_>,
    item: BatchRenamePlanItem,
) -> CoreResult<AppliedBatchRenameItem> {
    match item {
        BatchRenamePlanItem::Rename(change) => apply_change(repo, tx, change, false),
        BatchRenamePlanItem::DisplayOnly(change) => apply_change(repo, tx, change, true),
        BatchRenamePlanItem::Unchanged(change) => Ok(unchanged_result(change)),
        BatchRenamePlanItem::Blocked(change) => Ok(AppliedBatchRenameItem {
            report: BatchRenameItemResult {
                file_id: change.file_id,
                original_name: change.original_name,
                final_name: change.new_name,
                final_path: change.target_path,
                status: BatchRenameResultStatus::Failed,
                error: Some(change.reason),
            },
            updated_file: None,
            undo_item: None,
            fs_rename: None,
        }),
    }
}

fn apply_change(
    repo: &Path,
    tx: &mut rusqlite::Transaction<'_>,
    change: PlannedRenameChange,
    index_only: bool,
) -> CoreResult<AppliedBatchRenameItem> {
    let savepoint = tx
        .savepoint()
        .map_err(|error| CoreError::db(error.to_string()))?;
    match try_apply_change(repo, &savepoint, &change, index_only) {
        Ok((updated, undo_item, fs_rename)) => match savepoint.commit() {
            Ok(()) => Ok(successful_change_result(
                change, index_only, updated, undo_item, fs_rename,
            )),
            Err(error) => {
                drop(fs_rename);
                Ok(failed_change_result(
                    change,
                    CoreError::db(error.to_string()),
                ))
            }
        },
        Err(error) => {
            let failure = failed_change_result(change, error);
            savepoint
                .finish()
                .map_err(|error| CoreError::db(error.to_string()))?;
            Ok(failure)
        }
    }
}

fn try_apply_change(
    repo: &Path,
    connection: &rusqlite::Connection,
    change: &PlannedRenameChange,
    index_only: bool,
) -> CoreResult<(
    FileEntry,
    crate::db::BatchRenameUndoItem,
    Option<AppliedFsRename>,
)> {
    let fs_rename = if index_only {
        crate::db::batch_update_rename_indexed_in_tx(
            connection,
            change.entry.id,
            &change.new_name,
            &rename_detail(change, true),
        )?;
        None
    } else {
        let final_path = change
            .final_path
            .as_ref()
            .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
        let file_hash = crate::batch_journal::file_hash(&change.current_path)
            .map_err(|error| CoreError::io(error.to_string()))?;
        let journal_spec = crate::batch_journal::BatchJournal::for_paths(
            repo,
            crate::batch_journal::BatchJournalInput {
                operation: "batch_rename",
                file_id: change.entry.id,
                original: &change.current_path,
                current: final_path,
                original_db_path: &change.entry.path,
                current_db_path: change
                    .final_relative_path
                    .as_deref()
                    .ok_or_else(|| CoreError::invalid_path("invalid path"))?,
                original_name: &change.entry.current_name,
                current_name: &change.new_name,
                original_category: &change.entry.category,
                current_category: &change.entry.category,
                file_hash_sha256: &file_hash,
                sidecar: change
                    .note_sidecar
                    .as_ref()
                    .map(|sidecar| (sidecar.current_path.as_path(), sidecar.final_path.as_path())),
                planned_directory: None,
            },
        )
        .map_err(|e| CoreError::io(e.to_string()))?;
        let sidecar_hash = journal_spec
            .sidecar
            .as_ref()
            .map(|sidecar| sidecar.hash_sha256.clone());
        let journal = crate::batch_journal::create(repo, &journal_spec)
            .map_err(|e| CoreError::io(e.to_string()))?;
        move_checked_file(&change.current_path, final_path)?;
        let mut file_guard = RenameRollbackGuard::new(
            final_path.clone(),
            change.current_path.clone(),
            Some(journal),
            Some(file_hash),
        );
        let mut note_guard = move_note_sidecar(change, &mut file_guard, sidecar_hash)?;
        if let Err(error) = crate::db::batch_update_rename_repo_owned_in_tx(
            connection,
            change.entry.id,
            change
                .final_relative_path
                .as_deref()
                .ok_or_else(|| CoreError::invalid_path("invalid path"))?,
            &change.new_name,
            &rename_detail(change, false),
        ) {
            rollback_filesystem_rename(&mut file_guard, &mut note_guard)?;
            return Err(error);
        }
        Some(AppliedFsRename {
            note_guard,
            file_guard,
        })
    };
    let updated = crate::db::load_batch_rename_active_file(connection, change.entry.id)?;
    let undo_item =
        crate::db::BatchRenameUndoItem::from_file_states(&change.entry, &updated, index_only);
    Ok((updated, undo_item, fs_rename))
}

fn successful_change_result(
    change: PlannedRenameChange,
    index_only: bool,
    updated: FileEntry,
    undo_item: crate::db::BatchRenameUndoItem,
    fs_rename: Option<AppliedFsRename>,
) -> AppliedBatchRenameItem {
    AppliedBatchRenameItem {
        report: BatchRenameItemResult {
            file_id: change.entry.id,
            original_name: Some(change.entry.current_name),
            final_name: Some(updated.current_name.clone()),
            final_path: Some(updated.path.clone()),
            status: if index_only {
                BatchRenameResultStatus::DisplayNameUpdated
            } else {
                BatchRenameResultStatus::Renamed
            },
            error: None,
        },
        updated_file: Some(updated),
        undo_item: Some(undo_item),
        fs_rename,
    }
}

fn failed_change_result(change: PlannedRenameChange, error: CoreError) -> AppliedBatchRenameItem {
    AppliedBatchRenameItem {
        report: BatchRenameItemResult {
            file_id: change.entry.id,
            original_name: Some(change.entry.current_name),
            final_name: Some(change.new_name),
            final_path: change.final_relative_path,
            status: BatchRenameResultStatus::Failed,
            error: Some(error_message(error)),
        },
        updated_file: None,
        undo_item: None,
        fs_rename: None,
    }
}

fn unchanged_result(change: PlannedRenameChange) -> AppliedBatchRenameItem {
    AppliedBatchRenameItem {
        report: BatchRenameItemResult {
            file_id: change.entry.id,
            original_name: Some(change.entry.current_name.clone()),
            final_name: Some(change.entry.current_name),
            final_path: Some(change.entry.path),
            status: BatchRenameResultStatus::Unchanged,
            error: None,
        },
        updated_file: None,
        undo_item: None,
        fs_rename: None,
    }
}

fn rename_detail(change: &PlannedRenameChange, index_only: bool) -> Value {
    json!({
        "kind": "batch_rename",
        "from": change.entry.current_name,
        "to": change.new_name,
        "from_path": change.entry.path,
        "to_path": change.final_relative_path.as_deref().unwrap_or(&change.entry.path),
        "from_name": change.entry.current_name,
        "requested_name": change.new_name,
        "final_name": change.new_name,
        "name_conflict_resolved": false,
        "storage_mode": storage_mode_detail(&change.entry.storage_mode),
        "index_only": index_only,
        "by": "user",
    })
}

struct AppliedFsRename {
    note_guard: Option<RenameRollbackGuard>,
    file_guard: RenameRollbackGuard,
}

impl AppliedFsRename {
    fn disarm(&mut self) {
        if let Some(note_guard) = self.note_guard.as_mut() {
            note_guard.disarm();
        }
        self.file_guard.disarm();
    }
}

impl Drop for AppliedFsRename {
    fn drop(&mut self) {
        let note_result = self
            .note_guard
            .as_mut()
            .map(RenameRollbackGuard::rollback)
            .unwrap_or(Ok(()));
        let file_result = self.file_guard.rollback();
        if note_result.is_ok() && file_result.is_ok() {
            self.file_guard.clear_journal();
        }
        if let Err(error) = note_result {
            tracing::warn!(error = %error, "batch rename sidecar rollback deferred");
        }
        if let Err(error) = file_result {
            tracing::warn!(error = %error, "batch rename file rollback deferred");
        }
    }
}

struct RenameRollbackGuard {
    current_path: PathBuf,
    original_path: PathBuf,
    armed: bool,
    journal: Option<PathBuf>,
    expected_hash: Option<String>,
}

impl RenameRollbackGuard {
    fn new(
        current_path: PathBuf,
        original_path: PathBuf,
        journal: Option<PathBuf>,
        expected_hash: Option<String>,
    ) -> Self {
        Self {
            current_path,
            original_path,
            armed: true,
            journal,
            expected_hash,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
        if let Some(path) = self.journal.as_ref() {
            if let Err(error) = crate::batch_journal::remove(path) {
                tracing::warn!(error = %error, "batch rename journal cleanup deferred");
            } else {
                self.journal = None;
            }
        }
    }

    fn clear_journal(&mut self) {
        let Some(path) = self.journal.as_ref() else {
            return;
        };
        if let Err(error) = crate::batch_journal::remove(path) {
            tracing::warn!(error = %error, "batch rename journal cleanup deferred");
        } else {
            self.journal = None;
        }
    }

    fn rollback(&mut self) -> CoreResult<()> {
        if self.armed {
            match (
                safe_regular_file(&self.current_path),
                safe_regular_file(&self.original_path),
            ) {
                (true, false) => match self.expected_hash.as_deref() {
                    Some(hash) => crate::storage::move_recoverable_file_with_hash(
                        &self.current_path,
                        &self.original_path,
                        hash,
                    )?,
                    None => crate::storage::move_recoverable_file(
                        &self.current_path,
                        &self.original_path,
                    )?,
                },
                (false, true) => {}
                (false, false) => {
                    return Err(CoreError::io("batch rename rollback paths are unavailable"))
                }
                (true, true) => return Err(CoreError::conflict("batch rename rollback conflict")),
            }
        }
        self.armed = false;
        Ok(())
    }
}

impl Drop for RenameRollbackGuard {
    fn drop(&mut self) {
        if self.armed
            && safe_regular_file(&self.current_path)
            && !safe_regular_file(&self.original_path)
        {
            let result = match self.expected_hash.as_deref() {
                Some(hash) => crate::storage::move_recoverable_file_with_hash(
                    &self.current_path,
                    &self.original_path,
                    hash,
                ),
                None => {
                    crate::storage::move_recoverable_file(&self.current_path, &self.original_path)
                }
            };
            if let Err(error) = result {
                tracing::warn!(error = %error, "batch rename rollback deferred");
            }
        }
    }
}

fn safe_regular_file(path: &Path) -> bool {
    std::fs::symlink_metadata(path)
        .map(|metadata| !metadata.file_type().is_symlink() && metadata.is_file())
        .unwrap_or(false)
}

fn move_note_sidecar(
    change: &PlannedRenameChange,
    file_guard: &mut RenameRollbackGuard,
    sidecar_hash: Option<String>,
) -> CoreResult<Option<RenameRollbackGuard>> {
    let Some(sidecar) = &change.note_sidecar else {
        return Ok(None);
    };
    match move_checked_file(&sidecar.current_path, &sidecar.final_path) {
        Ok(()) => Ok(Some(RenameRollbackGuard::new(
            sidecar.final_path.clone(),
            sidecar.current_path.clone(),
            None,
            sidecar_hash,
        ))),
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
    let note_result = note_guard
        .as_mut()
        .map(RenameRollbackGuard::rollback)
        .unwrap_or(Ok(()));
    let file_result = file_guard.rollback();
    match (note_result, file_result) {
        (Ok(()), Ok(())) => {
            file_guard.clear_journal();
            Ok(())
        }
        (Err(error), _) | (_, Err(error)) => Err(error),
    }
}

fn move_checked_file(current_path: &Path, destination: &Path) -> CoreResult<()> {
    if !current_path.try_exists().map_err(map_io_error)? {
        return Err(CoreError::file_not_found(
            current_path.display().to_string(),
        ));
    }
    if destination.try_exists().map_err(map_io_error)? {
        return Err(CoreError::conflict(destination.display().to_string()));
    }
    crate::storage::move_recoverable_file(current_path, destination)
}

fn map_io_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::AlreadyExists => CoreError::conflict("path conflict"),
        std::io::ErrorKind::NotFound => CoreError::file_not_found("missing file"),
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
        _ => CoreError::io("io error"),
    }
}

fn storage_mode_detail(mode: &crate::StorageMode) -> &'static str {
    match mode {
        crate::StorageMode::Moved => "moved",
        crate::StorageMode::Copied => "copied",
        crate::StorageMode::Indexed => "indexed",
    }
}
