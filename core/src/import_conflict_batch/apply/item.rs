use std::path::Path;

use crate::{
    db, storage, CoreError, CoreResult, FileEntry, ImportConflictBatchPreviewStatus,
    ImportConflictBatchResultStatus, ImportConflictBatchStrategy,
};

use super::{
    detail::{import_detail, strategy_detail_for_item},
    result::{pending_result, simple_result, successful_write_result, AppliedImportConflictItem},
    rollback::ImportConflictRollback,
};
use crate::import_conflict_batch::{path, strategy_detail, PlannedImportConflict};

pub(super) fn apply_item(
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
        ImportConflictBatchStrategy::Replace => {
            super::replace::apply_replace(repo, item, session_status)
        }
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
            decision: strategy_detail_for_item(item),
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
    super::detail::ensure_parent_dir(&final_absolute_path)?;
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

pub(super) fn is_actionable(status: &ImportConflictBatchPreviewStatus) -> bool {
    matches!(
        status,
        ImportConflictBatchPreviewStatus::Ready
            | ImportConflictBatchPreviewStatus::NeedsConfirmation
    )
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

fn error_message(error: CoreError) -> String {
    match error {
        CoreError::Conflict { path }
        | CoreError::FileNotFound { path }
        | CoreError::InvalidPath { path }
        | CoreError::PermissionDenied { path }
        | CoreError::StagingRecoveryRequired { path } => path,
        CoreError::DuplicateFile { existing_path } => existing_path,
        CoreError::ExpiredAction { action_id } => action_id,
        CoreError::Io { message }
        | CoreError::Db { message }
        | CoreError::DbLocked { message }
        | CoreError::DbCorrupted { message }
        | CoreError::Internal { message } => message,
        CoreError::Config { reason }
        | CoreError::Validation { reason }
        | CoreError::Classify { reason } => reason,
        CoreError::RepoNotInitialized { path } | CoreError::ICloudPlaceholder { path } => path,
        CoreError::RevisionConflict {
            resource,
            expected_revision,
            current_revision,
        } => format!(
            "{resource}: expected revision {expected_revision}, current revision {current_revision}"
        ),
    }
}
