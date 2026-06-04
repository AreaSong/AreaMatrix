use std::{
    fs,
    path::{Path, PathBuf},
};

use sha2::{Digest, Sha256};

use crate::{CoreError, CoreResult, SyncConflict, SyncConflictAffectedFile, SyncConflictFileRole};

use super::{
    logical_change_log_action, IncomingReplacement, ResolutionPlan, SyncConflictReplacePlan,
    SyncConflictResolutionStrategy, SyncConflictVersionImpact,
};

const TRASH_TARGET: &str = "Trash";

pub(super) fn build_resolution_plan(
    conflict: &SyncConflict,
    resolution: SyncConflictResolutionStrategy,
    trash_available: bool,
) -> CoreResult<ResolutionPlan> {
    match resolution {
        SyncConflictResolutionStrategy::KeepBoth | SyncConflictResolutionStrategy::UseExisting => {
            non_destructive_plan(conflict, resolution, trash_available)
        }
        SyncConflictResolutionStrategy::UseIncoming => {
            use_incoming_plan(conflict, resolution, trash_available)
        }
    }
}

pub(super) fn trash_available() -> CoreResult<bool> {
    let Some(home) = std::env::var_os("HOME") else {
        return Ok(false);
    };
    let trash_dir = PathBuf::from(home).join(".Trash");
    if trash_dir.try_exists().map_err(map_preflight_error)? {
        return writable_dir(&trash_dir);
    }
    match trash_dir.parent() {
        Some(parent) => writable_dir(parent),
        None => Ok(false),
    }
}

fn non_destructive_plan(
    conflict: &SyncConflict,
    resolution: SyncConflictResolutionStrategy,
    trash_available: bool,
) -> CoreResult<ResolutionPlan> {
    let canonical_path = canonical_path(conflict);
    let change_log_action = logical_change_log_action(&resolution);
    Ok(ResolutionPlan {
        conflict_id: conflict.conflict_id.clone(),
        resolution: resolution.clone(),
        version_impacts: non_destructive_impacts(conflict, canonical_path.as_deref()),
        kept_paths: visible_paths(conflict),
        retained_paths: retained_paths(conflict, canonical_path.as_deref()),
        planned_trash_paths: Vec::new(),
        affected_file_ids: affected_file_ids(conflict),
        canonical_path,
        change_log_action,
        destructive: false,
        requires_replace_confirmation: false,
        trash_required: false,
        trash_available,
        can_apply: true,
        blocked_reason: None,
        preview_token: Some(preview_token(conflict, &resolution, trash_available)?),
        replace_plan: None,
        replacement: None,
    })
}

fn use_incoming_plan(
    conflict: &SyncConflict,
    resolution: SyncConflictResolutionStrategy,
    trash_available: bool,
) -> CoreResult<ResolutionPlan> {
    let change_log_action = logical_change_log_action(&resolution);
    let Some(replacement) = incoming_replacement(conflict) else {
        return Ok(blocked_incoming_plan(
            conflict,
            resolution,
            trash_available,
            "replace plan is unavailable",
        ));
    };
    let trash_blocked = replacement.trash_existing && !trash_available;
    let blocked_reason = if trash_blocked {
        Some("Trash unavailable".to_owned())
    } else {
        Some("replace confirmation is required".to_owned())
    };
    let replace_plan = replace_plan(&replacement, &change_log_action);
    let planned_trash_paths = if replacement.trash_existing {
        vec![replacement.existing_path.clone()]
    } else {
        Vec::new()
    };

    Ok(ResolutionPlan {
        conflict_id: conflict.conflict_id.clone(),
        resolution: resolution.clone(),
        version_impacts: incoming_impacts(conflict, &replacement),
        kept_paths: vec![replacement.canonical_path.clone()],
        retained_paths: Vec::new(),
        planned_trash_paths,
        affected_file_ids: affected_file_ids(conflict),
        canonical_path: Some(replacement.canonical_path.clone()),
        change_log_action,
        destructive: true,
        requires_replace_confirmation: true,
        trash_required: replacement.trash_existing,
        trash_available,
        can_apply: false,
        blocked_reason,
        preview_token: if trash_blocked {
            None
        } else {
            Some(preview_token(conflict, &resolution, trash_available)?)
        },
        replace_plan: Some(replace_plan),
        replacement: Some(replacement),
    })
}

fn blocked_incoming_plan(
    conflict: &SyncConflict,
    resolution: SyncConflictResolutionStrategy,
    trash_available: bool,
    reason: &str,
) -> ResolutionPlan {
    ResolutionPlan {
        conflict_id: conflict.conflict_id.clone(),
        resolution: resolution.clone(),
        version_impacts: blocked_impacts(conflict, reason),
        kept_paths: visible_paths(conflict),
        retained_paths: retained_paths(conflict, canonical_path(conflict).as_deref()),
        planned_trash_paths: Vec::new(),
        affected_file_ids: affected_file_ids(conflict),
        canonical_path: canonical_path(conflict),
        change_log_action: logical_change_log_action(&resolution),
        destructive: true,
        requires_replace_confirmation: true,
        trash_required: true,
        trash_available,
        can_apply: false,
        blocked_reason: Some(reason.to_owned()),
        preview_token: None,
        replace_plan: None,
        replacement: None,
    }
}

fn incoming_replacement(conflict: &SyncConflict) -> Option<IncomingReplacement> {
    let existing = existing_version(conflict)?;
    let incoming = incoming_version(conflict)?;
    let affected_file_id = existing.file_id?;
    let incoming_size_bytes = incoming.size_bytes?;
    let incoming_hash_sha256 = incoming.hash_sha256.clone()?;
    let canonical_path = existing.path.clone();
    let move_incoming_to_canonical = incoming.path != canonical_path;
    Some(IncomingReplacement {
        existing_path: existing.path.clone(),
        incoming_path: incoming.path.clone(),
        canonical_path,
        affected_file_id,
        existing_hash_sha256: existing.hash_sha256.clone(),
        incoming_size_bytes,
        incoming_hash_sha256,
        move_incoming_to_canonical,
        trash_existing: move_incoming_to_canonical,
    })
}

fn replace_plan(
    replacement: &IncomingReplacement,
    change_log_action: &str,
) -> SyncConflictReplacePlan {
    SyncConflictReplacePlan {
        old_path: replacement.existing_path.clone(),
        new_path: replacement.incoming_path.clone(),
        old_hash_sha256: replacement.existing_hash_sha256.clone(),
        new_hash_sha256: Some(replacement.incoming_hash_sha256.clone()),
        affected_file_id: Some(replacement.affected_file_id),
        backup_target: replacement.trash_existing.then(|| TRASH_TARGET.to_owned()),
        database_update: "canonical record will point to incoming file".to_owned(),
        change_log_action: change_log_action.to_owned(),
        recovery_note: "existing file must remain recoverable".to_owned(),
    }
}

fn non_destructive_impacts(
    conflict: &SyncConflict,
    canonical_path: Option<&str>,
) -> Vec<SyncConflictVersionImpact> {
    conflict
        .affected_files
        .iter()
        .map(|file| SyncConflictVersionImpact {
            path: file.path.clone(),
            file_id: file.file_id,
            role: file.role.clone(),
            will_keep: file.role != SyncConflictFileRole::Missing,
            will_be_canonical: canonical_path == Some(file.path.as_str())
                && file.role == SyncConflictFileRole::Existing,
            will_remain_user_visible: file.role != SyncConflictFileRole::Missing,
            will_move_to_trash: false,
            recovery_target: None,
            reason: missing_reason(file),
        })
        .collect()
}

fn incoming_impacts(
    conflict: &SyncConflict,
    replacement: &IncomingReplacement,
) -> Vec<SyncConflictVersionImpact> {
    conflict
        .affected_files
        .iter()
        .map(|file| {
            let is_existing = file.path == replacement.existing_path
                && file.role == SyncConflictFileRole::Existing;
            let is_incoming = file.path == replacement.incoming_path
                && matches!(
                    file.role,
                    SyncConflictFileRole::Incoming | SyncConflictFileRole::ConflictCopy
                );
            SyncConflictVersionImpact {
                path: file.path.clone(),
                file_id: file.file_id,
                role: file.role.clone(),
                will_keep: !is_existing && file.role != SyncConflictFileRole::Missing,
                will_be_canonical: is_incoming,
                will_remain_user_visible: is_incoming,
                will_move_to_trash: is_existing && replacement.trash_existing,
                recovery_target: (is_existing && replacement.trash_existing)
                    .then(|| TRASH_TARGET.to_owned()),
                reason: incoming_impact_reason(file, is_existing, is_incoming),
            }
        })
        .collect()
}

fn blocked_impacts(conflict: &SyncConflict, reason: &str) -> Vec<SyncConflictVersionImpact> {
    conflict
        .affected_files
        .iter()
        .map(|file| SyncConflictVersionImpact {
            path: file.path.clone(),
            file_id: file.file_id,
            role: file.role.clone(),
            will_keep: file.role != SyncConflictFileRole::Missing,
            will_be_canonical: file.role == SyncConflictFileRole::Existing,
            will_remain_user_visible: file.role != SyncConflictFileRole::Missing,
            will_move_to_trash: false,
            recovery_target: None,
            reason: Some(reason.to_owned()),
        })
        .collect()
}

fn incoming_impact_reason(
    file: &SyncConflictAffectedFile,
    is_existing: bool,
    is_incoming: bool,
) -> Option<String> {
    if file.role == SyncConflictFileRole::Missing {
        Some("missing version cannot be made visible".to_owned())
    } else if is_existing {
        Some("existing version will move to Trash after confirmation".to_owned())
    } else if is_incoming {
        Some("incoming version will become canonical".to_owned())
    } else {
        Some("unselected version is outside this replace plan".to_owned())
    }
}

fn missing_reason(file: &SyncConflictAffectedFile) -> Option<String> {
    (file.role == SyncConflictFileRole::Missing)
        .then(|| "missing version cannot be made visible".to_owned())
}

fn canonical_path(conflict: &SyncConflict) -> Option<String> {
    existing_version(conflict)
        .map(|file| file.path.clone())
        .or_else(|| Some(conflict.primary_path.clone()))
}

fn existing_version(conflict: &SyncConflict) -> Option<&SyncConflictAffectedFile> {
    conflict
        .affected_files
        .iter()
        .find(|file| file.role == SyncConflictFileRole::Existing)
}

fn incoming_version(conflict: &SyncConflict) -> Option<&SyncConflictAffectedFile> {
    conflict.affected_files.iter().find(|file| {
        matches!(
            file.role,
            SyncConflictFileRole::Incoming | SyncConflictFileRole::ConflictCopy
        )
    })
}

fn visible_paths(conflict: &SyncConflict) -> Vec<String> {
    let mut paths = Vec::new();
    for file in &conflict.affected_files {
        if file.role != SyncConflictFileRole::Missing && !paths.contains(&file.path) {
            paths.push(file.path.clone());
        }
    }
    paths
}

fn retained_paths(conflict: &SyncConflict, canonical_path: Option<&str>) -> Vec<String> {
    visible_paths(conflict)
        .into_iter()
        .filter(|path| Some(path.as_str()) != canonical_path)
        .collect()
}

fn affected_file_ids(conflict: &SyncConflict) -> Vec<i64> {
    let mut ids = Vec::new();
    for id in conflict
        .affected_files
        .iter()
        .filter_map(|file| file.file_id)
    {
        if !ids.contains(&id) {
            ids.push(id);
        }
    }
    ids
}

fn preview_token(
    conflict: &SyncConflict,
    resolution: &SyncConflictResolutionStrategy,
    trash_available: bool,
) -> CoreResult<String> {
    let payload = serde_json::to_string(&(conflict, resolution, trash_available))
        .map_err(|_| CoreError::db("sync conflict preview token metadata is invalid"))?;
    let mut hasher = Sha256::new();
    hasher.update(payload.as_bytes());
    Ok(format!("sync-conflict-preview:{:x}", hasher.finalize()))
}

fn writable_dir(path: &Path) -> CoreResult<bool> {
    let metadata = fs::metadata(path).map_err(map_preflight_error)?;
    Ok(metadata.is_dir() && !metadata.permissions().readonly())
}

fn map_preflight_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        std::io::ErrorKind::InvalidInput => CoreError::io("trash preflight failed"),
        _ => CoreError::io("trash preflight failed"),
    }
}
