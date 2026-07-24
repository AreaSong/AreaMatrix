use std::{
    fs::{self, OpenOptions},
    io::{self, Write},
    path::{Component, Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{
    db::{self, OverviewJournalItem, OverviewProvenanceRecord},
    CoreError, CoreResult, RecoverableOperationContext, RecoverableOperationStatus,
};

use crate::overview::{map_io_error, write_atomic_replace};

use super::{PlanPayload, RenderedTarget};

const DELETED_HASH: &str = "0000000000000000000000000000000000000000000000000000000000000000";

pub(super) fn create_journal(
    repo: &Path,
    payload: &PlanPayload,
    targets: &[RenderedTarget],
) -> CoreResult<()> {
    let context = RecoverableOperationContext {
        operation_id: payload.operation_id.clone(),
        retry_of_operation_id: None,
        operation_code: "overview_regeneration".to_owned(),
        operation_payload_json: serde_json::to_string(payload)
            .map_err(|_| CoreError::internal("overview operation payload encoding failed"))?,
        content_locale: Some(payload.content_locale.clone()),
        repository_revision: payload.repository_revision,
        format_contract_version: payload.format_contract_version,
        target_set_hash: Some(payload.target_set_hash.clone()),
        run_sequence: 1,
    };
    let items = targets
        .iter()
        .enumerate()
        .map(|(index, target)| OverviewJournalItem {
            relative_path: target.relative_path.clone(),
            target_kind: target.target_kind.clone(),
            old_exists: target.old_content.is_some(),
            old_sha256: target.old_content.as_deref().map(sha256),
            new_exists: target.new_content.is_some(),
            new_sha256: target
                .new_content
                .as_deref()
                .map(sha256)
                .unwrap_or_else(|| DELETED_HASH.to_owned()),
            staging_relative_path: format!(
                ".areamatrix/staging/overview/{}/new/{index}.md",
                payload.operation_id
            ),
            backup_relative_path: target.old_content.as_ref().map(|_| {
                format!(
                    ".areamatrix/staging/overview/{}/old/{index}.md",
                    payload.operation_id
                )
            }),
            state: "planned".to_owned(),
            old_provenance: None,
        })
        .collect::<Vec<_>>();
    db::create_overview_regeneration(repo, &context, &items)
}

pub(super) fn execute_precommit(
    repo: &Path,
    payload: &PlanPayload,
    targets: &[RenderedTarget],
) -> CoreResult<()> {
    if let Err(error) = stage_targets(repo, &payload.operation_id, targets) {
        let (operation, _) = db::load_overview_regeneration(repo, &payload.operation_id)?;
        if operation.status == RecoverableOperationStatus::Canceled {
            cleanup_operation_directory(repo, &payload.operation_id)?;
            return Ok(());
        }
        fail_operation(repo, &payload.operation_id, "overview_staging_failed")?;
        return Err(error);
    }
    let snapshot = db::load_repo_config_snapshot_or_default(repo.to_string_lossy().into_owned())?;
    if snapshot.revision != payload.repository_revision {
        fail_operation(repo, &payload.operation_id, "repo_config_revision_conflict")?;
        return Err(CoreError::conflict(
            "repository configuration revision changed",
        ));
    }
    set_status(
        repo,
        &payload.operation_id,
        RecoverableOperationStatus::ReadyToCommit,
        None,
    )
}

pub(super) fn commit_ready(repo: &Path, operation_id: &str) -> CoreResult<()> {
    let (operation, _) = db::load_overview_regeneration(repo, operation_id)?;
    if operation.status != RecoverableOperationStatus::ReadyToCommit {
        return Err(CoreError::conflict(
            "overview regeneration is not ready to commit",
        ));
    }
    let snapshot = db::load_repo_config_snapshot_or_default(repo.to_string_lossy().into_owned())?;
    if snapshot.revision != operation.context.repository_revision {
        fail_operation(repo, operation_id, "repo_config_revision_conflict")?;
        return Err(CoreError::conflict(
            "repository configuration revision changed",
        ));
    }
    let payload: PlanPayload = serde_json::from_str(&operation.context.operation_payload_json)
        .map_err(|_| CoreError::db("overview operation payload is invalid"))?;
    set_status(
        repo,
        operation_id,
        RecoverableOperationStatus::Committing,
        None,
    )?;
    if let Err(error) = roll_forward_internal(repo, &payload) {
        set_status(
            repo,
            operation_id,
            RecoverableOperationStatus::RollbackRequired,
            Some("overview_commit_failed"),
        )?;
        recover_committing(repo, operation_id)?;
        return Err(error);
    }
    Ok(())
}

pub(super) fn recover_committing(repo: &Path, operation_id: &str) -> CoreResult<()> {
    let (operation, _) = db::load_overview_regeneration(repo, operation_id)?;
    let payload: PlanPayload = serde_json::from_str(&operation.context.operation_payload_json)
        .map_err(|_| CoreError::db("overview operation payload is invalid"))?;
    if verify_roll_forward_evidence(repo, operation_id).is_ok() {
        return roll_forward_internal(repo, &payload);
    }
    if verify_rollback_evidence(repo, operation_id).is_ok() {
        return rollback_internal(repo, operation_id);
    }
    set_status(
        repo,
        operation_id,
        RecoverableOperationStatus::RollbackRequired,
        Some("overview_recovery_unverifiable"),
    )?;
    Err(CoreError::conflict(
        "overview regeneration recovery evidence is unverifiable",
    ))
}

fn stage_targets(repo: &Path, operation_id: &str, targets: &[RenderedTarget]) -> CoreResult<()> {
    let (_, items) = db::load_overview_regeneration(repo, operation_id)?;
    if items.len() != targets.len() {
        return Err(CoreError::internal("overview journal target count changed"));
    }
    set_status(
        repo,
        operation_id,
        RecoverableOperationStatus::Staging,
        None,
    )?;
    ensure_operation_directories(repo, operation_id)?;
    for (item, target) in items.iter().zip(targets) {
        if operation_was_canceled(repo, operation_id)? {
            return Err(CoreError::conflict("overview regeneration was canceled"));
        }
        let new_hash = target
            .new_content
            .as_deref()
            .map(sha256)
            .unwrap_or_else(|| DELETED_HASH.to_owned());
        if item.relative_path != target.relative_path
            || item.old_sha256 != target.old_content.as_deref().map(sha256)
            || item.new_sha256 != new_hash
        {
            return Err(CoreError::conflict(
                "overview target changed before staging",
            ));
        }
        if let Some(content) = target.new_content.as_deref() {
            write_owned_file(&repo.join(&item.staging_relative_path), content)?;
        }
        if let (Some(relative), Some(content)) = (
            item.backup_relative_path.as_deref(),
            target.old_content.as_deref(),
        ) {
            write_owned_file(&repo.join(relative), content)?;
        }
        db::update_overview_item_state(repo, operation_id, &item.relative_path, "staged")?;
    }
    Ok(())
}

fn roll_forward_internal(repo: &Path, payload: &PlanPayload) -> CoreResult<()> {
    verify_roll_forward_evidence(repo, &payload.operation_id)?;
    let (_, items) = db::load_overview_regeneration(repo, &payload.operation_id)?;
    for item in &items {
        let path = checked_target_path(repo, &item.relative_path)?;
        let current_hash = current_regular_file_hash(&path)?;
        if item.new_exists {
            if current_hash.as_deref() != Some(item.new_sha256.as_str()) {
                let content = read_verified_staged_file(repo, item)?;
                write_atomic_replace(
                    &path,
                    std::str::from_utf8(&content)
                        .map_err(|_| CoreError::internal("overview content is not UTF-8"))?,
                )?;
            }
        } else if current_hash.is_some() {
            fs::remove_file(&path).map_err(map_io_error)?;
        }
        if item.new_exists {
            db::replace_overview_provenance(
                repo,
                &OverviewProvenanceRecord {
                    relative_path: item.relative_path.clone(),
                    operation_id: payload.operation_id.clone(),
                    content_locale: payload.content_locale.clone(),
                    format_contract_version: payload.format_contract_version,
                    repository_revision: payload.repository_revision,
                    content_sha256: item.new_sha256.clone(),
                    generated_at: now(),
                },
            )?;
        } else {
            db::restore_overview_provenance(repo, &item.relative_path, None)?;
        }
        db::update_overview_item_state(
            repo,
            &payload.operation_id,
            &item.relative_path,
            "applied",
        )?;
    }
    set_status(
        repo,
        &payload.operation_id,
        RecoverableOperationStatus::Completed,
        None,
    )?;
    cleanup_operation_directory(repo, &payload.operation_id)
}

pub(super) fn rollback_internal(repo: &Path, operation_id: &str) -> CoreResult<()> {
    verify_rollback_evidence(repo, operation_id)?;
    let (_, items) = db::load_overview_regeneration(repo, operation_id)?;
    for item in items.iter().rev() {
        let path = checked_target_path(repo, &item.relative_path)?;
        if item.old_exists {
            let backup = item
                .backup_relative_path
                .as_deref()
                .ok_or_else(|| CoreError::internal("overview backup path is missing"))?;
            let bytes = fs::read(repo.join(backup)).map_err(map_io_error)?;
            if Some(sha256(&bytes)) != item.old_sha256 {
                return Err(CoreError::internal("overview backup hash changed"));
            }
            if current_regular_file_hash(&path)?.as_deref() != item.old_sha256.as_deref() {
                write_atomic_replace(
                    &path,
                    std::str::from_utf8(&bytes)
                        .map_err(|_| CoreError::internal("overview backup is not UTF-8"))?,
                )?;
            }
        } else if current_regular_file_hash(&path)?.is_some() {
            fs::remove_file(&path).map_err(map_io_error)?;
        }
        db::restore_overview_provenance(repo, &item.relative_path, item.old_provenance.as_ref())?;
        db::update_overview_item_state(repo, operation_id, &item.relative_path, "restored")?;
    }
    set_status(
        repo,
        operation_id,
        RecoverableOperationStatus::RolledBack,
        None,
    )?;
    cleanup_operation_directory(repo, operation_id)
}

fn verify_roll_forward_evidence(repo: &Path, operation_id: &str) -> CoreResult<()> {
    let (_, items) = db::load_overview_regeneration(repo, operation_id)?;
    for item in &items {
        let path = checked_target_path(repo, &item.relative_path)?;
        let current = current_regular_file_hash(&path)?;
        let is_old = current.as_deref() == item.old_sha256.as_deref()
            && current.is_some() == item.old_exists;
        let is_new = if item.new_exists {
            current.as_deref() == Some(item.new_sha256.as_str())
        } else {
            current.is_none()
        };
        if !is_old && !is_new {
            return Err(CoreError::conflict(
                "overview target changed during regeneration",
            ));
        }
        if item.new_exists && !is_new {
            read_verified_staged_file(repo, item)?;
        }
    }
    Ok(())
}

fn verify_rollback_evidence(repo: &Path, operation_id: &str) -> CoreResult<()> {
    let (_, items) = db::load_overview_regeneration(repo, operation_id)?;
    for item in &items {
        let path = checked_target_path(repo, &item.relative_path)?;
        let current = current_regular_file_hash(&path)?;
        let is_old = current.as_deref() == item.old_sha256.as_deref()
            && current.is_some() == item.old_exists;
        let is_new = if item.new_exists {
            current.as_deref() == Some(item.new_sha256.as_str())
        } else {
            current.is_none()
        };
        if !is_old && !is_new {
            return Err(CoreError::conflict(
                "overview target changed during regeneration",
            ));
        }
        if item.old_exists {
            let backup = item
                .backup_relative_path
                .as_deref()
                .ok_or_else(|| CoreError::internal("overview backup path is missing"))?;
            let bytes = read_regular_file(&repo.join(backup), "overview backup is unsafe")?;
            if Some(sha256(&bytes)) != item.old_sha256 {
                return Err(CoreError::conflict("overview backup hash changed"));
            }
        }
    }
    Ok(())
}

fn read_verified_staged_file(repo: &Path, item: &OverviewJournalItem) -> CoreResult<Vec<u8>> {
    let bytes = read_regular_file(
        &repo.join(&item.staging_relative_path),
        "overview staged file is unsafe",
    )?;
    if sha256(&bytes) != item.new_sha256 {
        return Err(CoreError::conflict("overview staged file hash changed"));
    }
    Ok(bytes)
}

fn read_regular_file(path: &Path, unsafe_message: &str) -> CoreResult<Vec<u8>> {
    let metadata = fs::symlink_metadata(path).map_err(map_io_error)?;
    if !metadata.is_file() || metadata.file_type().is_symlink() {
        return Err(CoreError::config(unsafe_message));
    }
    fs::read(path).map_err(map_io_error)
}

fn current_regular_file_hash(path: &Path) -> CoreResult<Option<String>> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_file() && !metadata.file_type().is_symlink() => fs::read(path)
            .map(|bytes| Some(sha256(&bytes)))
            .map_err(map_io_error),
        Ok(_) => Err(CoreError::config("overview target became unsafe")),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(map_io_error(error)),
    }
}

fn operation_was_canceled(repo: &Path, operation_id: &str) -> CoreResult<bool> {
    let (operation, _) = db::load_overview_regeneration(repo, operation_id)?;
    Ok(operation.status == RecoverableOperationStatus::Canceled)
}

pub(super) fn checked_target_path(repo: &Path, relative: &str) -> CoreResult<PathBuf> {
    let path = Path::new(relative);
    if path.is_absolute()
        || path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        return Err(CoreError::config("overview target path is invalid"));
    }
    let allowed = relative == "AREAMATRIX.md"
        || relative == ".areamatrix/generated/root.md"
        || (relative.starts_with(".areamatrix/generated/nodes/") && relative.ends_with(".md"));
    if !allowed || relative == "README.md" {
        return Err(CoreError::config(
            "overview target path is outside the whitelist",
        ));
    }
    Ok(repo.join(path))
}

fn ensure_operation_directories(repo: &Path, operation_id: &str) -> CoreResult<()> {
    Uuid::parse_str(operation_id).map_err(|_| CoreError::config("operation id is invalid"))?;
    let area_matrix = repo.join(".areamatrix");
    ensure_owned_directory(&area_matrix, false)?;
    let staging = area_matrix.join("staging");
    ensure_owned_directory(&staging, true)?;
    let overview = staging.join("overview");
    ensure_owned_directory(&overview, true)?;
    let base = overview.join(operation_id);
    ensure_owned_directory(&base, true)?;
    for path in [base.join("new"), base.join("old")] {
        ensure_owned_directory(&path, true)?;
    }
    Ok(())
}

fn ensure_owned_directory(path: &Path, create: bool) -> CoreResult<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => Ok(()),
        Ok(_) => Err(CoreError::config("overview staging path is unsafe")),
        Err(error) if error.kind() == io::ErrorKind::NotFound && create => {
            fs::create_dir(path).map_err(map_io_error)?;
            let metadata = fs::symlink_metadata(path).map_err(map_io_error)?;
            if metadata.is_dir() && !metadata.file_type().is_symlink() {
                Ok(())
            } else {
                Err(CoreError::config("overview staging path is unsafe"))
            }
        }
        Err(error) => Err(map_io_error(error)),
    }
}

fn write_owned_file(path: &Path, content: &[u8]) -> CoreResult<()> {
    if path.try_exists().map_err(map_io_error)? {
        let metadata = fs::symlink_metadata(path).map_err(map_io_error)?;
        if !metadata.is_file() || metadata.file_type().is_symlink() {
            return Err(CoreError::config("overview staging file is unsafe"));
        }
        fs::remove_file(path).map_err(map_io_error)?;
    }
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(map_io_error)?;
    file.write_all(content).map_err(map_io_error)?;
    file.sync_all().map_err(map_io_error)
}

pub(super) fn cleanup_operation_directory(repo: &Path, operation_id: &str) -> CoreResult<()> {
    let parsed =
        Uuid::parse_str(operation_id).map_err(|_| CoreError::config("operation id is invalid"))?;
    if parsed.to_string() != operation_id {
        return Err(CoreError::config("operation id is not canonical"));
    }
    let area_matrix = repo.join(".areamatrix");
    ensure_owned_directory(&area_matrix, false)?;
    let staging = area_matrix.join("staging");
    match fs::symlink_metadata(&staging) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        _ => ensure_owned_directory(&staging, false)?,
    }
    let overview = staging.join("overview");
    match fs::symlink_metadata(&overview) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        _ => ensure_owned_directory(&overview, false)?,
    }
    let path = overview.join(operation_id);
    match fs::symlink_metadata(&path) {
        Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => {
            fs::remove_dir_all(path).map_err(map_io_error)
        }
        Ok(_) => Err(CoreError::config("overview operation directory is unsafe")),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(map_io_error(error)),
    }
}

pub(super) fn fail_operation(repo: &Path, operation_id: &str, code: &str) -> CoreResult<()> {
    cleanup_operation_directory(repo, operation_id)?;
    set_status(
        repo,
        operation_id,
        RecoverableOperationStatus::Failed,
        Some(code),
    )
}

fn set_status(
    repo: &Path,
    operation_id: &str,
    status: RecoverableOperationStatus,
    error_code: Option<&str>,
) -> CoreResult<()> {
    db::update_overview_operation_status(repo, operation_id, status, error_code, false)
}

pub(super) fn sha256(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs() as i64)
}
