//! Planning and detail payloads for external filesystem changes.

use std::{fs, path::Path};

use serde_json::json;

use crate::{
    db::{self, ExternalCreatedRow, ExternalModifiedRow, ExternalRemovedRow, ExternalRenamedRow},
    CoreError, CoreResult, ExternalEvent,
};

use super::{
    events::{category_for_relative_path, file_name_from_relative, resolve_file_event_path},
    snapshots::{
        ensure_path_absent, map_io_error, map_renamed_target_metadata_error,
        rename_source_is_absent, stable_file_snapshot,
    },
};

pub(super) struct CreatedPlan {
    pub(super) row: ExternalCreatedRow,
    pub(super) expectation: FilesystemExpectation,
}

pub(super) struct RenamedPlan {
    pub(super) row: Option<ExternalRenamedRow>,
    pub(super) file_id: i64,
    pub(super) target_path: String,
    pub(super) previous_category: String,
    pub(super) expectation: Option<FilesystemExpectation>,
}

pub(super) struct RemovedPlan {
    pub(super) row: Option<ExternalRemovedRow>,
    pub(super) expectation: FilesystemExpectation,
}

pub(super) struct ModifiedPlan {
    pub(super) row: ExternalModifiedRow,
    pub(super) expectation: FilesystemExpectation,
}

pub(super) enum ModifiedEventPlan {
    Created(CreatedPlan),
    Modified(ModifiedPlan),
    Unchanged(FilesystemExpectation),
}

#[derive(Clone, Debug)]
pub(super) enum FilesystemExpectation {
    Snapshot {
        path: String,
        size_bytes: i64,
        hash_sha256: String,
    },
    Absent {
        path: String,
    },
    Rename {
        source_path: String,
        target_path: String,
        size_bytes: i64,
        hash_sha256: String,
    },
}

struct ExternalRenameDetail<'a> {
    event_id: i64,
    from_path: &'a str,
    to_path: &'a str,
    from_name: &'a str,
    to_name: &'a str,
    from_category: &'a str,
    to_category: &'a str,
    hash_after: &'a str,
    size_after: i64,
}

pub(super) fn plan_created_event(
    repo: &Path,
    event: &ExternalEvent,
) -> CoreResult<Option<CreatedPlan>> {
    let Some(resolved) = resolve_file_event_path(repo, &event.path)? else {
        return Ok(None);
    };

    let metadata = fs::symlink_metadata(&resolved.absolute_path)
        .map_err(|error| map_io_error(error, &resolved.relative_path))?;
    if metadata.is_dir() {
        return Ok(None);
    }
    if !metadata.is_file() {
        return Err(CoreError::invalid_path(resolved.relative_path));
    }

    let snapshot = stable_file_snapshot(&resolved.absolute_path, &resolved.relative_path)?;
    let current_name = file_name_from_relative(&resolved.relative_path)?;
    let category = category_for_relative_path(&resolved.relative_path);
    let detail_json = external_create_detail(
        event.fs_event_id,
        &resolved.relative_path,
        &category,
        &snapshot.hash_sha256,
        snapshot.size_bytes,
    )?;

    let expectation = snapshot_expectation(&resolved.relative_path, &snapshot);
    Ok(Some(CreatedPlan {
        row: ExternalCreatedRow {
            path: resolved.relative_path,
            original_name: current_name.clone(),
            current_name,
            category,
            size_bytes: snapshot.size_bytes,
            hash_sha256: snapshot.hash_sha256,
            detail_json,
        },
        expectation,
    }))
}

pub(super) fn plan_renamed_event(
    repo: &Path,
    event: &ExternalEvent,
) -> CoreResult<Option<RenamedPlan>> {
    let Some(resolved) = resolve_file_event_path(repo, &event.path)? else {
        return Ok(None);
    };

    if let Some(target) = db::find_file_by_path_any_status(repo, &resolved.relative_path)? {
        if target.status == "active" {
            let previous_category = db::latest_external_rename_source_category(
                repo,
                target.id,
                event.fs_event_id,
                &resolved.relative_path,
            )?;
            if let Some(previous_category) = previous_category {
                return Ok(Some(RenamedPlan {
                    row: None,
                    file_id: target.id,
                    target_path: resolved.relative_path,
                    previous_category,
                    expectation: None,
                }));
            }
        }
        return Err(CoreError::conflict(resolved.relative_path));
    }

    let metadata = fs::symlink_metadata(&resolved.absolute_path)
        .map_err(|error| map_renamed_target_metadata_error(error, &resolved.relative_path))?;
    if metadata.is_dir() {
        return Ok(None);
    }
    if !metadata.is_file() {
        return Err(CoreError::invalid_path(resolved.relative_path));
    }

    let snapshot = stable_file_snapshot(&resolved.absolute_path, &resolved.relative_path)?;
    let current_name = file_name_from_relative(&resolved.relative_path)?;
    let category = category_for_relative_path(&resolved.relative_path);

    let candidates = db::find_external_rename_candidates_by_hash(
        repo,
        &snapshot.hash_sha256,
        &resolved.relative_path,
    )?;
    let candidate = match candidates.as_slice() {
        [candidate] => candidate,
        _ => return Err(CoreError::conflict(resolved.relative_path)),
    };
    if !rename_source_is_absent(repo, &candidate.path)? {
        return Err(CoreError::conflict(candidate.path.clone()));
    }
    let detail_json = external_rename_detail(ExternalRenameDetail {
        event_id: event.fs_event_id,
        from_path: &candidate.path,
        to_path: &resolved.relative_path,
        from_name: &candidate.current_name,
        to_name: &current_name,
        from_category: &candidate.category,
        to_category: &category,
        hash_after: &snapshot.hash_sha256,
        size_after: snapshot.size_bytes,
    })?;

    let expectation = FilesystemExpectation::Rename {
        source_path: candidate.path.clone(),
        target_path: resolved.relative_path.clone(),
        size_bytes: snapshot.size_bytes,
        hash_sha256: snapshot.hash_sha256.clone(),
    };
    Ok(Some(RenamedPlan {
        row: Some(ExternalRenamedRow {
            file_id: candidate.id,
            from_path: candidate.path.clone(),
            path: resolved.relative_path.clone(),
            current_name,
            category: category.clone(),
            size_bytes: snapshot.size_bytes,
            hash_sha256: snapshot.hash_sha256,
            expected_size_bytes: candidate.size_bytes,
            expected_hash_sha256: candidate.hash_sha256.clone(),
            detail_json,
        }),
        file_id: candidate.id,
        target_path: resolved.relative_path,
        previous_category: candidate.category.clone(),
        expectation: Some(expectation),
    }))
}

pub(super) fn plan_modified_event(
    repo: &Path,
    event: &ExternalEvent,
) -> CoreResult<Option<ModifiedEventPlan>> {
    let Some(resolved) = resolve_file_event_path(repo, &event.path)? else {
        return Ok(None);
    };

    let metadata = fs::symlink_metadata(&resolved.absolute_path)
        .map_err(|error| map_io_error(error, &resolved.relative_path))?;
    if metadata.is_dir() {
        return Ok(None);
    }
    if !metadata.is_file() {
        return Err(CoreError::invalid_path(resolved.relative_path));
    }

    let Some(file) = db::find_active_file_by_path(repo, &resolved.relative_path)? else {
        return plan_created_event(repo, event).map(|plan| plan.map(ModifiedEventPlan::Created));
    };
    let snapshot = stable_file_snapshot(&resolved.absolute_path, &resolved.relative_path)?;
    let expectation = snapshot_expectation(&resolved.relative_path, &snapshot);
    if file.hash_sha256 == snapshot.hash_sha256 && file.size_bytes == snapshot.size_bytes {
        return Ok(Some(ModifiedEventPlan::Unchanged(expectation)));
    }
    let detail_json = external_modified_detail(
        event.fs_event_id,
        &resolved.relative_path,
        &file.hash_sha256,
        &snapshot.hash_sha256,
        file.size_bytes,
        snapshot.size_bytes,
    )?;

    Ok(Some(ModifiedEventPlan::Modified(ModifiedPlan {
        row: ExternalModifiedRow {
            file_id: file.id,
            expected_path: file.path,
            expected_size_bytes: file.size_bytes,
            expected_hash_sha256: file.hash_sha256.clone(),
            size_bytes: snapshot.size_bytes,
            hash_sha256: snapshot.hash_sha256,
            detail_json,
        },
        expectation,
    })))
}

pub(super) fn plan_removed_event(
    repo: &Path,
    event: &ExternalEvent,
) -> CoreResult<Option<RemovedPlan>> {
    let Some(resolved) = resolve_file_event_path(repo, &event.path)? else {
        return Ok(None);
    };
    ensure_path_absent(&resolved.absolute_path, &resolved.relative_path)?;
    let expectation = FilesystemExpectation::Absent {
        path: resolved.relative_path.clone(),
    };

    let row = match db::find_active_file_by_path(repo, &resolved.relative_path)? {
        Some(file) => {
            let detail_json = external_removed_detail(event.fs_event_id, &resolved.relative_path)?;
            Some(ExternalRemovedRow {
                file_id: file.id,
                expected_path: file.path,
                expected_size_bytes: file.size_bytes,
                expected_hash_sha256: file.hash_sha256,
                detail_json,
            })
        }
        None => None,
    };

    Ok(Some(RemovedPlan { row, expectation }))
}

pub(super) fn revalidate_planned_filesystem_state(
    repo: &Path,
    expectations: &[FilesystemExpectation],
) -> CoreResult<()> {
    for expectation in expectations {
        match expectation {
            FilesystemExpectation::Snapshot {
                path,
                size_bytes,
                hash_sha256,
            } => ensure_snapshot_matches(repo, path, *size_bytes, hash_sha256)?,
            FilesystemExpectation::Absent { path } => {
                ensure_path_absent(&repo.join(path), path)?;
            }
            FilesystemExpectation::Rename {
                source_path,
                target_path,
                size_bytes,
                hash_sha256,
            } => {
                if !rename_source_is_absent(repo, source_path)? {
                    return Err(CoreError::conflict(source_path));
                }
                ensure_snapshot_matches(repo, target_path, *size_bytes, hash_sha256)?;
            }
        }
    }
    Ok(())
}

fn snapshot_expectation(
    path: &str,
    snapshot: &super::snapshots::StableFileSnapshot,
) -> FilesystemExpectation {
    FilesystemExpectation::Snapshot {
        path: path.to_owned(),
        size_bytes: snapshot.size_bytes,
        hash_sha256: snapshot.hash_sha256.clone(),
    }
}

fn ensure_snapshot_matches(
    repo: &Path,
    relative_path: &str,
    size_bytes: i64,
    hash_sha256: &str,
) -> CoreResult<()> {
    let snapshot = stable_file_snapshot(&repo.join(relative_path), relative_path)?;
    if snapshot.size_bytes != size_bytes || snapshot.hash_sha256 != hash_sha256 {
        return Err(CoreError::conflict(relative_path));
    }
    Ok(())
}

fn external_create_detail(
    event_id: i64,
    relative_path: &str,
    category: &str,
    hash_sha256: &str,
    size_bytes: i64,
) -> CoreResult<String> {
    serde_json::to_string(&json!({
        "event_id": event_id,
        "kind": "create",
        "path": relative_path,
        "category": category,
        "hash_after": hash_sha256,
        "size_bytes": size_bytes,
        "by": "external",
    }))
    .map_err(|error| CoreError::internal(error.to_string()))
}

fn external_rename_detail(detail: ExternalRenameDetail<'_>) -> CoreResult<String> {
    serde_json::to_string(&json!({
        "event_id": detail.event_id,
        "from_path": detail.from_path,
        "to_path": detail.to_path,
        "from_name": detail.from_name,
        "to_name": detail.to_name,
        "from_category": detail.from_category,
        "to_category": detail.to_category,
        "hash_after": detail.hash_after,
        "size_after": detail.size_after,
        "by": "external",
    }))
    .map_err(|error| CoreError::internal(error.to_string()))
}

fn external_modified_detail(
    event_id: i64,
    relative_path: &str,
    hash_before: &str,
    hash_after: &str,
    size_before: i64,
    size_after: i64,
) -> CoreResult<String> {
    serde_json::to_string(&json!({
        "event_id": event_id,
        "kind": "content",
        "path": relative_path,
        "hash_before": hash_before,
        "hash_after": hash_after,
        "size_before": size_before,
        "size_after": size_after,
        "by": "external",
    }))
    .map_err(|error| CoreError::internal(error.to_string()))
}

fn external_removed_detail(event_id: i64, relative_path: &str) -> CoreResult<String> {
    serde_json::to_string(&json!({
        "event_id": event_id,
        "path": relative_path,
        "hard": false,
        "by": "external",
    }))
    .map_err(|error| CoreError::internal(error.to_string()))
}
