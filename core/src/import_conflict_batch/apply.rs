use std::{fs, path::Path};

use serde_json::{json, Value};

use crate::{
    db, storage, CoreError, CoreResult, FileEntry, ImportConflictBatchApplyReport,
    ImportConflictBatchItemResult, ImportConflictBatchPreviewStatus,
    ImportConflictBatchResultStatus, ImportConflictBatchStrategy,
};

use super::{
    conflict_type_detail, path, storage_mode_detail, strategy_detail, PlannedImportConflict,
};

mod replace;

pub(super) fn apply_plan(
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

pub(super) struct AppliedImportConflictItem {
    result: ImportConflictBatchItemResult,
    affected_file_ids: Vec<i64>,
    change_log_actions: Vec<String>,
    undo_name: Option<String>,
    pub(super) rollback: Option<ImportConflictRollback>,
}

pub(super) enum ImportConflictRollback {
    Decision {
        row: db::ImportConflictRow,
        session_status: String,
    },
    KeepBoth {
        row: db::ImportConflictRow,
        final_path: String,
        staging_path: String,
        staging_name: String,
        session_status: String,
    },
    Replace {
        row: db::ImportConflictRow,
        final_path: String,
        archived_path: String,
        staging_path: String,
        staging_name: String,
        session_status: String,
    },
}

impl ImportConflictRollback {
    fn apply(self, repo: &Path) -> CoreResult<()> {
        match self {
            Self::Decision {
                row,
                session_status,
            } => db::rollback_import_conflict_decision(repo, &row, &session_status),
            Self::KeepBoth {
                row,
                final_path,
                staging_path,
                staging_name,
                session_status,
            } => {
                restore_staging_file(repo, &final_path, &staging_path)?;
                db::rollback_import_conflict_keep_both(
                    repo,
                    &row,
                    &final_path,
                    &staging_path,
                    &staging_name,
                    &session_status,
                )
            }
            Self::Replace {
                row,
                final_path,
                archived_path,
                staging_path,
                staging_name,
                session_status,
            } => {
                restore_staging_file(repo, &final_path, &staging_path)?;
                restore_replaced_file(repo, &archived_path, &row.target_path)?;
                db::rollback_import_conflict_replace(
                    repo,
                    &row,
                    &final_path,
                    &archived_path,
                    &staging_path,
                    &staging_name,
                    &session_status,
                )
            }
        }
    }
}

fn restore_staging_file(repo: &Path, final_path: &str, staging_path: &str) -> CoreResult<()> {
    let final_absolute_path = path::repo_relative_file_path(repo, final_path)?;
    let staging_absolute_path = path::staging_file_path(repo, staging_path)?;
    if final_absolute_path.exists() && !staging_absolute_path.exists() {
        storage::move_recoverable_file(&final_absolute_path, &staging_absolute_path)?;
    }
    Ok(())
}

fn restore_replaced_file(repo: &Path, archived_path: &str, target_path: &str) -> CoreResult<()> {
    let archive_absolute_path = internal_repo_path(repo, archived_path)?;
    let target_absolute_path = path::repo_relative_file_path(repo, target_path)?;
    if archive_absolute_path.exists() && !target_absolute_path.exists() {
        storage::move_recoverable_file(&archive_absolute_path, &target_absolute_path)?;
    }
    Ok(())
}

fn internal_repo_path(repo: &Path, relative_path: &str) -> CoreResult<std::path::PathBuf> {
    let relative = Path::new(relative_path);
    if relative.is_absolute() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    Ok(repo.join(relative))
}

fn apply_item(
    repo: &Path,
    item: &PlannedImportConflict,
    session_status: &str,
) -> CoreResult<AppliedImportConflictItem> {
    if !item.included || !is_actionable(&item.status) {
        return Ok(pending_result(item));
    }
    let result = match item.strategy {
        ImportConflictBatchStrategy::Skip => apply_skip(repo, item, session_status),
        ImportConflictBatchStrategy::AskPerItem => apply_ask_per_item(repo, item, session_status),
        ImportConflictBatchStrategy::KeepBoth => apply_keep_both(repo, item, session_status),
        ImportConflictBatchStrategy::Replace => replace::apply_replace(repo, item, session_status),
    };
    match result {
        Ok(applied) => Ok(applied),
        Err(error) => mark_failed(repo, item, error),
    }
}

fn apply_skip(
    repo: &Path,
    item: &PlannedImportConflict,
    session_status: &str,
) -> CoreResult<AppliedImportConflictItem> {
    db::resolve_import_conflict_item(
        repo,
        db::ImportConflictApplyItem {
            conflict: &item.row,
            final_path: None,
            final_name: None,
            change_detail: None,
            replaced: None,
            decision: strategy_detail(&item.strategy),
        },
    )?;
    let mut applied = simple_result(item, ImportConflictBatchResultStatus::Skipped, None, None);
    applied.rollback = Some(ImportConflictRollback::Decision {
        row: item.row.clone(),
        session_status: session_status.to_owned(),
    });
    Ok(applied)
}

fn apply_ask_per_item(
    repo: &Path,
    item: &PlannedImportConflict,
    session_status: &str,
) -> CoreResult<AppliedImportConflictItem> {
    db::queue_import_conflict_for_per_item(repo, &item.row)?;
    let mut applied = simple_result(
        item,
        ImportConflictBatchResultStatus::QueuedForPerItem,
        None,
        None,
    );
    applied.rollback = Some(ImportConflictRollback::Decision {
        row: item.row.clone(),
        session_status: session_status.to_owned(),
    });
    Ok(applied)
}

fn apply_keep_both(
    repo: &Path,
    item: &PlannedImportConflict,
    session_status: &str,
) -> CoreResult<AppliedImportConflictItem> {
    let staging = required_staging(item)?;
    let final_path = required_final_path(item)?;
    let final_name = required_final_name(item)?;
    let staging_path = path::staging_file_path(repo, &staging.path)?;
    let final_absolute_path = path::repo_relative_file_path(repo, final_path)?;
    ensure_parent_dir(&final_absolute_path)?;
    storage::move_recoverable_file(&staging_path, &final_absolute_path)?;
    let detail = import_detail(
        item,
        staging,
        final_path,
        strategy_detail(&item.strategy),
        None,
    );
    match db::resolve_import_conflict_item(
        repo,
        db::ImportConflictApplyItem {
            conflict: &item.row,
            final_path: Some(final_path),
            final_name: Some(final_name),
            change_detail: Some(&detail),
            replaced: None,
            decision: strategy_detail(&item.strategy),
        },
    ) {
        Ok(()) => {
            let mut applied = successful_write_result(
                item,
                ImportConflictBatchResultStatus::KeptBoth,
                staging.id,
                final_path,
                vec![staging.id],
                vec!["imported".to_owned()],
            );
            applied.rollback = Some(ImportConflictRollback::KeepBoth {
                row: item.row.clone(),
                final_path: final_path.to_owned(),
                staging_path: staging.path.clone(),
                staging_name: staging.current_name.clone(),
                session_status: session_status.to_owned(),
            });
            Ok(applied)
        }
        Err(error) => {
            let rollback =
                storage::move_recoverable_file(&final_absolute_path, &staging_path).err();
            Err(rollback.unwrap_or(error))
        }
    }
}

fn pending_result(item: &PlannedImportConflict) -> AppliedImportConflictItem {
    simple_result(
        item,
        ImportConflictBatchResultStatus::Pending,
        item.final_relative_path.clone(),
        item.reason.clone(),
    )
}

fn simple_result(
    item: &PlannedImportConflict,
    status: ImportConflictBatchResultStatus,
    final_path: Option<String>,
    error: Option<String>,
) -> AppliedImportConflictItem {
    AppliedImportConflictItem {
        result: ImportConflictBatchItemResult {
            conflict_id: item.row.conflict_id.clone(),
            conflict_type: super::api_conflict_type(&item.row.conflict_type),
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
            conflict_type: super::api_conflict_type(&item.row.conflict_type),
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

fn mark_failed(
    repo: &Path,
    item: &PlannedImportConflict,
    error: CoreError,
) -> CoreResult<AppliedImportConflictItem> {
    let reason = error_message(error);
    db::mark_import_conflict_failed(repo, &item.row, strategy_detail(&item.strategy), &reason)?;
    Ok(simple_result(
        item,
        ImportConflictBatchResultStatus::Failed,
        item.final_relative_path.clone(),
        Some(reason),
    ))
}

pub(super) fn required_final_path(item: &PlannedImportConflict) -> CoreResult<&str> {
    item.final_relative_path
        .as_deref()
        .ok_or_else(|| CoreError::conflict("missing final path"))
}

pub(super) fn required_final_name(item: &PlannedImportConflict) -> CoreResult<&str> {
    item.final_name
        .as_deref()
        .ok_or_else(|| CoreError::conflict("missing final name"))
}

pub(super) fn required_staging(item: &PlannedImportConflict) -> CoreResult<&FileEntry> {
    item.staging
        .as_ref()
        .ok_or_else(|| CoreError::staging_recovery_required(item.row.incoming_path.clone()))
}

fn is_actionable(status: &ImportConflictBatchPreviewStatus) -> bool {
    matches!(
        status,
        ImportConflictBatchPreviewStatus::Ready
            | ImportConflictBatchPreviewStatus::NeedsConfirmation
    )
}

fn will_write_undo(plan: &[PlannedImportConflict]) -> bool {
    plan.iter().any(|item| {
        item.included
            && is_actionable(&item.status)
            && matches!(
                item.strategy,
                ImportConflictBatchStrategy::KeepBoth | ImportConflictBatchStrategy::Replace
            )
    })
}

pub(super) fn import_detail(
    item: &PlannedImportConflict,
    staging: &FileEntry,
    final_path: &str,
    decision: &str,
    existing: Option<&FileEntry>,
) -> Value {
    json!({
        "source": staging.source_path.clone().unwrap_or_else(|| item.row.incoming_path.clone()),
        "mode": storage_mode_detail(&staging.storage_mode),
        "category": staging.category,
        "destination": "import_conflict_batch",
        "requested_name": staging.current_name,
        "final_name": item.final_name.clone().unwrap_or_else(|| staging.current_name.clone()),
        "final_path": final_path,
        "name_conflict_resolved": item.row.target_path != final_path,
        "duplicate_strategy": decision,
        "conflict_id": item.row.conflict_id,
        "conflict_type": conflict_type_detail(&item.row.conflict_type),
        "replaced_file_id": existing.map(|entry| entry.id),
        "replaced_path": existing.map(|entry| entry.path.clone()),
        "by": "user",
    })
}

pub(super) fn deleted_detail(existing: &FileEntry, archived_path: &str) -> Value {
    json!({
        "hard": false,
        "by": "user",
        "reason": "import_conflict_batch_replace",
        "from_path": existing.path,
        "archived_path": archived_path,
        "trash_location": "recovery",
        "trashed": true,
        "storage_mode": storage_mode_detail(&existing.storage_mode),
        "safe_replace": true,
    })
}

pub(super) fn ensure_parent_dir(path: &Path) -> CoreResult<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(path::map_io_error)?;
    }
    Ok(())
}

fn error_message(error: CoreError) -> String {
    match error {
        CoreError::Conflict { path }
        | CoreError::FileNotFound { path }
        | CoreError::InvalidPath { path }
        | CoreError::PermissionDenied { path }
        | CoreError::StagingRecoveryRequired { path } => path,
        CoreError::DuplicateFile { existing_path } => existing_path,
        CoreError::ExpiredAction { action_id } => action_id,
        CoreError::Io { message } | CoreError::Db { message } | CoreError::Internal { message } => {
            message
        }
        CoreError::Config { reason } | CoreError::Classify { reason } => reason,
        CoreError::RepoNotInitialized { path } | CoreError::ICloudPlaceholder { path } => path,
    }
}
