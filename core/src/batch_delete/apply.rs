use std::{
    fs,
    path::{Path, PathBuf},
};

use serde_json::{json, Value};

use crate::{
    db, storage, BatchDeleteItemResult, BatchDeleteReport, BatchDeleteResultStatus, CoreError,
    CoreResult, FileEntry, FileOrigin, StorageMode,
};

use super::plan::{BatchDeletePlan, BatchDeletePlanItem, PlannedBatchDeleteItem};

const ARCHIVES_DIR: &str = "archives";

pub(super) fn apply_batch_delete_plan(
    repo: &Path,
    plan: BatchDeletePlan,
) -> CoreResult<BatchDeleteReport> {
    let mut execution = BatchDeleteExecution::new(&plan);
    for item in plan.items {
        execution.push(apply_batch_delete_item(repo, item));
    }
    execution.insert_batch_undo(repo)?;
    Ok(execution.into_report())
}

struct BatchDeleteExecution {
    report: BatchDeleteReport,
    undo_items: Vec<db::BatchDeleteUndoItem>,
    trash_rollbacks: Vec<TrashRollbackItem>,
    index_rollbacks: Vec<IndexRollbackItem>,
}

impl BatchDeleteExecution {
    fn new(plan: &BatchDeletePlan) -> Self {
        Self {
            report: BatchDeleteReport {
                requested_file_count: plan.requested_file_count,
                delete_mode: plan.delete_mode.clone(),
                moved_to_trash_count: 0,
                removed_from_index_count: 0,
                skipped_count: 0,
                failed_count: 0,
                item_results: Vec::new(),
                affected_file_ids: Vec::new(),
                undo_token: None,
            },
            undo_items: Vec::new(),
            trash_rollbacks: Vec::new(),
            index_rollbacks: Vec::new(),
        }
    }

    fn push(&mut self, applied: AppliedBatchDeleteItem) {
        match applied.result.status {
            BatchDeleteResultStatus::MovedToTrash => self.report.moved_to_trash_count += 1,
            BatchDeleteResultStatus::RemovedFromIndex => self.report.removed_from_index_count += 1,
            BatchDeleteResultStatus::Skipped => self.report.skipped_count += 1,
            BatchDeleteResultStatus::Failed => self.report.failed_count += 1,
        }
        if applied.refresh {
            self.report.affected_file_ids.push(applied.result.file_id);
        }
        if let Some(undo_item) = applied.undo_item {
            self.undo_items.push(undo_item);
        }
        if let Some(rollback_item) = applied.trash_rollback {
            self.trash_rollbacks.push(rollback_item);
        }
        if let Some(rollback_item) = applied.index_rollback {
            self.index_rollbacks.push(rollback_item);
        }
        self.report.item_results.push(applied.result);
    }

    fn insert_batch_undo(&mut self, repo: &Path) -> CoreResult<()> {
        if self.undo_items.is_empty() {
            return Ok(());
        }
        match db::insert_batch_delete_undo_action(repo, &self.undo_items) {
            Ok(token) => self.report.undo_token = Some(token),
            Err(error) => {
                let rollback_error = self.rollback_after_undo_failure(repo).err();
                return Err(rollback_error.unwrap_or(error));
            }
        }
        Ok(())
    }

    fn rollback_after_undo_failure(&mut self, repo: &Path) -> CoreResult<()> {
        let mut first_error = None;
        while let Some(item) = self.trash_rollbacks.pop() {
            if let Err(error) = item.rollback(repo) {
                if first_error.is_none() {
                    first_error = Some(error);
                }
            }
        }
        while let Some(item) = self.index_rollbacks.pop() {
            if let Err(error) = item.rollback(repo) {
                if first_error.is_none() {
                    first_error = Some(error);
                }
            }
        }
        match first_error {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }

    fn into_report(self) -> BatchDeleteReport {
        self.report
    }
}

struct AppliedBatchDeleteItem {
    result: BatchDeleteItemResult,
    refresh: bool,
    undo_item: Option<db::BatchDeleteUndoItem>,
    trash_rollback: Option<TrashRollbackItem>,
    index_rollback: Option<IndexRollbackItem>,
}

fn apply_batch_delete_item(repo: &Path, item: BatchDeletePlanItem) -> AppliedBatchDeleteItem {
    match item {
        BatchDeletePlanItem::MoveToTrash(item) => match apply_move_to_trash(repo, item) {
            Ok(outcome) => applied_success(
                outcome.file_id,
                outcome.final_path,
                BatchDeleteResultStatus::MovedToTrash,
                Some(outcome.undo_item),
                Some(outcome.rollback_item),
                None,
            ),
            Err((file_id, path, error)) => applied_failure(file_id, path, error),
        },
        BatchDeletePlanItem::RemoveFromIndex(item) | BatchDeletePlanItem::Missing(item) => {
            match apply_remove_from_index(repo, item) {
                Ok(outcome) => applied_success(
                    outcome.file_id,
                    outcome.final_path,
                    BatchDeleteResultStatus::RemovedFromIndex,
                    None,
                    None,
                    Some(outcome.rollback_item),
                ),
                Err((file_id, path, error)) => applied_failure(file_id, path, error),
            }
        }
        BatchDeletePlanItem::Skipped(item) => AppliedBatchDeleteItem {
            result: BatchDeleteItemResult {
                file_id: item.file_id,
                final_path: item.current_path,
                status: BatchDeleteResultStatus::Skipped,
                error: Some(item.reason),
            },
            refresh: false,
            undo_item: None,
            trash_rollback: None,
            index_rollback: None,
        },
        BatchDeletePlanItem::Blocked(item) => AppliedBatchDeleteItem {
            result: BatchDeleteItemResult {
                file_id: item.file_id,
                final_path: item.current_path,
                status: BatchDeleteResultStatus::Failed,
                error: Some(item.reason),
            },
            refresh: false,
            undo_item: None,
            trash_rollback: None,
            index_rollback: None,
        },
    }
}

fn apply_move_to_trash(
    repo: &Path,
    item: PlannedBatchDeleteItem,
) -> Result<TrashDeleteOutcome, (i64, Option<String>, CoreError)> {
    let file_id = item.entry.id;
    let final_path = Some(item.entry.path.clone());
    let archive_path = delete_archive_path(repo, &item.current_path)
        .map_err(|error| (file_id, final_path.clone(), error))?;
    let detail = delete_detail(&item.entry);
    let mut guard = match DeleteArchiveGuard::archive(item.current_path, archive_path) {
        Ok(guard) => guard,
        Err(error) => return Err((file_id, final_path, error)),
    };
    match db::soft_delete_batch_repo_owned_file(repo, file_id, &detail) {
        Ok(()) => {}
        Err(error) => {
            let rollback = guard.rollback().err();
            return Err((file_id, final_path, rollback.unwrap_or(error)));
        }
    };
    let trash_path = match storage::move_to_user_trash(guard.archived_path()) {
        Ok(trash_path) => trash_path,
        Err(error) => {
            let rollback = guard.rollback().err();
            if let Err(db_error) =
                db::rollback_deleted_repo_owned_file(repo, file_id, &detail, None)
            {
                return Err((file_id, final_path, db_error));
            }
            return Err((file_id, final_path, rollback.unwrap_or(error)));
        }
    };
    let Some(trash_path) = trash_path else {
        return Err((
            file_id,
            final_path,
            CoreError::internal("Trash restore location unavailable"),
        ));
    };
    let rollback_item = TrashRollbackItem {
        file_id,
        trash_path: trash_path.clone(),
        restore_path: item.entry.path.clone(),
        detail,
    };
    let undo_item = db::BatchDeleteUndoItem {
        file_id,
        affected_file_name: item.entry.current_name.clone(),
        trash_path: trash_path.to_string_lossy().into_owned(),
        restore_path: item.entry.path.clone(),
        restore_name: item.entry.current_name,
        restore_category: item.entry.category,
    };
    guard.disarm();
    Ok(TrashDeleteOutcome {
        file_id,
        final_path,
        undo_item,
        rollback_item,
    })
}

fn apply_remove_from_index(
    repo: &Path,
    item: PlannedBatchDeleteItem,
) -> Result<IndexDeleteOutcome, (i64, Option<String>, CoreError)> {
    let file_id = item.entry.id;
    let final_path = Some(item.entry.path.clone());
    let detail = remove_index_detail(&item.entry, item.current_path.exists());
    match db::remove_batch_delete_index_entry_row(repo, file_id, &detail) {
        Ok(()) => Ok(IndexDeleteOutcome {
            file_id,
            final_path,
            rollback_item: IndexRollbackItem { file_id, detail },
        }),
        Err(error) => Err((file_id, final_path, error)),
    }
}

fn applied_success(
    file_id: i64,
    final_path: Option<String>,
    status: BatchDeleteResultStatus,
    undo_item: Option<db::BatchDeleteUndoItem>,
    trash_rollback: Option<TrashRollbackItem>,
    index_rollback: Option<IndexRollbackItem>,
) -> AppliedBatchDeleteItem {
    AppliedBatchDeleteItem {
        result: BatchDeleteItemResult {
            file_id,
            final_path,
            status,
            error: None,
        },
        refresh: true,
        undo_item,
        trash_rollback,
        index_rollback,
    }
}

fn applied_failure(
    file_id: i64,
    final_path: Option<String>,
    error: CoreError,
) -> AppliedBatchDeleteItem {
    AppliedBatchDeleteItem {
        result: BatchDeleteItemResult {
            file_id,
            final_path,
            status: BatchDeleteResultStatus::Failed,
            error: Some(super::error_message(error)),
        },
        refresh: false,
        undo_item: None,
        trash_rollback: None,
        index_rollback: None,
    }
}

struct TrashRollbackItem {
    file_id: i64,
    trash_path: PathBuf,
    restore_path: String,
    detail: Value,
}

impl TrashRollbackItem {
    fn rollback(self, repo: &Path) -> CoreResult<()> {
        let restore_path = super::repo_relative_file_path(repo, &self.restore_path)?;
        if self.trash_path.exists() && !restore_path.exists() {
            storage::move_recoverable_file(&self.trash_path, &restore_path)?;
        }
        db::rollback_deleted_repo_owned_file(repo, self.file_id, &self.detail, None)
    }
}

struct TrashDeleteOutcome {
    file_id: i64,
    final_path: Option<String>,
    undo_item: db::BatchDeleteUndoItem,
    rollback_item: TrashRollbackItem,
}

struct IndexRollbackItem {
    file_id: i64,
    detail: Value,
}

impl IndexRollbackItem {
    fn rollback(self, repo: &Path) -> CoreResult<()> {
        db::rollback_removed_index_entry_row(repo, self.file_id, &self.detail)
    }
}

struct IndexDeleteOutcome {
    file_id: i64,
    final_path: Option<String>,
    rollback_item: IndexRollbackItem,
}

fn delete_archive_path(repo: &Path, target_path: &Path) -> CoreResult<PathBuf> {
    let file_name = target_path
        .file_name()
        .ok_or_else(|| CoreError::invalid_path("invalid path"))?;
    Ok(repo
        .join(super::AREA_MATRIX_DIR)
        .join(ARCHIVES_DIR)
        .join(format!("delete-{}", uuid::Uuid::new_v4()))
        .join(file_name))
}

fn delete_detail(entry: &FileEntry) -> serde_json::Value {
    json!({
        "hard": false,
        "by": "user",
        "kind": "batch_delete_trash",
        "from_path": entry.path,
        "storage_mode": storage_mode_detail(&entry.storage_mode),
        "trash_location": "system",
        "trashed": true,
    })
}

fn remove_index_detail(entry: &FileEntry, source_exists: bool) -> serde_json::Value {
    json!({
        "by": "user",
        "kind": "batch_delete_trash",
        "index_only": true,
        "path": entry.path,
        "storage_mode": storage_mode_detail(&entry.storage_mode),
        "origin": origin_detail(&entry.origin),
        "source_exists": source_exists,
    })
}

fn storage_mode_detail(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

fn origin_detail(origin: &FileOrigin) -> &'static str {
    match origin {
        FileOrigin::Imported => "imported",
        FileOrigin::Adopted => "adopted",
        FileOrigin::External => "external",
    }
}

struct DeleteArchiveGuard {
    original_path: PathBuf,
    archived_path: PathBuf,
    archive_dir: PathBuf,
    armed: bool,
}

impl DeleteArchiveGuard {
    fn archive(original_path: PathBuf, archived_path: PathBuf) -> CoreResult<Self> {
        let archive_dir = archived_path
            .parent()
            .ok_or_else(|| CoreError::invalid_path("invalid path"))?
            .to_path_buf();
        fs::create_dir_all(&archive_dir).map_err(map_io_error)?;
        storage::move_recoverable_file(&original_path, &archived_path)?;
        Ok(Self {
            original_path,
            archived_path,
            archive_dir,
            armed: true,
        })
    }

    fn archived_path(&self) -> &Path {
        &self.archived_path
    }

    fn rollback(&mut self) -> CoreResult<()> {
        if self.armed && self.archived_path.exists() && !self.original_path.exists() {
            storage::move_recoverable_file(&self.archived_path, &self.original_path)?;
        }
        self.cleanup_archive_dir();
        self.armed = false;
        Ok(())
    }

    fn disarm(&mut self) {
        self.cleanup_archive_dir();
        self.armed = false;
    }

    fn cleanup_archive_dir(&self) {
        let _cleanup_result = fs::remove_dir(&self.archive_dir);
    }
}

impl Drop for DeleteArchiveGuard {
    fn drop(&mut self) {
        if self.armed && self.archived_path.exists() && !self.original_path.exists() {
            let _restore_result =
                storage::move_recoverable_file(&self.archived_path, &self.original_path);
        }
        self.cleanup_archive_dir();
    }
}

fn map_io_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::NotFound => CoreError::file_not_found(error.to_string()),
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied(error.to_string()),
        std::io::ErrorKind::AlreadyExists => CoreError::conflict(error.to_string()),
        std::io::ErrorKind::InvalidInput => CoreError::invalid_path(error.to_string()),
        _ => CoreError::io(error.to_string()),
    }
}
