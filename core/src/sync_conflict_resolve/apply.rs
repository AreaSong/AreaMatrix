use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{db, storage, CoreError, CoreResult};

use super::{
    resolution_detail_json, IncomingReplacement, ResolutionPlan, SyncConflictResolutionRequest,
    SyncConflictResolveReport,
};

pub(super) fn apply_resolution(
    repo: &Path,
    plan: &ResolutionPlan,
    request: &SyncConflictResolutionRequest,
    serialized_state: &str,
    resolved_at: i64,
) -> CoreResult<SyncConflictResolveReport> {
    db::preflight_sync_conflict_resolution(repo)?;
    match &plan.replacement {
        Some(replacement) if replacement.move_incoming_to_canonical => {
            apply_file_replacement(repo, plan, request, replacement, serialized_state, resolved_at)
        }
        Some(replacement) => persist_resolution(
            repo,
            plan,
            request,
            Some(replacement),
            serialized_state,
            &[],
            resolved_at,
        ),
        None => persist_resolution(repo, plan, request, None, serialized_state, &[], resolved_at),
    }
}

fn apply_file_replacement(
    repo: &Path,
    plan: &ResolutionPlan,
    request: &SyncConflictResolutionRequest,
    replacement: &IncomingReplacement,
    serialized_state: &str,
    resolved_at: i64,
) -> CoreResult<SyncConflictResolveReport> {
    let existing_path = repo.join(&replacement.existing_path);
    let incoming_path = repo.join(&replacement.incoming_path);
    let canonical_path = repo.join(&replacement.canonical_path);
    preflight_regular_file(&existing_path, &replacement.existing_path)?;
    preflight_regular_file(&incoming_path, &replacement.incoming_path)?;

    let mut trash_guard = TrashMoveGuard::move_to_trash(&existing_path)?;
    let mut incoming_guard = IncomingMoveGuard::move_to_canonical(&incoming_path, &canonical_path)?;
    let trashed_paths = vec![replacement.existing_path.clone()];
    let result = persist_resolution(
        repo,
        plan,
        request,
        Some(replacement),
        serialized_state,
        &trashed_paths,
        resolved_at,
    );

    match result {
        Ok(report) => {
            incoming_guard.disarm();
            trash_guard.disarm();
            Ok(report)
        }
        Err(error) => {
            rollback_replacement(&mut incoming_guard, &mut trash_guard)?;
            Err(error)
        }
    }
}

fn persist_resolution(
    repo: &Path,
    plan: &ResolutionPlan,
    request: &SyncConflictResolutionRequest,
    replacement: Option<&IncomingReplacement>,
    serialized_state: &str,
    trashed_paths: &[String],
    resolved_at: i64,
) -> CoreResult<SyncConflictResolveReport> {
    let detail_json = resolution_detail_json(plan, request, trashed_paths, resolved_at)?;
    let file_update = replacement.map(|replacement| db::SyncConflictCanonicalUpdate {
        file_id: replacement.affected_file_id,
        size_bytes: replacement.incoming_size_bytes,
        hash_sha256: replacement.incoming_hash_sha256.as_str(),
    });
    db::record_sync_conflict_resolution(
        repo,
        db::SyncConflictResolutionRecord {
            serialized_state,
            file_update,
            log_file_id: log_file_id(plan, replacement),
            detail_json: &detail_json,
            occurred_at: resolved_at,
        },
    )?;
    Ok(plan.resolve_report(trashed_paths.to_vec(), None, resolved_at))
}

fn log_file_id(plan: &ResolutionPlan, replacement: Option<&IncomingReplacement>) -> Option<i64> {
    replacement
        .map(|replacement| replacement.affected_file_id)
        .or_else(|| plan.affected_file_ids.first().copied())
}

fn preflight_regular_file(path: &Path, display_path: &str) -> CoreResult<()> {
    match fs::metadata(path) {
        Ok(metadata) if metadata.is_file() => Ok(()),
        Ok(_) => Err(CoreError::conflict(display_path.to_owned())),
        Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied => {
            Err(CoreError::permission_denied(display_path.to_owned()))
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            Err(CoreError::conflict(display_path.to_owned()))
        }
        Err(_) => Err(CoreError::io("sync conflict file preflight failed")),
    }
}

fn rollback_replacement(
    incoming_guard: &mut IncomingMoveGuard,
    trash_guard: &mut TrashMoveGuard,
) -> CoreResult<()> {
    incoming_guard.rollback()?;
    trash_guard.rollback()
}

struct TrashMoveGuard {
    original_path: PathBuf,
    trash_path: PathBuf,
    armed: bool,
}

impl TrashMoveGuard {
    fn move_to_trash(path: &Path) -> CoreResult<Self> {
        let trash_path = storage::move_to_user_trash(path)?
            .ok_or_else(|| CoreError::io("trash rollback path unavailable"))?;
        Ok(Self {
            original_path: path.to_path_buf(),
            trash_path,
            armed: true,
        })
    }

    fn rollback(&mut self) -> CoreResult<()> {
        if self.armed
            && self.trash_path.try_exists().map_err(map_rollback_error)?
            && !self.original_path.try_exists().map_err(map_rollback_error)?
        {
            storage::move_recoverable_file(&self.trash_path, &self.original_path)?;
        }
        self.armed = false;
        Ok(())
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for TrashMoveGuard {
    fn drop(&mut self) {
        let _rollback_result = self.rollback();
    }
}

struct IncomingMoveGuard {
    original_path: PathBuf,
    canonical_path: PathBuf,
    armed: bool,
}

impl IncomingMoveGuard {
    fn move_to_canonical(original_path: &Path, canonical_path: &Path) -> CoreResult<Self> {
        storage::move_recoverable_file(original_path, canonical_path)?;
        Ok(Self {
            original_path: original_path.to_path_buf(),
            canonical_path: canonical_path.to_path_buf(),
            armed: true,
        })
    }

    fn rollback(&mut self) -> CoreResult<()> {
        if self.armed
            && self.canonical_path.try_exists().map_err(map_rollback_error)?
            && !self.original_path.try_exists().map_err(map_rollback_error)?
        {
            storage::move_recoverable_file(&self.canonical_path, &self.original_path)?;
        }
        self.armed = false;
        Ok(())
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl Drop for IncomingMoveGuard {
    fn drop(&mut self) {
        let _rollback_result = self.rollback();
    }
}

fn map_rollback_error(error: std::io::Error) -> CoreError {
    match error.kind() {
        std::io::ErrorKind::PermissionDenied => CoreError::permission_denied("permission denied"),
        _ => CoreError::io("sync conflict rollback failed"),
    }
}
