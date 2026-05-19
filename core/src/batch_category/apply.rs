use std::path::Path;

use serde_json::{json, Value};

use crate::{
    BatchCategoryChangeItemResult, BatchCategoryChangeReport, BatchCategoryResultStatus, CoreError,
    CoreResult, FileEntry,
};

use super::{
    fs_move::{
        move_checked_file, move_recoverable_file, AppliedFsMove, CategoryDirectoryGuard,
        MoveRollbackGuard,
    },
    plan::{BatchCategoryPlan, BatchCategoryPlanItem, PlannedCategoryChange},
};

pub(super) fn apply_batch_category_plan(
    repo: &Path,
    plan: BatchCategoryPlan,
) -> CoreResult<BatchCategoryChangeReport> {
    let (report, mut fs_moves) = crate::db::with_batch_category_transaction(repo, |tx| {
        let mut report = BatchCategoryExecution::new(&plan);
        for item in plan.items {
            report.push(apply_item(tx, item)?);
        }
        if report.has_successful_write() {
            report.undo_token = Some(crate::db::insert_batch_category_undo_action_in_tx(
                tx,
                &report.undo_items,
            )?);
        }
        let fs_moves = std::mem::take(&mut report.fs_moves);
        Ok((report.into_report(), fs_moves))
    })?;
    for fs_move in &mut fs_moves {
        fs_move.disarm();
    }
    Ok(report)
}

struct BatchCategoryExecution {
    requested_file_count: i64,
    target_category: String,
    moved_count: i64,
    metadata_only_count: i64,
    unchanged_count: i64,
    skipped_count: i64,
    failed_count: i64,
    item_results: Vec<BatchCategoryChangeItemResult>,
    updated_files: Vec<FileEntry>,
    undo_items: Vec<crate::db::BatchCategoryUndoItem>,
    fs_moves: Vec<AppliedFsMove>,
    undo_token: Option<String>,
}

impl BatchCategoryExecution {
    fn new(plan: &BatchCategoryPlan) -> Self {
        Self {
            requested_file_count: plan.requested_file_count,
            target_category: plan.target_category.clone(),
            moved_count: 0,
            metadata_only_count: 0,
            unchanged_count: 0,
            skipped_count: 0,
            failed_count: 0,
            item_results: Vec::new(),
            updated_files: Vec::new(),
            undo_items: Vec::new(),
            fs_moves: Vec::new(),
            undo_token: None,
        }
    }

    fn push(&mut self, result: AppliedBatchCategoryItem) {
        match result.report.status {
            BatchCategoryResultStatus::Moved => self.moved_count += 1,
            BatchCategoryResultStatus::MetadataUpdated => self.metadata_only_count += 1,
            BatchCategoryResultStatus::Unchanged => self.unchanged_count += 1,
            BatchCategoryResultStatus::Skipped => self.skipped_count += 1,
            BatchCategoryResultStatus::Failed => self.failed_count += 1,
        }
        if let Some(entry) = result.updated_file {
            self.updated_files.push(entry);
        }
        if let Some(undo_item) = result.undo_item {
            self.undo_items.push(undo_item);
        }
        if let Some(fs_move) = result.fs_move {
            self.fs_moves.push(fs_move);
        }
        self.item_results.push(result.report);
    }

    fn has_successful_write(&self) -> bool {
        self.moved_count > 0 || self.metadata_only_count > 0
    }

    fn into_report(self) -> BatchCategoryChangeReport {
        BatchCategoryChangeReport {
            requested_file_count: self.requested_file_count,
            target_category: self.target_category,
            moved_count: self.moved_count,
            metadata_only_count: self.metadata_only_count,
            unchanged_count: self.unchanged_count,
            skipped_count: self.skipped_count,
            failed_count: self.failed_count,
            item_results: self.item_results,
            updated_files: self.updated_files,
            undo_token: self.undo_token,
        }
    }
}

struct AppliedBatchCategoryItem {
    report: BatchCategoryChangeItemResult,
    updated_file: Option<FileEntry>,
    undo_item: Option<crate::db::BatchCategoryUndoItem>,
    fs_move: Option<AppliedFsMove>,
}

fn apply_item(
    tx: &mut rusqlite::Transaction<'_>,
    item: BatchCategoryPlanItem,
) -> CoreResult<AppliedBatchCategoryItem> {
    match item {
        BatchCategoryPlanItem::WillMove(change) => apply_change(tx, change, false),
        BatchCategoryPlanItem::MetadataOnly(change) => apply_change(tx, change, true),
        BatchCategoryPlanItem::Unchanged(change) => Ok(unchanged_result(change)),
        BatchCategoryPlanItem::Skipped(change) => Ok(AppliedBatchCategoryItem {
            report: BatchCategoryChangeItemResult {
                file_id: change.file_id,
                from_category: None,
                to_category: change.target_category,
                final_path: None,
                status: BatchCategoryResultStatus::Skipped,
                error: Some(change.reason),
            },
            updated_file: None,
            undo_item: None,
            fs_move: None,
        }),
        BatchCategoryPlanItem::Blocked(change) => Ok(AppliedBatchCategoryItem {
            report: BatchCategoryChangeItemResult {
                file_id: change.file_id,
                from_category: change.from_category,
                to_category: change.target_category,
                final_path: change.current_path,
                status: BatchCategoryResultStatus::Failed,
                error: Some(change.reason),
            },
            updated_file: None,
            undo_item: None,
            fs_move: None,
        }),
    }
}

fn apply_change(
    tx: &mut rusqlite::Transaction<'_>,
    change: PlannedCategoryChange,
    metadata_only: bool,
) -> CoreResult<AppliedBatchCategoryItem> {
    let savepoint = tx
        .savepoint()
        .map_err(|error| CoreError::db(error.to_string()))?;
    match try_apply_change(&savepoint, &change, metadata_only) {
        Ok((updated, undo_item, fs_move)) => match savepoint.commit() {
            Ok(()) => Ok(successful_change_result(
                change,
                metadata_only,
                updated,
                undo_item,
                fs_move,
            )),
            Err(error) => {
                drop(fs_move);
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

fn successful_change_result(
    change: PlannedCategoryChange,
    metadata_only: bool,
    updated: FileEntry,
    undo_item: crate::db::BatchCategoryUndoItem,
    fs_move: Option<AppliedFsMove>,
) -> AppliedBatchCategoryItem {
    AppliedBatchCategoryItem {
        report: BatchCategoryChangeItemResult {
            file_id: change.entry.id,
            from_category: Some(change.entry.category),
            to_category: change.target_category,
            final_path: Some(updated.path.clone()),
            status: if metadata_only {
                BatchCategoryResultStatus::MetadataUpdated
            } else {
                BatchCategoryResultStatus::Moved
            },
            error: None,
        },
        updated_file: Some(updated),
        undo_item: Some(undo_item),
        fs_move,
    }
}

fn failed_change_result(
    change: PlannedCategoryChange,
    error: CoreError,
) -> AppliedBatchCategoryItem {
    AppliedBatchCategoryItem {
        report: BatchCategoryChangeItemResult {
            file_id: change.entry.id,
            from_category: Some(change.entry.category),
            to_category: change.target_category,
            final_path: Some(change.final_relative_path),
            status: BatchCategoryResultStatus::Failed,
            error: Some(batch_category_failure_message(error)),
        },
        updated_file: None,
        undo_item: None,
        fs_move: None,
    }
}

fn try_apply_change(
    connection: &rusqlite::Connection,
    change: &PlannedCategoryChange,
    metadata_only: bool,
) -> CoreResult<(
    FileEntry,
    crate::db::BatchCategoryUndoItem,
    Option<AppliedFsMove>,
)> {
    let mut fs_move = None;
    if metadata_only {
        crate::db::batch_update_category_metadata_only_in_tx(
            connection,
            change.entry.id,
            &change.target_category,
            &move_detail(change, true),
        )?;
    } else {
        let directory_guard = CategoryDirectoryGuard::ensure(
            change
                .final_path
                .parent()
                .ok_or_else(|| CoreError::invalid_path("invalid path"))?
                .to_path_buf(),
        )?;
        move_recoverable_file(&change.current_path, &change.final_path)?;
        let mut file_guard =
            MoveRollbackGuard::new(change.final_path.clone(), change.current_path.clone());
        let mut note_guard = move_note_sidecar(change, &mut file_guard)?;
        if let Err(error) = crate::db::batch_update_category_repo_owned_in_tx(
            connection,
            change.entry.id,
            &change.final_relative_path,
            &change.final_name,
            &change.target_category,
            &move_detail(change, false),
        ) {
            rollback_filesystem_move(&mut file_guard, &mut note_guard)?;
            return Err(error);
        }
        fs_move = Some(AppliedFsMove {
            note_guard,
            file_guard,
            directory_guard,
        });
    }

    let updated = crate::db::load_batch_category_active_file(connection, change.entry.id)?;
    let undo_item =
        crate::db::BatchCategoryUndoItem::from_file_states(&change.entry, &updated, metadata_only);
    Ok((updated, undo_item, fs_move))
}

fn unchanged_result(change: PlannedCategoryChange) -> AppliedBatchCategoryItem {
    AppliedBatchCategoryItem {
        report: BatchCategoryChangeItemResult {
            file_id: change.entry.id,
            from_category: Some(change.entry.category.clone()),
            to_category: change.target_category,
            final_path: Some(change.entry.path),
            status: BatchCategoryResultStatus::Unchanged,
            error: None,
        },
        updated_file: None,
        undo_item: None,
        fs_move: None,
    }
}

fn move_detail(change: &PlannedCategoryChange, index_only: bool) -> Value {
    let mut detail = json!({
        "kind": "batch_change_category",
        "from_category": change.entry.category,
        "to_category": change.target_category,
        "from_path": change.entry.path,
        "to_path": change.final_relative_path,
        "final_name": change.final_name,
        "name_conflict_resolved": change.final_name != change.entry.current_name,
        "storage_mode": storage_mode_detail(&change.entry.storage_mode),
        "index_only": index_only,
        "by": "user",
    });
    if change.final_name != change.entry.current_name {
        detail["renamed_to"] = json!(change.final_name);
    }
    detail
}

fn move_note_sidecar(
    change: &PlannedCategoryChange,
    file_guard: &mut MoveRollbackGuard,
) -> CoreResult<Option<MoveRollbackGuard>> {
    let Some(sidecar) = &change.note_sidecar else {
        return Ok(None);
    };
    match move_checked_file(&sidecar.current_path, &sidecar.final_path) {
        Ok(()) => Ok(Some(MoveRollbackGuard::new(
            sidecar.final_path.clone(),
            sidecar.current_path.clone(),
        ))),
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

fn storage_mode_detail(mode: &crate::StorageMode) -> &'static str {
    match mode {
        crate::StorageMode::Moved => "moved",
        crate::StorageMode::Copied => "copied",
        crate::StorageMode::Indexed => "indexed",
    }
}

fn batch_category_failure_message(error: CoreError) -> String {
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
