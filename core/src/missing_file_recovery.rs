//! C4-18 missing-file recovery contract types and entry points.

mod filesystem;

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::{
    db::{self, MissingFileRecoveryEntry},
    CoreError, CoreResult,
};
use filesystem::{
    backing_file_path, ensure_record_is_missing, inspect_relink_candidate, missing_reason,
    origin_detail, storage_mode_detail, RelinkCandidate,
};

/// Reason Core can report for a retained missing-file metadata row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum MissingFileReason {
    /// The last known path no longer exists.
    PathMissing,
    /// The path or metadata cannot be inspected with current permissions.
    PermissionDenied,
    /// A cloud provider reports the file as an unavailable placeholder.
    CloudPlaceholder,
    /// The path likely depends on a disconnected external volume or mount.
    ExternalVolumeDisconnected,
    /// Core cannot classify the missing state safely.
    Unknown,
}

/// Current recovery status for one missing-file record.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum MissingFileRecoveryStatus {
    /// The record is still present but the backing file is missing.
    Missing,
    /// A read-only check found the backing file again.
    Present,
    /// The record was relinked to a user-selected matching file.
    Relinked,
    /// The selected file exists but does not match the missing record hash.
    HashMismatch,
    /// Only the AreaMatrix record was removed from metadata.
    RecordRemoved,
    /// Recovery could not continue without user or platform action.
    Blocked,
}

/// Page-ready C4-18 missing-file state for S4-X-06.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct MissingFileState {
    /// Stable AreaMatrix file id.
    pub file_id: i64,
    /// Repository-relative path stored in metadata.
    pub relative_path: String,
    /// Last known platform path when Core has one.
    pub last_known_path: Option<String>,
    /// Unix timestamp when the file was last known to be present.
    pub last_seen_at: Option<i64>,
    /// Structured reason for the missing state.
    pub reason: MissingFileReason,
    /// Stored SHA-256 hash for relink verification when available.
    pub expected_hash_sha256: Option<String>,
    /// Whether `Locate File` can be offered by the platform shell.
    pub can_locate: bool,
    /// Whether `Try Again` can run a read-only path check.
    pub can_try_again: bool,
    /// Whether S4-X-06 may expose `Remove Record...`.
    pub can_remove_record: bool,
    /// Whether remove record must show explicit confirmation first.
    pub remove_record_requires_confirmation: bool,
    /// Whether the page may route to S4-X-07 rescan confirmation.
    pub can_run_rescan: bool,
    /// Stable disabled reason for the rescan route.
    pub rescan_disabled_reason: Option<String>,
}

/// User-selected relink request for C4-18.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct MissingFileRelinkRequest {
    /// Stable AreaMatrix file id.
    pub file_id: i64,
    /// User-selected replacement path after the platform picker grants access.
    pub new_path: String,
    /// Whether the user confirmed relinking after hash verification.
    pub confirmed: bool,
}

/// Confirmed remove-record request for C4-18.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct MissingFileRemoveRecordRequest {
    /// Stable AreaMatrix file id.
    pub file_id: i64,
    /// Explicit user confirmation that only metadata will be removed.
    pub confirmed: bool,
}

/// Result returned by relink and remove-record recovery actions.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct MissingFileRecoveryReport {
    /// Stable AreaMatrix file id.
    pub file_id: i64,
    /// Final action status.
    pub status: MissingFileRecoveryStatus,
    /// Previous repository-relative or last-known path.
    pub previous_path: Option<String>,
    /// Current path after a successful relink, when any.
    pub current_path: Option<String>,
    /// Whether the selected relink candidate matched the stored file hash.
    pub hash_matched: bool,
    /// Whether the AreaMatrix metadata record was removed.
    pub record_removed: bool,
    /// Whether any user file was deleted by this action. C4-18 must keep this false.
    pub file_deleted: bool,
    /// Change-log action written by the later implementation, when successful.
    pub change_log_action: Option<String>,
    /// Display-safe reason or blocked summary for the page.
    pub message: Option<String>,
}

/// Returns page-ready missing-file state for S4-X-06.
///
/// The contract is read-only. It exposes the last known path, reason, hash
/// expectation, confirmation requirements, and rescan route state without
/// scanning the whole repository, deleting records, downloading placeholders,
/// or mutating user files.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when `file_id` is not a valid
/// active missing-file record, `CoreError::PermissionDenied { path }` when
/// metadata inspection is blocked, and `CoreError::Db { message }` when
/// recovery metadata cannot be read.
pub(crate) fn get_missing_file_state(
    repo_path: String,
    file_id: i64,
) -> CoreResult<MissingFileState> {
    let repo = validate_repo_path(&repo_path)?;
    validate_file_id(file_id)?;
    let entry = db::load_missing_file_recovery_entry(&repo, file_id)?;
    let backing_path = backing_file_path(&repo, &entry);
    ensure_record_is_missing(&backing_path)?;
    Ok(MissingFileState {
        file_id: entry.id,
        relative_path: entry.path.clone(),
        last_known_path: Some(backing_path.to_string_lossy().into_owned()),
        last_seen_at: Some(entry.updated_at),
        reason: missing_reason(&backing_path),
        expected_hash_sha256: Some(entry.hash_sha256),
        can_locate: true,
        can_try_again: true,
        can_remove_record: true,
        remove_record_requires_confirmation: true,
        can_run_rescan: false,
        rescan_disabled_reason: Some("manual rescan requires S4-X-07 confirmation".to_owned()),
    })
}

/// Removes only the AreaMatrix metadata record for a missing file.
///
/// This C4-18 entry point requires explicit confirmation and must never delete,
/// move, rename, overwrite, trash, or download a user file. The later
/// implementation writes metadata and change-log state only after the
/// confirmation is present.
///
/// # Errors
///
/// Returns `CoreError::PermissionDenied { path }` when confirmation is missing,
/// `CoreError::FileNotFound { path }` when the file id is invalid or no longer
/// removable, and `CoreError::Db { message }` when metadata or change-log
/// persistence fails.
pub(crate) fn remove_missing_file_record(
    repo_path: String,
    request: MissingFileRemoveRecordRequest,
) -> CoreResult<MissingFileRecoveryReport> {
    let repo = validate_repo_path(&repo_path)?;
    validate_file_id(request.file_id)?;
    validate_confirmation(request.confirmed, "remove record confirmation is required")?;
    let entry = db::load_missing_file_recovery_entry(&repo, request.file_id)?;
    let backing_path = backing_file_path(&repo, &entry);
    ensure_record_is_missing(&backing_path)?;
    let detail = json!({
        "kind": "missing_file_record_removed",
        "by": "user",
        "path": entry.path.as_str(),
        "last_known_path": backing_path.to_string_lossy(),
        "storage_mode": storage_mode_detail(&entry.storage_mode),
        "origin": origin_detail(&entry.origin),
        "file_deleted": false,
    });
    db::mark_missing_file_record_removed(&repo, &entry, &detail)?;
    Ok(MissingFileRecoveryReport {
        file_id: entry.id,
        status: MissingFileRecoveryStatus::RecordRemoved,
        previous_path: Some(entry.path),
        current_path: None,
        hash_matched: false,
        record_removed: true,
        file_deleted: false,
        change_log_action: Some("removed_from_index".to_owned()),
        message: Some("Record removed; user file was not deleted.".to_owned()),
    })
}

/// Relinks a missing record to a user-selected matching file.
///
/// The platform layer owns file picking and permission recovery. Core receives
/// the authorized path, verifies it against stored metadata, and must not
/// overwrite or delete either the selected file or the old missing path.
/// Hash mismatch is represented by the report status so the page can keep the
/// record missing without linking an unsafe candidate.
///
/// # Errors
///
/// Returns `CoreError::FileNotFound { path }` when the file id or selected path
/// is absent, `CoreError::PermissionDenied { path }` when confirmation or path
/// access is missing, and `CoreError::Db { message }` when metadata or
/// change-log persistence fails.
pub(crate) fn relink_missing_file(
    repo_path: String,
    request: MissingFileRelinkRequest,
) -> CoreResult<MissingFileRecoveryReport> {
    let repo = validate_repo_path(&repo_path)?;
    validate_file_id(request.file_id)?;
    validate_confirmation(request.confirmed, "relink confirmation is required")?;
    let selected_path = validate_new_path(&request.new_path)?;
    let entry = db::load_missing_file_recovery_entry(&repo, request.file_id)?;
    let previous_path = entry.path.clone();
    let previous_backing_path = backing_file_path(&repo, &entry);
    ensure_record_is_missing(&previous_backing_path)?;
    let candidate = inspect_relink_candidate(&repo, &entry, &selected_path)?;

    if candidate.hash_sha256 != entry.hash_sha256 {
        return Ok(hash_mismatch_report(entry.id, previous_path));
    }

    let detail = relink_detail(&entry, &previous_path, &candidate, &selected_path);
    db::relink_missing_file_record(
        &repo,
        &entry,
        db::MissingFileRelinkUpdate {
            relative_path: &candidate.relative_path,
            current_name: &candidate.current_name,
            category: &candidate.category,
            source_path: candidate.source_path.as_deref(),
            size_bytes: candidate.size_bytes,
            detail: &detail,
        },
    )?;
    Ok(relinked_report(
        entry.id,
        previous_path,
        candidate.relative_path,
    ))
}

fn validate_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::db(
            "missing file recovery repository path is required",
        ));
    }
    Ok(PathBuf::from(repo_path))
}

fn validate_file_id(file_id: i64) -> CoreResult<()> {
    if file_id <= 0 {
        return Err(CoreError::file_not_found("missing file record"));
    }
    Ok(())
}

fn validate_new_path(new_path: &str) -> CoreResult<PathBuf> {
    if new_path.trim().is_empty() || new_path.contains('\0') {
        return Err(CoreError::file_not_found("selected relink path"));
    }
    Ok(PathBuf::from(new_path))
}

fn validate_confirmation(confirmed: bool, reason: &str) -> CoreResult<()> {
    if !confirmed {
        return Err(CoreError::permission_denied(reason));
    }
    Ok(())
}

fn hash_mismatch_report(file_id: i64, previous_path: String) -> MissingFileRecoveryReport {
    MissingFileRecoveryReport {
        file_id,
        status: MissingFileRecoveryStatus::HashMismatch,
        previous_path: Some(previous_path),
        current_path: None,
        hash_matched: false,
        record_removed: false,
        file_deleted: false,
        change_log_action: None,
        message: Some("Selected file does not match the missing record.".to_owned()),
    }
}

fn relinked_report(
    file_id: i64,
    previous_path: String,
    current_path: String,
) -> MissingFileRecoveryReport {
    MissingFileRecoveryReport {
        file_id,
        status: MissingFileRecoveryStatus::Relinked,
        previous_path: Some(previous_path),
        current_path: Some(current_path),
        hash_matched: true,
        record_removed: false,
        file_deleted: false,
        change_log_action: Some("external_modified".to_owned()),
        message: Some("Missing file relinked.".to_owned()),
    }
}

fn relink_detail(
    entry: &MissingFileRecoveryEntry,
    previous_path: &str,
    candidate: &RelinkCandidate,
    selected_path: &Path,
) -> serde_json::Value {
    json!({
        "kind": "missing_file_relinked",
        "by": "user",
        "from_path": previous_path,
        "to_path": candidate.relative_path.as_str(),
        "selected_path": selected_path.to_string_lossy(),
        "storage_mode": storage_mode_detail(&entry.storage_mode),
        "hash_sha256": candidate.hash_sha256.as_str(),
        "file_deleted": false,
    })
}
