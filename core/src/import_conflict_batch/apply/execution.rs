use std::path::Path;

use crate::{db, CoreResult, ImportConflictBatchApplyReport, ImportConflictBatchResultStatus};

use super::{
    item::apply_item, result::AppliedImportConflictItem, rollback::ImportConflictRollback,
};
use crate::import_conflict_batch::PlannedImportConflict;

pub(in crate::import_conflict_batch) fn apply_plan(
    repo: &Path,
    import_session_id: &str,
    plan: &[PlannedImportConflict],
) -> CoreResult<ImportConflictBatchApplyReport> {
    let mut execution = ImportConflictBatchExecution::new(import_session_id, plan);
    let session_status = db::get_import_session_status(repo, import_session_id)?;
    if will_write_undo(plan) {
        db::preflight_import_conflict_undo_action(repo)?;
    }
    for item in plan {
        match apply_item(repo, item, &session_status) {
            Ok(applied) => execution.push(applied),
            Err(error) => {
                let rollback_error = execution.rollback_successes(repo).err();
                return Err(rollback_error.unwrap_or(error));
            }
        }
    }
    execution.insert_undo(repo)?;
    Ok(execution.into_report())
}

struct ImportConflictBatchExecution {
    report: ImportConflictBatchApplyReport,
    undo_names: Vec<String>,
    rollbacks: Vec<ImportConflictRollback>,
}

impl ImportConflictBatchExecution {
    fn new(import_session_id: &str, plan: &[PlannedImportConflict]) -> Self {
        Self {
            report: ImportConflictBatchApplyReport {
                import_session_id: import_session_id.to_owned(),
                requested_conflict_count: plan.iter().filter(|item| item.included).count() as i64,
                resolved_count: 0,
                skipped_count: 0,
                kept_both_count: 0,
                replaced_count: 0,
                queued_for_per_item_count: 0,
                pending_count: 0,
                failed_count: 0,
                item_results: Vec::new(),
                affected_file_ids: Vec::new(),
                undo_token: None,
                change_log_actions: Vec::new(),
                failure_summary: None,
            },
            undo_names: Vec::new(),
            rollbacks: Vec::new(),
        }
    }

    fn push(&mut self, applied: AppliedImportConflictItem) {
        match applied.result.status {
            ImportConflictBatchResultStatus::Skipped => {
                self.report.resolved_count += 1;
                self.report.skipped_count += 1;
            }
            ImportConflictBatchResultStatus::KeptBoth => {
                self.report.resolved_count += 1;
                self.report.kept_both_count += 1;
            }
            ImportConflictBatchResultStatus::Replaced => {
                self.report.resolved_count += 1;
                self.report.replaced_count += 1;
            }
            ImportConflictBatchResultStatus::QueuedForPerItem => {
                self.report.resolved_count += 1;
                self.report.queued_for_per_item_count += 1;
            }
            ImportConflictBatchResultStatus::Pending => self.report.pending_count += 1,
            ImportConflictBatchResultStatus::Failed => self.report.failed_count += 1,
        }
        for file_id in applied.affected_file_ids {
            if !self.report.affected_file_ids.contains(&file_id) {
                self.report.affected_file_ids.push(file_id);
            }
        }
        for action in applied.change_log_actions {
            if !self.report.change_log_actions.contains(&action) {
                self.report.change_log_actions.push(action);
            }
        }
        if let Some(name) = applied.undo_name {
            self.undo_names.push(name);
        }
        if let Some(rollback) = applied.rollback {
            self.rollbacks.push(rollback);
        }
        self.report.item_results.push(applied.result);
    }

    fn insert_undo(&mut self, repo: &Path) -> CoreResult<()> {
        if self.undo_names.is_empty() {
            return Ok(());
        }
        match db::insert_import_conflict_undo_action(repo, &self.undo_names) {
            Ok(token) => self.report.undo_token = Some(token),
            Err(error) => {
                let rollback_error = self.rollback_successes(repo).err();
                return Err(rollback_error.unwrap_or(error));
            }
        }
        Ok(())
    }

    fn rollback_successes(&mut self, repo: &Path) -> CoreResult<()> {
        let mut first_error = None;
        while let Some(rollback) = self.rollbacks.pop() {
            if let Err(error) = rollback.apply(repo) {
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

    fn into_report(mut self) -> ImportConflictBatchApplyReport {
        if self.report.failed_count > 0 {
            self.report.failure_summary = Some(format!(
                "{} import conflict(s) failed and remain staged for retry",
                self.report.failed_count
            ));
        }
        self.report
    }
}

fn will_write_undo(plan: &[PlannedImportConflict]) -> bool {
    plan.iter().any(|item| {
        item.included
            && super::item::is_actionable(&item.status)
            && matches!(
                item.strategy,
                crate::ImportConflictBatchStrategy::KeepBoth
                    | crate::ImportConflictBatchStrategy::Replace
            )
    })
}
