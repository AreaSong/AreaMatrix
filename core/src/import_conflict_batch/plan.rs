use std::path::{Path, PathBuf};

use crate::{db, CoreError, CoreResult, FileEntry, StorageMode};

use super::{
    api_conflict_type, path, risk_summary, token, ImportConflictBatchPreviewItem,
    ImportConflictBatchPreviewReport, ImportConflictBatchPreviewRequest,
    ImportConflictBatchPreviewStatus, ImportConflictBatchStrategy, PlannedImportConflict,
};

pub(super) fn build_plan(
    repo: &Path,
    import_session_id: &str,
    requested_ids: &[String],
    request: &ImportConflictBatchPreviewRequest,
) -> CoreResult<Vec<PlannedImportConflict>> {
    let rows = db::list_import_conflicts_for_session(repo, import_session_id)?;
    if rows.is_empty() {
        return Err(CoreError::file_not_found("import-session:empty"));
    }
    ensure_requested_conflicts_exist(&rows, requested_ids)?;
    let selected_kinds = selected_conflict_kinds(&rows, requested_ids);
    let trash_available = trash_available(repo);
    rows.into_iter()
        .map(|row| {
            let included = should_include(
                &row,
                requested_ids,
                &selected_kinds,
                request.apply_to_all_similar_conflicts,
            );
            plan_row(repo, row, included, request, trash_available)
        })
        .collect()
}

pub(super) fn preview_report(
    repo: &Path,
    request: &ImportConflictBatchPreviewRequest,
    requested_ids: &[String],
    plan: &[PlannedImportConflict],
) -> ImportConflictBatchPreviewReport {
    let items = preview_items(plan);
    let can_apply = can_apply(plan);
    let replace_count = count_plan(plan, |item| {
        item.included
            && is_actionable(&item.status)
            && item.strategy == ImportConflictBatchStrategy::Replace
    });
    ImportConflictBatchPreviewReport {
        import_session_id: request.import_session_id.clone(),
        preview_token: token::preview_token_for(&request.import_session_id, requested_ids, plan),
        apply_to_all_similar_conflicts: request.apply_to_all_similar_conflicts,
        requested_conflict_count: scoped_count(plan),
        duplicate_conflict_count: count_plan(plan, |item| {
            item.included && item.row.conflict_type == db::ImportConflictKind::DuplicateHash
        }),
        same_name_conflict_count: count_plan(plan, |item| {
            item.included
                && item.row.conflict_type == db::ImportConflictKind::SameNameDifferentContent
        }),
        included_count: scoped_count(plan),
        pending_count: count_plan(plan, |item| {
            !item.included || item.status == ImportConflictBatchPreviewStatus::Pending
        }),
        blocked_count: count_plan(plan, |item| {
            item.included
                && matches!(
                    item.status,
                    ImportConflictBatchPreviewStatus::Blocked
                        | ImportConflictBatchPreviewStatus::Failed
                )
        }),
        replace_count,
        skip_count: count_strategy(plan, ImportConflictBatchStrategy::Skip),
        keep_both_count: count_strategy(plan, ImportConflictBatchStrategy::KeepBoth),
        ask_per_item_count: count_strategy(plan, ImportConflictBatchStrategy::AskPerItem),
        trash_available: plan_trash_available(repo, plan),
        undo_available: true,
        can_apply,
        apply_blocked_reason: apply_blocked_reason(plan),
        replace_confirmation_required: replace_count > 0,
        replace_confirmation_summary: replace_summary(replace_count, request),
        items,
    }
}

pub(super) fn can_apply(plan: &[PlannedImportConflict]) -> bool {
    scoped_count(plan) > 0
        && count_plan(plan, |item| {
            item.included
                && matches!(
                    item.status,
                    ImportConflictBatchPreviewStatus::Blocked
                        | ImportConflictBatchPreviewStatus::Failed
                )
        }) == 0
        && count_plan(plan, |item| item.included && is_actionable(&item.status)) > 0
}

pub(super) fn apply_blocked_reason(plan: &[PlannedImportConflict]) -> Option<String> {
    if can_apply(plan) {
        return None;
    }
    if scoped_count(plan) == 0 {
        return Some("No selected conflicts can be applied".to_owned());
    }
    Some("One or more import conflicts are blocked".to_owned())
}

fn plan_row(
    repo: &Path,
    row: db::ImportConflictRow,
    included: bool,
    request: &ImportConflictBatchPreviewRequest,
    trash_available: bool,
) -> CoreResult<PlannedImportConflict> {
    let strategy = strategy_for(&row.conflict_type, request);
    let mut item = PlannedImportConflict {
        row,
        staging: None,
        existing: None,
        included,
        strategy,
        trash_available,
        final_relative_path: None,
        final_name: None,
        status: ImportConflictBatchPreviewStatus::Pending,
        reason: None,
    };
    if !included {
        return Ok(item);
    }
    if mark_non_pending_status(&mut item) {
        return Ok(item);
    }
    item.staging = Some(
        db::get_staging_file_snapshot(repo, item.row.staging_file_id)?
            .ok_or_else(|| CoreError::staging_recovery_required(item.row.incoming_path.clone()))?,
    );
    item.existing = load_existing(repo, item.row.existing_file_id)?;
    plan_pending_row(repo, &mut item)?;
    Ok(item)
}

fn load_existing(repo: &Path, existing_file_id: Option<i64>) -> CoreResult<Option<FileEntry>> {
    existing_file_id
        .map(|file_id| db::get_active_file_by_id(repo, file_id))
        .transpose()
}

fn mark_non_pending_status(item: &mut PlannedImportConflict) -> bool {
    match item.row.status {
        db::ImportConflictStatus::Pending => false,
        db::ImportConflictStatus::QueuedForPerItem => {
            item.status = ImportConflictBatchPreviewStatus::Pending;
            item.reason = Some("Conflict is queued for per-item handling".to_owned());
            true
        }
        db::ImportConflictStatus::Resolved => {
            item.status = ImportConflictBatchPreviewStatus::Pending;
            item.reason = Some("Conflict is already resolved".to_owned());
            true
        }
        db::ImportConflictStatus::Failed => {
            item.status = ImportConflictBatchPreviewStatus::Failed;
            item.reason = item
                .row
                .failure_reason
                .clone()
                .or_else(|| Some("Previous apply attempt failed".to_owned()));
            true
        }
    }
}

fn plan_pending_row(repo: &Path, item: &mut PlannedImportConflict) -> CoreResult<()> {
    match item.strategy {
        ImportConflictBatchStrategy::Skip | ImportConflictBatchStrategy::AskPerItem => {
            item.status = ImportConflictBatchPreviewStatus::Ready;
        }
        ImportConflictBatchStrategy::KeepBoth => {
            let staging = staging_snapshot(item)?;
            if staging.storage_mode == StorageMode::Indexed {
                block_item(item, "Index-only staging cannot be batch imported");
                return Ok(());
            }
            path::ensure_staging_file_matches(repo, &staging.path)?;
            let force_numbered = item.existing.is_some();
            let final_path =
                path::resolve_keep_both_path(repo, &item.row.target_path, force_numbered)?;
            set_final_path(repo, item, final_path)?;
            item.status = ImportConflictBatchPreviewStatus::Ready;
        }
        ImportConflictBatchStrategy::Replace => plan_replace(repo, item)?,
    }
    Ok(())
}

fn plan_replace(repo: &Path, item: &mut PlannedImportConflict) -> CoreResult<()> {
    let staging = staging_snapshot(item)?;
    if staging.storage_mode == StorageMode::Indexed {
        block_item(item, "Index-only staging cannot replace an existing file");
        return Ok(());
    }
    let Some(existing) = item.existing.as_ref() else {
        block_item(item, "Replace requires an active target file");
        return Ok(());
    };
    if existing.storage_mode == StorageMode::Indexed {
        block_item(item, "Index-only target cannot be replaced");
        return Ok(());
    }
    if !item.trash_available {
        block_item(item, "Trash unavailable");
        return Ok(());
    }
    path::ensure_staging_file_matches(repo, &staging.path)?;
    let existing_path = path::repo_relative_file_path(repo, &existing.path)?;
    path::ensure_existing_replace_target(&existing_path)?;
    set_final_path(repo, item, existing_path)?;
    item.status = ImportConflictBatchPreviewStatus::NeedsConfirmation;
    Ok(())
}

fn set_final_path(
    repo: &Path,
    item: &mut PlannedImportConflict,
    final_path: PathBuf,
) -> CoreResult<()> {
    let final_name = path::filename_from_path(&final_path)?;
    let final_relative_path = path::relative_repo_path(repo, &final_path)?;
    item.final_relative_path = Some(final_relative_path);
    item.final_name = Some(final_name);
    Ok(())
}

fn block_item(item: &mut PlannedImportConflict, reason: &str) {
    item.status = ImportConflictBatchPreviewStatus::Blocked;
    item.reason = Some(reason.to_owned());
}

fn staging_snapshot(item: &PlannedImportConflict) -> CoreResult<&FileEntry> {
    item.staging
        .as_ref()
        .ok_or_else(|| CoreError::staging_recovery_required(item.row.incoming_path.clone()))
}

fn preview_items(plan: &[PlannedImportConflict]) -> Vec<ImportConflictBatchPreviewItem> {
    plan.iter().map(preview_item).collect()
}

fn preview_item(item: &PlannedImportConflict) -> ImportConflictBatchPreviewItem {
    let actionable = item.included && is_actionable(&item.status);
    ImportConflictBatchPreviewItem {
        conflict_id: item.row.conflict_id.clone(),
        conflict_type: api_conflict_type(&item.row.conflict_type),
        existing_file_id: item.row.existing_file_id,
        existing_path: item.existing.as_ref().map(|entry| entry.path.clone()),
        incoming_path: item.row.incoming_path.clone(),
        target_path: item.final_relative_path.clone(),
        selected_strategy: item.strategy.clone(),
        status: item.status.clone(),
        will_replace: actionable && item.strategy == ImportConflictBatchStrategy::Replace,
        will_keep_both: actionable && item.strategy == ImportConflictBatchStrategy::KeepBoth,
        will_skip: actionable && item.strategy == ImportConflictBatchStrategy::Skip,
        will_ask_per_item: actionable && item.strategy == ImportConflictBatchStrategy::AskPerItem,
        index_only: item
            .existing
            .as_ref()
            .is_some_and(|entry| entry.storage_mode == StorageMode::Indexed),
        risk_summary: risk_summary(item),
        reason: item.reason.clone(),
    }
}

fn ensure_requested_conflicts_exist(
    rows: &[db::ImportConflictRow],
    requested_ids: &[String],
) -> CoreResult<()> {
    for conflict_id in requested_ids {
        if !rows.iter().any(|row| &row.conflict_id == conflict_id) {
            return Err(CoreError::file_not_found("conflict:missing"));
        }
    }
    Ok(())
}

fn should_include(
    row: &db::ImportConflictRow,
    requested_ids: &[String],
    selected_kinds: &[db::ImportConflictKind],
    apply_to_all_similar: bool,
) -> bool {
    if requested_ids
        .iter()
        .any(|conflict_id| conflict_id == &row.conflict_id)
    {
        return true;
    }
    apply_to_all_similar && selected_kinds.iter().any(|kind| kind == &row.conflict_type)
}

fn selected_conflict_kinds(
    rows: &[db::ImportConflictRow],
    requested_ids: &[String],
) -> Vec<db::ImportConflictKind> {
    let mut kinds = Vec::new();
    for row in rows {
        if !requested_ids
            .iter()
            .any(|conflict_id| conflict_id == &row.conflict_id)
        {
            continue;
        }
        if !kinds.iter().any(|kind| kind == &row.conflict_type) {
            kinds.push(row.conflict_type.clone());
        }
    }
    kinds
}

fn strategy_for(
    kind: &db::ImportConflictKind,
    request: &ImportConflictBatchPreviewRequest,
) -> ImportConflictBatchStrategy {
    match kind {
        db::ImportConflictKind::DuplicateHash => request.duplicate_strategy.clone(),
        db::ImportConflictKind::SameNameDifferentContent => request.same_name_strategy.clone(),
    }
}

fn count_strategy(plan: &[PlannedImportConflict], strategy: ImportConflictBatchStrategy) -> i64 {
    count_plan(plan, |item| {
        item.included && is_actionable(&item.status) && item.strategy == strategy
    })
}

fn scoped_count(plan: &[PlannedImportConflict]) -> i64 {
    count_plan(plan, |item| item.included)
}

fn count_plan(
    plan: &[PlannedImportConflict],
    predicate: impl Fn(&PlannedImportConflict) -> bool,
) -> i64 {
    plan.iter().filter(|item| predicate(item)).count() as i64
}

fn is_actionable(status: &ImportConflictBatchPreviewStatus) -> bool {
    matches!(
        status,
        ImportConflictBatchPreviewStatus::Ready
            | ImportConflictBatchPreviewStatus::NeedsConfirmation
    )
}

fn replace_summary(
    replace_count: i64,
    request: &ImportConflictBatchPreviewRequest,
) -> Option<String> {
    if replace_count == 0 {
        return None;
    }
    let scope = if request.apply_to_all_similar_conflicts {
        "all similar conflicts in this import"
    } else {
        "selected conflicts"
    };
    Some(format!(
        "Replace {replace_count} existing file(s). Scope: {scope}."
    ))
}

fn trash_available(repo: &Path) -> bool {
    let trash_pending = repo
        .join(super::AREA_MATRIX_DIR)
        .join(super::TRASH_PENDING_DIR);
    if trash_pending.exists() {
        return is_writable_dir(&trash_pending);
    }
    is_writable_dir(&repo.join(super::AREA_MATRIX_DIR))
}

fn plan_trash_available(repo: &Path, plan: &[PlannedImportConflict]) -> bool {
    plan.first()
        .map(|item| item.trash_available)
        .unwrap_or_else(|| trash_available(repo))
}

fn is_writable_dir(path: &Path) -> bool {
    path.metadata()
        .is_ok_and(|metadata| metadata.is_dir() && !metadata.permissions().readonly())
}
