//! C4-15 sync conflict detection contract types and entry point.

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

/// Lifecycle state for a detected sync conflict.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SyncConflictStatus {
    /// The conflict must remain visible until a user chooses a resolution.
    NeedsReview,
    /// The conflict was resolved by a later explicit resolution flow.
    Resolved,
}

/// Sync conflict category shown to Stage 4 conflict entry and review pages.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SyncConflictType {
    /// The same repository-relative path has multiple versions with different content.
    SameNameDifferentContent,
    /// Multiple platforms changed the same file before the repository converged.
    ConcurrentModification,
    /// Filesystem and AreaMatrix metadata no longer agree.
    MetadataMismatch,
    /// One expected version is missing or inaccessible.
    MissingVersion,
    /// Core cannot classify the conflict source safely.
    Unknown,
}

/// User-facing severity for prioritizing conflict review.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SyncConflictSeverity {
    /// The conflict is informational but still reviewable.
    Low,
    /// The conflict should be reviewed during normal workflow.
    Medium,
    /// The conflict blocks a safe follow-up action until reviewed.
    High,
}

/// Role of one file or metadata row participating in a sync conflict.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SyncConflictFileRole {
    /// Existing canonical repository path or record.
    Existing,
    /// Incoming version detected from another platform or sync provider.
    Incoming,
    /// Provider-created conflict copy.
    ConflictCopy,
    /// Expected version is missing or cannot be read.
    Missing,
    /// Role cannot be determined without user review.
    Unknown,
}

/// One affected file/version entry inside a sync conflict.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SyncConflictAffectedFile {
    /// Repository-relative path or safe display path.
    pub path: String,
    /// AreaMatrix file id when the version is already tracked.
    pub file_id: Option<i64>,
    /// Role of this version in the conflict.
    pub role: SyncConflictFileRole,
    /// File size when metadata can be inspected.
    pub size_bytes: Option<i64>,
    /// Last modified timestamp when available.
    pub modified_at: Option<i64>,
    /// SHA-256 hash when known without unsafe downloads or writes.
    pub hash_sha256: Option<String>,
    /// Platform or provider source, such as iOS, Windows, Linux, iCloud, or OneDrive.
    pub source_platform: Option<String>,
}

/// Sync conflict row returned by C4-15 detection.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SyncConflict {
    /// Stable conflict id used by later review and resolution tasks.
    pub conflict_id: String,
    /// Conflict category for list grouping and badges.
    pub conflict_type: SyncConflictType,
    /// Review priority for UI ordering and status summaries.
    pub severity: SyncConflictSeverity,
    /// Current lifecycle state.
    pub status: SyncConflictStatus,
    /// Main repository-relative path shown in compact entry rows.
    pub primary_path: String,
    /// Affected files or metadata versions participating in the conflict.
    pub affected_files: Vec<SyncConflictAffectedFile>,
    /// Number of versions Core can identify for the conflict.
    pub version_count: i64,
    /// Cloud or platform source summary when known.
    pub source_provider: Option<String>,
    /// Unix timestamp when the conflict was detected.
    pub detected_at: Option<i64>,
    /// Display-safe summary for banners, VoiceOver, and diagnostics previews.
    pub summary: Option<String>,
}

/// Detects unresolved C4-15 sync conflicts without resolving them.
///
/// This contract entry point exists so UDL, bindings, and downstream page work
/// can compile against the Stage 4 shape. The implementation task must replace
/// this unavailable metadata result with real conflict-state inspection and
/// conflict-state metadata writes.
///
/// # Errors
///
/// Returns `CoreError::Db { message }` until C4-15 conflict-state metadata
/// inspection and writes are implemented. Future implementations may also
/// return `CoreError::Io { message }` or `CoreError::Conflict { path }`
/// according to the public Core API contract.
pub(crate) fn detect_sync_conflicts(_repo_path: String) -> CoreResult<Vec<SyncConflict>> {
    Err(CoreError::db(
        "sync conflict detection metadata is unavailable",
    ))
}
