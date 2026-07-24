//! External filesystem synchronization.

use std::{
    collections::{BTreeMap, BTreeSet},
    path::{Path, PathBuf},
};

mod events;
mod plans;
mod snapshots;

#[cfg(test)]
mod precondition_tests;

use events::{
    affected_node_for_event, category_for_relative_path, normalize_and_coalesce_events,
    should_skip_event, validate_event_id,
};
use plans::{
    plan_created_event, plan_modified_event, plan_removed_event, plan_renamed_event,
    revalidate_planned_filesystem_state, ModifiedEventPlan,
};

use crate::{
    db, overview, repo_path, ContentLocale, CoreResult, ExternalEvent, ExternalEventKind,
    ExternalSyncLocaleRecoveryPlan, ExternalSyncLocaleRecoveryReport, SyncResult,
};

pub(crate) fn sync_external_changes(
    repo_path: String,
    events: Vec<ExternalEvent>,
    content_locale: String,
) -> CoreResult<SyncResult> {
    crate::config::validate_content_locale(&content_locale)?;
    let repo = initialized_repo_path(&repo_path)?;
    db::ensure_repository_locale_allows_normal_mutation(&repo)?;
    let (normalized_events, max_sync_event_id) = normalize_and_coalesce_events(&repo, events)?;
    db::ensure_external_sync_receipts(&repo)?;
    let persisted_cursor = db::get_fs_event_cursor(&repo)?;
    let normalized_events = normalized_events
        .into_iter()
        .filter(|event| !persisted_cursor.is_some_and(|cursor| event.fs_event_id <= cursor))
        .collect::<Vec<_>>();
    let receipt_keys = normalized_events
        .iter()
        .map(|event| db::ExternalSyncReceiptKey {
            event_id: event.fs_event_id,
            kind: external_event_kind_name(&event.kind).to_owned(),
            path: event.path.clone(),
        })
        .collect::<Vec<_>>();
    let persisted_receipts =
        db::claim_external_sync_receipts(&repo, &receipt_keys, &content_locale)?;
    let mut events = Vec::new();
    let mut replayed_receipts = Vec::new();
    for (event, receipt) in normalized_events.into_iter().zip(persisted_receipts) {
        if let Some(receipt) = receipt {
            replayed_receipts.push(receipt);
        } else {
            events.push(event);
        }
    }
    let mut created_rows = Vec::new();
    let mut renamed_rows = Vec::new();
    let mut removed_rows = Vec::new();
    let mut modified_rows = Vec::new();
    let mut filesystem_expectations = Vec::new();
    let mut receipt_by_path = events
        .iter()
        .map(|event| {
            (
                event.path.clone(),
                db::ExternalSyncReceiptRow {
                    event_id: event.fs_event_id,
                    kind: external_event_kind_name(&event.kind).to_owned(),
                    path: event.path.clone(),
                    file_id: None,
                    previous_category: None,
                    current_category: None,
                    content_locale: content_locale.clone(),
                },
            )
        })
        .collect::<BTreeMap<_, _>>();
    let renamed_event_paths = events
        .iter()
        .filter(|event| event.kind == ExternalEventKind::Renamed)
        .map(|event| event.path.as_str())
        .collect::<BTreeSet<_>>();
    let deferred_sidecar_renames = renamed_event_paths
        .iter()
        .filter_map(|path| path.strip_suffix(".md"))
        .filter(|base_path| renamed_event_paths.contains(base_path))
        .map(str::to_owned)
        .collect::<BTreeSet<_>>();
    let mut rename_plans_by_target = BTreeMap::new();
    let mut renamed_file_ids = BTreeSet::new();
    let mut replayed_renamed_file_ids = BTreeSet::new();
    for receipt in &replayed_receipts {
        if receipt.kind == "renamed" {
            if let Some(file_id) = receipt.file_id {
                rename_plans_by_target.insert(receipt.path.clone(), file_id);
                replayed_renamed_file_ids.insert(file_id);
            }
        }
    }

    for event in &events {
        if event.kind != ExternalEventKind::Renamed
            || deferred_sidecar_renames.contains(event.path.strip_suffix(".md").unwrap_or(""))
            || should_skip_event(&repo, &event.path, &rename_plans_by_target)?
        {
            continue;
        }
        if let Some(mut plan) = plan_renamed_event(&repo, event)? {
            if let Some(receipt) = receipt_by_path.get_mut(&event.path) {
                receipt.file_id = Some(plan.file_id);
                receipt.previous_category = Some(plan.previous_category.clone());
                receipt.current_category = Some(category_for_relative_path(&plan.target_path));
            }
            rename_plans_by_target.insert(plan.target_path.clone(), plan.file_id);
            rename_plans_by_target.insert(event.path.clone(), plan.file_id);
            renamed_file_ids.insert(plan.file_id);
            if let Some(expectation) = plan.expectation.take() {
                filesystem_expectations.push(expectation);
            }
            if let Some(row) = plan.row {
                renamed_rows.push(row);
            }
        }
    }

    for event in &events {
        if should_skip_event(&repo, &event.path, &rename_plans_by_target)? {
            continue;
        }
        if let Some(node) = affected_node_for_event(&repo, event)? {
            if let Some(receipt) = receipt_by_path.get_mut(&event.path) {
                receipt.current_category = Some(node);
            }
        }
        match event.kind {
            ExternalEventKind::Created => {
                if let Some(plan) = plan_created_event(&repo, event)? {
                    if let Some(receipt) = receipt_by_path.get_mut(&event.path) {
                        receipt.current_category = Some(plan.row.category.clone());
                    }
                    filesystem_expectations.push(plan.expectation);
                    created_rows.push(plan.row);
                }
            }
            ExternalEventKind::Renamed => {
                if rename_plans_by_target.contains_key(&event.path) {
                    continue;
                }
                if let Some(mut plan) = plan_renamed_event(&repo, event)? {
                    if let Some(receipt) = receipt_by_path.get_mut(&event.path) {
                        receipt.file_id = Some(plan.file_id);
                        receipt.previous_category = Some(plan.previous_category.clone());
                        receipt.current_category =
                            Some(category_for_relative_path(&plan.target_path));
                    }
                    rename_plans_by_target.insert(plan.target_path.clone(), plan.file_id);
                    rename_plans_by_target.insert(event.path.clone(), plan.file_id);
                    renamed_file_ids.insert(plan.file_id);
                    if let Some(expectation) = plan.expectation.take() {
                        filesystem_expectations.push(expectation);
                    }
                    if let Some(row) = plan.row {
                        renamed_rows.push(row);
                    }
                }
            }
            ExternalEventKind::Removed => {
                if let Some(plan) = plan_removed_event(&repo, event)? {
                    if let Some(row) = plan.row.as_ref() {
                        if let Some(receipt) = receipt_by_path.get_mut(&event.path) {
                            receipt.file_id = Some(row.file_id);
                            receipt.previous_category = receipt.current_category.clone();
                        }
                    }
                    filesystem_expectations.push(plan.expectation);
                    removed_rows.push(plan.row);
                }
            }
            ExternalEventKind::Modified => {
                if let Some(plan) = plan_modified_event(&repo, event)? {
                    match plan {
                        ModifiedEventPlan::Created(plan) => {
                            if let Some(receipt) = receipt_by_path.get_mut(&event.path) {
                                receipt.current_category = Some(plan.row.category.clone());
                            }
                            filesystem_expectations.push(plan.expectation);
                            created_rows.push(plan.row);
                        }
                        ModifiedEventPlan::Modified(plan) => {
                            if let Some(receipt) = receipt_by_path.get_mut(&event.path) {
                                receipt.file_id = Some(plan.row.file_id);
                            }
                            filesystem_expectations.push(plan.expectation);
                            modified_rows.push(plan.row);
                        }
                        ModifiedEventPlan::Unchanged(expectation) => {
                            filesystem_expectations.push(expectation);
                        }
                    }
                }
            }
        }
    }

    removed_rows.retain(|row| match row {
        Some(row) => {
            !renamed_file_ids.contains(&row.file_id)
                && !replayed_renamed_file_ids.contains(&row.file_id)
        }
        None => true,
    });
    let removed_rows = removed_rows.into_iter().flatten().collect::<Vec<_>>();
    let receipts = receipt_by_path.into_values().collect();
    revalidate_planned_filesystem_state(&repo, &filesystem_expectations)?;
    let applied = db::apply_external_sync_batch(
        &repo,
        created_rows,
        renamed_rows,
        modified_rows,
        removed_rows,
        receipts,
    )?;
    let receipts = db::claim_external_sync_receipts(&repo, &receipt_keys, &content_locale)?
        .into_iter()
        .map(|receipt| {
            receipt.ok_or_else(|| {
                crate::CoreError::internal("external sync receipt locale provenance missing")
            })
        })
        .collect::<CoreResult<Vec<_>>>()?;
    regenerate_affected_overviews(&repo, &receipts)?;
    if let Some(cursor) = max_sync_event_id {
        db::set_fs_event_cursor(&repo, cursor)?;
    }

    Ok(SyncResult {
        detected_creates: applied.detected_creates,
        detected_renames: applied.detected_renames,
        detected_deletes: applied.detected_deletes,
        detected_modifies: applied.detected_modifies,
        errors: Vec::new(),
    })
}

pub(crate) fn prepare_external_sync_locale_recovery(
    repo_path: String,
) -> CoreResult<Option<ExternalSyncLocaleRecoveryPlan>> {
    let repo = initialized_repo_path(&repo_path)?;
    db::prepare_external_sync_locale_recovery(&repo)
}

pub(crate) fn resolve_external_sync_locale_recovery(
    repo_path: String,
    recovery_token: String,
    content_locale: ContentLocale,
) -> CoreResult<ExternalSyncLocaleRecoveryReport> {
    let repo = initialized_repo_path(&repo_path)?;
    db::resolve_external_sync_locale_recovery(&repo, &recovery_token, content_locale)
}

fn external_event_kind_name(kind: &ExternalEventKind) -> &'static str {
    match kind {
        ExternalEventKind::Created => "created",
        ExternalEventKind::Renamed => "renamed",
        ExternalEventKind::Removed => "removed",
        ExternalEventKind::Modified => "modified",
    }
}

/// Returns the latest processed filesystem event cursor.
///
/// # Errors
///
/// Returns `CoreError::RepoNotInitialized { path }` or `CoreError::Db { message }` when repository
/// metadata is absent or unreadable.
pub(crate) fn get_fs_event_cursor(repo_path: String) -> CoreResult<Option<i64>> {
    let repo = initialized_repo_path(&repo_path)?;
    db::get_fs_event_cursor(&repo)
}

/// Persists the latest processed filesystem event cursor.
///
/// # Errors
///
/// Returns `CoreError::InvalidPath { path }` for negative cursors,
/// `CoreError::RepoNotInitialized { path }` when metadata is absent, or `CoreError::Db { message }`
/// when SQLite persistence fails.
pub(crate) fn set_fs_event_cursor(repo_path: String, last_event_id: i64) -> CoreResult<()> {
    validate_event_id(last_event_id)?;
    let repo = initialized_repo_path(&repo_path)?;
    db::set_fs_event_cursor(&repo, last_event_id)
}

fn regenerate_affected_overviews(
    repo: &Path,
    receipts: &[db::ExternalSyncReceiptRow],
) -> CoreResult<()> {
    let locales = db::external_sync_overview_locales(receipts)?;
    match locales.root_locale {
        Some(root_locale) if !locales.node_locales.is_empty() => {
            overview::regenerate_external_sync_overviews(repo, &locales.node_locales, &root_locale)
        }
        _ => Ok(()),
    }
}

fn initialized_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    repo_path::validate_initialized_repo_path(repo_path.to_owned())?;
    Ok(PathBuf::from(repo_path))
}

#[cfg(test)]
mod tests {
    use std::fs::{self, File, FileTimes};

    use super::{
        events::normalize_and_coalesce_events,
        snapshots::{
            retry_stable_snapshot, snapshot_metadata_is_stable, SnapshotAttempt, StableFileSnapshot,
        },
    };
    use crate::{CoreError, ExternalEvent, ExternalEventKind};

    fn event(kind: ExternalEventKind, fs_event_id: i64) -> ExternalEvent {
        ExternalEvent {
            path: "docs/item.txt".to_owned(),
            kind,
            fs_event_id,
        }
    }

    fn coalesced_event(events: Vec<ExternalEvent>) -> ExternalEvent {
        let repo = tempfile::tempdir().expect("create temporary repository directory");
        let (mut events, _) = normalize_and_coalesce_events(repo.path(), events)
            .expect("normalize and coalesce events");
        assert_eq!(events.len(), 1);
        events.remove(0)
    }

    #[test]
    fn coalescing_orders_removed_then_created_by_event_id() {
        let event = coalesced_event(vec![
            event(ExternalEventKind::Created, 20),
            event(ExternalEventKind::Removed, 10),
        ]);

        assert_eq!(event.kind, ExternalEventKind::Created);
        assert_eq!(event.fs_event_id, 20);
    }

    #[test]
    fn coalescing_orders_created_then_removed_by_event_id() {
        let event = coalesced_event(vec![
            event(ExternalEventKind::Removed, 20),
            event(ExternalEventKind::Created, 10),
        ]);

        assert_eq!(event.kind, ExternalEventKind::Removed);
        assert_eq!(event.fs_event_id, 20);
    }

    #[test]
    fn coalescing_orders_renamed_then_removed_by_event_id() {
        let event = coalesced_event(vec![
            event(ExternalEventKind::Removed, 20),
            event(ExternalEventKind::Renamed, 10),
        ]);

        assert_eq!(event.kind, ExternalEventKind::Removed);
        assert_eq!(event.fs_event_id, 20);
    }

    #[test]
    fn coalescing_preserves_input_order_for_equal_event_ids() {
        let created_last = coalesced_event(vec![
            event(ExternalEventKind::Removed, 10),
            event(ExternalEventKind::Created, 10),
        ]);
        let removed_last = coalesced_event(vec![
            event(ExternalEventKind::Created, 10),
            event(ExternalEventKind::Removed, 10),
        ]);

        assert_eq!(created_last.kind, ExternalEventKind::Created);
        assert_eq!(removed_last.kind, ExternalEventKind::Removed);
    }

    #[test]
    fn coalescing_modified_only_advances_the_retained_watermark() {
        let event = coalesced_event(vec![
            event(ExternalEventKind::Created, 10),
            event(ExternalEventKind::Modified, 30),
            event(ExternalEventKind::Modified, 20),
        ]);

        assert_eq!(event.kind, ExternalEventKind::Created);
        assert_eq!(event.fs_event_id, 30);
    }

    #[test]
    fn stable_file_snapshot_retries_after_change() {
        let mut attempts = 0;
        let snapshot = retry_stable_snapshot("docs/item.txt", || {
            attempts += 1;
            if attempts == 1 {
                Ok(SnapshotAttempt::Changed)
            } else {
                Ok(SnapshotAttempt::Stable(StableFileSnapshot {
                    size_bytes: 3,
                    hash_sha256: "abc".to_owned(),
                }))
            }
        })
        .expect("second stable snapshot attempt should succeed");

        assert_eq!(attempts, 2);
        assert_eq!(snapshot.size_bytes, 3);
        assert_eq!(snapshot.hash_sha256, "abc");
    }

    #[test]
    fn stable_file_snapshot_rejects_continuous_changes() {
        let result = retry_stable_snapshot("docs/item.txt", || Ok(SnapshotAttempt::Changed));

        assert!(matches!(result, Err(CoreError::Conflict { .. })));
    }

    #[cfg(unix)]
    #[test]
    fn stable_file_snapshot_detects_same_metadata_atomic_replacement() {
        use std::os::unix::fs::MetadataExt;

        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("stable.txt");
        let replacement = directory.path().join("replacement.txt");
        fs::write(&path, b"old!").expect("write original file");
        fs::write(&replacement, b"new!").expect("write replacement file");

        let open_file = File::open(&path).expect("open original file handle");
        let before = open_file.metadata().expect("read original metadata");
        File::options()
            .write(true)
            .open(&replacement)
            .expect("open replacement file")
            .set_times(
                FileTimes::new()
                    .set_modified(before.modified().expect("read original modification time")),
            )
            .expect("align replacement modification time");
        fs::rename(&replacement, &path).expect("atomically replace original path");

        let after = open_file.metadata().expect("read open-handle metadata");
        let path_after = fs::symlink_metadata(&path).expect("read final path metadata");
        assert_eq!(before.len(), after.len());
        assert_eq!(after.len(), path_after.len());
        assert_eq!(
            before.modified().expect("read initial modification time"),
            after
                .modified()
                .expect("read open-handle modification time")
        );
        assert_eq!(
            after
                .modified()
                .expect("read open-handle modification time"),
            path_after
                .modified()
                .expect("read final path modification time")
        );
        assert_ne!(
            (after.dev(), after.ino()),
            (path_after.dev(), path_after.ino())
        );
        assert!(
            !snapshot_metadata_is_stable(&before, &after, &path_after, "docs/item.txt")
                .expect("compare stable snapshot metadata")
        );
    }
}
