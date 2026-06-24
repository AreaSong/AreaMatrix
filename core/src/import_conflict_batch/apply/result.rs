use crate::{ImportConflictBatchItemResult, ImportConflictBatchResultStatus};

use super::rollback::ImportConflictRollback;
use crate::import_conflict_batch::{api_conflict_type, PlannedImportConflict};

pub(super) struct AppliedImportConflictItem {
    pub(super) result: ImportConflictBatchItemResult,
    pub(super) affected_file_ids: Vec<i64>,
    pub(super) change_log_actions: Vec<String>,
    pub(super) undo_name: Option<String>,
    pub(super) rollback: Option<ImportConflictRollback>,
}

pub(super) fn pending_result(item: &PlannedImportConflict) -> AppliedImportConflictItem {
    simple_result(
        item,
        ImportConflictBatchResultStatus::Pending,
        item.final_relative_path.clone(),
        item.reason.clone(),
    )
}

pub(super) fn simple_result(
    item: &PlannedImportConflict,
    status: ImportConflictBatchResultStatus,
    final_path: Option<String>,
    error: Option<String>,
) -> AppliedImportConflictItem {
    AppliedImportConflictItem {
        result: ImportConflictBatchItemResult {
            conflict_id: item.row.conflict_id.clone(),
            conflict_type: api_conflict_type(&item.row.conflict_type),
            applied_strategy: item.strategy.clone(),
            status,
            file_id: None,
            final_path,
            error,
        },
        affected_file_ids: Vec::new(),
        change_log_actions: Vec::new(),
        undo_name: None,
        rollback: None,
    }
}

pub(super) fn successful_write_result(
    item: &PlannedImportConflict,
    status: ImportConflictBatchResultStatus,
    file_id: i64,
    final_path: &str,
    affected_file_ids: Vec<i64>,
    change_log_actions: Vec<String>,
) -> AppliedImportConflictItem {
    AppliedImportConflictItem {
        result: ImportConflictBatchItemResult {
            conflict_id: item.row.conflict_id.clone(),
            conflict_type: api_conflict_type(&item.row.conflict_type),
            applied_strategy: item.strategy.clone(),
            status,
            file_id: Some(file_id),
            final_path: Some(final_path.to_owned()),
            error: None,
        },
        affected_file_ids,
        change_log_actions,
        undo_name: item.final_name.clone(),
        rollback: None,
    }
}
