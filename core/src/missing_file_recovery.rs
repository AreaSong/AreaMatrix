//! C4-18 missing-file recovery contract types and entry points.

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

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
    validate_repo_path(&repo_path)?;
    validate_file_id(file_id)?;
    Err(CoreError::db("missing file recovery metadata unavailable"))
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
    validate_repo_path(&repo_path)?;
    validate_file_id(request.file_id)?;
    validate_confirmation(request.confirmed, "remove record confirmation is required")?;
    Err(CoreError::db("missing file recovery metadata unavailable"))
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
    validate_repo_path(&repo_path)?;
    validate_file_id(request.file_id)?;
    validate_new_path(&request.new_path)?;
    validate_confirmation(request.confirmed, "relink confirmation is required")?;
    Err(CoreError::db("missing file recovery metadata unavailable"))
}

fn validate_repo_path(repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() {
        return Err(CoreError::db(
            "missing file recovery repository path is required",
        ));
    }
    Ok(())
}

fn validate_file_id(file_id: i64) -> CoreResult<()> {
    if file_id <= 0 {
        return Err(CoreError::file_not_found("missing file record"));
    }
    Ok(())
}

fn validate_new_path(new_path: &str) -> CoreResult<()> {
    if new_path.trim().is_empty() || new_path.contains('\0') {
        return Err(CoreError::file_not_found("selected relink path"));
    }
    Ok(())
}

fn validate_confirmation(confirmed: bool, reason: &str) -> CoreResult<()> {
    if !confirmed {
        return Err(CoreError::permission_denied(reason));
    }
    Ok(())
}
