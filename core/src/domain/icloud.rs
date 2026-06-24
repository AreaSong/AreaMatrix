use serde::{Deserialize, Serialize};

/// Lifecycle state for an iCloud conflicted copy pair.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ICloudConflictStatus {
    /// The pair still needs explicit user review before any resolution action.
    NeedsReview,
    /// The pair was marked resolved by a later resolution flow.
    Resolved,
}

/// Read-only iCloud conflicted copy pair returned to Swift.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ICloudConflictPair {
    /// Stable identifier for later single-item resolution.
    pub conflict_id: String,
    /// Repository-relative original path when it can be identified.
    pub original_path: Option<String>,
    /// Repository-relative conflicted copy path.
    pub conflicted_copy_path: String,
    /// Original file modification timestamp when available.
    pub original_modified_at: Option<i64>,
    /// Conflicted copy modification timestamp.
    pub conflicted_modified_at: i64,
    /// Current user-visible conflict state.
    pub status: ICloudConflictStatus,
    /// Reason shown when pairing is uncertain and needs user review.
    pub uncertainty_reason: Option<String>,
}

/// Version role inside an iCloud conflict preview.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ICloudConflictVersionRole {
    /// The inferred original version.
    Original,
    /// The iCloud conflicted copy version.
    ConflictedCopy,
}

/// Preview availability for one conflict version.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ICloudConflictPreviewStatus {
    /// Core can provide a short text or metadata summary.
    Available,
    /// Core can provide metadata only; platform QuickLook may still be available.
    MetadataOnly,
    /// Core cannot provide enough metadata for this version.
    Unavailable,
}

/// User resolution choices supported by iCloud conflict resolution.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ICloudConflictResolution {
    /// Keep all versions and mark the conflict resolved or acknowledged.
    KeepBoth,
    /// Keep the inferred original version and move the conflicted copy to Trash.
    KeepOriginal,
    /// Keep the conflicted copy and move the inferred original version to Trash.
    KeepConflictedCopy,
}

/// Metadata and preview summary for one conflict version.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ICloudConflictVersionMetadata {
    /// Stable id for the version inside the conflict preview.
    pub version_id: String,
    /// Version role used by iCloud conflict review surface to label left/right choices.
    pub role: ICloudConflictVersionRole,
    /// Repository-relative path for the version.
    pub path: String,
    /// File modification timestamp when metadata can be read.
    pub modified_at: Option<i64>,
    /// File size when metadata can be read.
    pub size_bytes: Option<i64>,
    /// SHA-256 hash when Core can compute it without triggering iCloud download.
    pub hash_sha256: Option<String>,
    /// Short preview summary for metadata-only or text-preview display.
    pub preview_summary: Option<String>,
    /// Whether Core has enough preview state for this version.
    pub preview_status: ICloudConflictPreviewStatus,
}

/// One resolution option exposed to iCloud conflict review surface.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ICloudConflictResolutionOption {
    /// Resolution represented by this option.
    pub resolution: ICloudConflictResolution,
    /// Whether confirming this option can move a version to Trash.
    pub destructive: bool,
    /// Whether this option depends on system Trash availability.
    pub requires_trash: bool,
    /// Whether the UI may enable this option.
    pub enabled: bool,
    /// Structured disabled reason for VoiceOver, buttons, and error summaries.
    pub disabled_reason: Option<String>,
}

/// iCloud conflict preview report for comparing and resolving iCloud conflict versions.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ICloudConflictPreviewReport {
    /// Conflict id from `list_icloud_conflicts`.
    pub conflict_id: String,
    /// Version metadata and preview summaries available for the conflict.
    pub versions: Vec<ICloudConflictVersionMetadata>,
    /// Default safe choice; must remain KeepBoth.
    pub default_resolution: ICloudConflictResolution,
    /// Per-choice enablement and destructive boundary metadata.
    pub resolution_options: Vec<ICloudConflictResolutionOption>,
    /// Whether all required metadata is available for destructive choices.
    pub metadata_complete: bool,
    /// Whether the platform reported Trash as available for destructive choices.
    pub trash_available: bool,
    /// Whether KeepBoth can be applied without moving files.
    pub can_keep_both: bool,
    /// Whether any destructive resolution may be enabled.
    pub can_resolve_destructive: bool,
    /// Overall blocked reason when the preview cannot be resolved yet.
    pub blocked_reason: Option<String>,
}

/// iCloud conflict resolution result returned after explicit user confirmation.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ICloudConflictResolveReport {
    /// Conflict id that was resolved.
    pub conflict_id: String,
    /// User-confirmed resolution.
    pub resolution: ICloudConflictResolution,
    /// Final conflict state after the operation.
    pub status: ICloudConflictStatus,
    /// Versions retained after resolution.
    pub kept_paths: Vec<String>,
    /// Versions moved to Trash; empty for KeepBoth.
    pub trashed_paths: Vec<String>,
    /// Undo token when the resolution moved a version to Trash and Undo is available.
    pub undo_token: Option<String>,
    /// Change-log action written for the resolution.
    pub change_log_action: String,
}
