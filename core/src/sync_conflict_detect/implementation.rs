use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};

use serde_json::Value;

use crate::{db, repo_path, CoreError, CoreResult};

use super::{
    paths::{
        conflict_copy_paths, inspect_untracked_file, original_path_for_conflicted_copy,
        relative_repo_path, sha256_file,
    },
    SyncConflict, SyncConflictAffectedFile, SyncConflictFileRole, SyncConflictSeverity,
    SyncConflictStatus, SyncConflictType,
};

const WATCHER_HEALTH_KEY: &str = "platform_watcher_health";

#[derive(Clone)]
struct FileSnapshot {
    file_id: i64,
    relative_path: String,
    current_name: String,
    db_size_bytes: i64,
    db_hash_sha256: String,
    db_updated_at: i64,
    fs_size_bytes: Option<i64>,
    fs_modified_at: Option<i64>,
    fs_hash_sha256: Option<String>,
}

struct ConflictDraft {
    conflict_id: String,
    conflict_type: SyncConflictType,
    severity: SyncConflictSeverity,
    primary_path: String,
    affected_files: Vec<SyncConflictAffectedFile>,
    source_provider: Option<String>,
    summary: String,
}

struct SourceState {
    provider: Option<String>,
    modified_paths: BTreeSet<String>,
}

pub(super) fn detect_sync_conflicts(repo_path: String) -> CoreResult<Vec<SyncConflict>> {
    let repo = initialized_repo_path(&repo_path)?;
    let detected_at = chrono::Utc::now().timestamp();
    let source = load_source_state(&repo)?;
    let snapshots = load_file_snapshots(&repo)?;
    let mut drafts = Vec::new();

    drafts.extend(missing_version_conflicts(&snapshots));
    drafts.extend(metadata_mismatch_conflicts(
        &snapshots,
        &source.modified_paths,
    ));
    drafts.extend(same_name_conflicts(
        &repo,
        &snapshots,
        source.provider.clone(),
    )?);
    drafts.extend(concurrent_modification_conflicts(&snapshots, &source));

    let mut conflicts: Vec<SyncConflict> = dedupe_conflicts(drafts)
        .into_iter()
        .map(|draft| finalize_conflict(draft, detected_at))
        .collect();
    conflicts.sort_by(compare_conflicts);
    persist_conflict_state(&repo, &conflicts, detected_at)?;
    Ok(conflicts)
}

fn initialized_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    repo_path::validate_initialized_repo_path(repo_path.to_owned())
        .map_err(normalize_metadata_error)?;
    Ok(PathBuf::from(repo_path))
}

fn load_source_state(repo: &Path) -> CoreResult<SourceState> {
    let Some((payload, _)) = db::load_repo_config_record(repo, WATCHER_HEALTH_KEY)? else {
        return Ok(SourceState {
            provider: None,
            modified_paths: BTreeSet::new(),
        });
    };
    let value: Value = serde_json::from_str(&payload)
        .map_err(|_| CoreError::db("watcher health metadata is invalid"))?;
    Ok(SourceState {
        provider: value
            .get("backend")
            .and_then(Value::as_str)
            .filter(|backend| !backend.trim().is_empty())
            .map(str::to_owned),
        modified_paths: modified_paths_from_watcher_state(&value),
    })
}

fn modified_paths_from_watcher_state(value: &Value) -> BTreeSet<String> {
    value
        .get("recent_events")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|event| event.get("kind").and_then(Value::as_str) == Some("Modified"))
        .filter_map(|event| event.get("path").and_then(Value::as_str))
        .map(str::to_owned)
        .collect()
}

fn load_file_snapshots(repo: &Path) -> CoreResult<Vec<FileSnapshot>> {
    db::list_active_sync_conflict_files(repo)?
        .into_iter()
        .map(|row| snapshot_file(repo, row))
        .collect()
}

fn snapshot_file(repo: &Path, row: db::ActiveSyncConflictFile) -> CoreResult<FileSnapshot> {
    let absolute_path = repo.join(&row.path);
    match fs::metadata(&absolute_path) {
        Ok(metadata) if metadata.is_file() => Ok(FileSnapshot {
            file_id: row.id,
            relative_path: row.path,
            current_name: row.current_name,
            db_size_bytes: row.size_bytes,
            db_hash_sha256: row.hash_sha256,
            db_updated_at: row.updated_at,
            fs_size_bytes: Some(metadata.len() as i64),
            fs_modified_at: super::paths::modified_at_from_metadata(&metadata)?,
            fs_hash_sha256: Some(sha256_file(&absolute_path)?),
        }),
        Ok(_) => Err(CoreError::conflict(row.path)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(FileSnapshot {
            file_id: row.id,
            relative_path: row.path,
            current_name: row.current_name,
            db_size_bytes: row.size_bytes,
            db_hash_sha256: row.hash_sha256,
            db_updated_at: row.updated_at,
            fs_size_bytes: None,
            fs_modified_at: None,
            fs_hash_sha256: None,
        }),
        Err(error) => Err(super::paths::map_io_error(error)),
    }
}

fn missing_version_conflicts(snapshots: &[FileSnapshot]) -> Vec<ConflictDraft> {
    snapshots
        .iter()
        .filter(|snapshot| snapshot.fs_hash_sha256.is_none())
        .map(|snapshot| ConflictDraft {
            conflict_id: format!("sync-conflict:missing:{}", snapshot.relative_path),
            conflict_type: SyncConflictType::MissingVersion,
            severity: SyncConflictSeverity::High,
            primary_path: snapshot.relative_path.clone(),
            affected_files: vec![missing_file(snapshot)],
            source_provider: None,
            summary: format!(
                "Missing version requires review: {}",
                snapshot.relative_path
            ),
        })
        .collect()
}

fn metadata_mismatch_conflicts(
    snapshots: &[FileSnapshot],
    concurrent_paths: &BTreeSet<String>,
) -> Vec<ConflictDraft> {
    snapshots
        .iter()
        .filter(|snapshot| {
            metadata_differs(snapshot) && !concurrent_paths.contains(&snapshot.relative_path)
        })
        .map(|snapshot| ConflictDraft {
            conflict_id: format!("sync-conflict:metadata:{}", snapshot.relative_path),
            conflict_type: SyncConflictType::MetadataMismatch,
            severity: SyncConflictSeverity::Medium,
            primary_path: snapshot.relative_path.clone(),
            affected_files: vec![
                db_file(snapshot),
                fs_file(snapshot, SyncConflictFileRole::Incoming),
            ],
            source_provider: None,
            summary: format!(
                "Filesystem metadata differs from AreaMatrix state: {}",
                snapshot.relative_path
            ),
        })
        .collect()
}

fn same_name_conflicts(
    repo: &Path,
    snapshots: &[FileSnapshot],
    provider: Option<String>,
) -> CoreResult<Vec<ConflictDraft>> {
    let snapshots_by_path = snapshots
        .iter()
        .map(|snapshot| (snapshot.relative_path.as_str(), snapshot))
        .collect::<BTreeMap<_, _>>();
    let mut drafts = Vec::new();

    for path in conflict_copy_paths(repo)? {
        let draft = same_name_conflict_for_path(repo, &path, snapshots, &snapshots_by_path)?;
        if let Some(mut draft) = draft {
            draft.source_provider = provider.clone();
            drafts.push(draft);
        }
    }

    Ok(drafts)
}

fn same_name_conflict_for_path(
    repo: &Path,
    path: &Path,
    snapshots: &[FileSnapshot],
    snapshots_by_path: &BTreeMap<&str, &FileSnapshot>,
) -> CoreResult<Option<ConflictDraft>> {
    let relative_path = relative_repo_path(repo, path)?;
    let Some(primary_path) = original_path_for_conflicted_copy(&relative_path) else {
        return Err(CoreError::conflict(relative_path));
    };
    let Some(existing) = snapshots
        .iter()
        .find(|snapshot| snapshot.relative_path == primary_path)
    else {
        return Ok(None);
    };
    let conflict_copy = if let Some(snapshot) = snapshots_by_path.get(relative_path.as_str()) {
        fs_file(snapshot, SyncConflictFileRole::ConflictCopy)
    } else {
        inspect_untracked_file(path, &relative_path)?
    };
    if existing.fs_hash_sha256.as_deref() == conflict_copy.hash_sha256.as_deref() {
        return Ok(None);
    }

    Ok(Some(ConflictDraft {
        conflict_id: format!("sync-conflict:same-name:{}", primary_path),
        conflict_type: SyncConflictType::SameNameDifferentContent,
        severity: SyncConflictSeverity::High,
        primary_path,
        affected_files: vec![
            fs_file(existing, SyncConflictFileRole::Existing),
            conflict_copy,
        ],
        source_provider: None,
        summary: format!(
            "Same name has multiple different versions: {}",
            existing.current_name
        ),
    }))
}

fn concurrent_modification_conflicts(
    snapshots: &[FileSnapshot],
    source: &SourceState,
) -> Vec<ConflictDraft> {
    snapshots
        .iter()
        .filter(|snapshot| {
            metadata_differs(snapshot) && source.modified_paths.contains(&snapshot.relative_path)
        })
        .map(|snapshot| ConflictDraft {
            conflict_id: format!("sync-conflict:concurrent:{}", snapshot.relative_path),
            conflict_type: SyncConflictType::ConcurrentModification,
            severity: SyncConflictSeverity::High,
            primary_path: snapshot.relative_path.clone(),
            affected_files: vec![
                db_file(snapshot),
                fs_file(snapshot, SyncConflictFileRole::Incoming),
            ],
            source_provider: source.provider.clone(),
            summary: format!(
                "Concurrent modification requires review: {}",
                snapshot.relative_path
            ),
        })
        .collect()
}

fn metadata_differs(snapshot: &FileSnapshot) -> bool {
    let Some(fs_hash) = snapshot.fs_hash_sha256.as_deref() else {
        return false;
    };
    fs_hash != snapshot.db_hash_sha256 || snapshot.fs_size_bytes != Some(snapshot.db_size_bytes)
}

fn db_file(snapshot: &FileSnapshot) -> SyncConflictAffectedFile {
    SyncConflictAffectedFile {
        path: snapshot.relative_path.clone(),
        file_id: Some(snapshot.file_id),
        role: SyncConflictFileRole::Existing,
        size_bytes: Some(snapshot.db_size_bytes),
        modified_at: Some(snapshot.db_updated_at),
        hash_sha256: Some(snapshot.db_hash_sha256.clone()),
        source_platform: Some("AreaMatrix metadata".to_owned()),
    }
}

fn fs_file(snapshot: &FileSnapshot, role: SyncConflictFileRole) -> SyncConflictAffectedFile {
    SyncConflictAffectedFile {
        path: snapshot.relative_path.clone(),
        file_id: Some(snapshot.file_id),
        role,
        size_bytes: snapshot.fs_size_bytes,
        modified_at: snapshot.fs_modified_at,
        hash_sha256: snapshot.fs_hash_sha256.clone(),
        source_platform: Some("filesystem".to_owned()),
    }
}

fn missing_file(snapshot: &FileSnapshot) -> SyncConflictAffectedFile {
    SyncConflictAffectedFile {
        path: snapshot.relative_path.clone(),
        file_id: Some(snapshot.file_id),
        role: SyncConflictFileRole::Missing,
        size_bytes: Some(snapshot.db_size_bytes),
        modified_at: Some(snapshot.db_updated_at),
        hash_sha256: Some(snapshot.db_hash_sha256.clone()),
        source_platform: Some("AreaMatrix metadata".to_owned()),
    }
}

fn dedupe_conflicts(drafts: Vec<ConflictDraft>) -> Vec<ConflictDraft> {
    let mut by_id = BTreeMap::new();
    for draft in drafts {
        by_id
            .entry(draft.conflict_id.clone())
            .and_modify(|existing: &mut ConflictDraft| merge_conflict(existing, &draft))
            .or_insert(draft);
    }
    by_id.into_values().collect()
}

fn merge_conflict(existing: &mut ConflictDraft, incoming: &ConflictDraft) {
    if severity_rank(&incoming.severity) > severity_rank(&existing.severity) {
        existing.severity = incoming.severity.clone();
    }
    for file in &incoming.affected_files {
        if !existing
            .affected_files
            .iter()
            .any(|existing_file| same_affected_file(existing_file, file))
        {
            existing.affected_files.push(file.clone());
        }
    }
}

fn same_affected_file(left: &SyncConflictAffectedFile, right: &SyncConflictAffectedFile) -> bool {
    left.path == right.path && left.role == right.role && left.file_id == right.file_id
}

fn finalize_conflict(draft: ConflictDraft, detected_at: i64) -> SyncConflict {
    let version_count = draft.affected_files.len() as i64;
    SyncConflict {
        conflict_id: draft.conflict_id,
        conflict_type: draft.conflict_type,
        severity: draft.severity,
        status: SyncConflictStatus::NeedsReview,
        primary_path: draft.primary_path,
        affected_files: draft.affected_files,
        version_count,
        source_provider: draft.source_provider,
        detected_at: Some(detected_at),
        summary: Some(draft.summary),
    }
}

fn compare_conflicts(left: &SyncConflict, right: &SyncConflict) -> std::cmp::Ordering {
    severity_rank(&right.severity)
        .cmp(&severity_rank(&left.severity))
        .then_with(|| {
            right
                .detected_at
                .unwrap_or_default()
                .cmp(&left.detected_at.unwrap_or_default())
        })
        .then_with(|| left.primary_path.cmp(&right.primary_path))
}

fn severity_rank(severity: &SyncConflictSeverity) -> u8 {
    match severity {
        SyncConflictSeverity::Low => 0,
        SyncConflictSeverity::Medium => 1,
        SyncConflictSeverity::High => 2,
    }
}

fn persist_conflict_state(
    repo: &Path,
    conflicts: &[SyncConflict],
    detected_at: i64,
) -> CoreResult<()> {
    let serialized = serde_json::to_string(conflicts)
        .map_err(|_| CoreError::db("sync conflict state metadata is invalid"))?;
    db::replace_sync_conflict_state(repo, &serialized, detected_at)
        .map_err(normalize_metadata_error)
}

fn normalize_metadata_error(error: CoreError) -> CoreError {
    match error {
        CoreError::Io { .. } | CoreError::PermissionDenied { .. } => {
            CoreError::io("sync conflict state metadata unavailable")
        }
        CoreError::RepoNotInitialized { .. } => {
            CoreError::db("sync conflict state requires initialized metadata")
        }
        other => other,
    }
}
