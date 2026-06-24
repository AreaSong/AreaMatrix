use serde::{Deserialize, Serialize};

/// Scan session category.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ScanSessionKind {
    /// Initial adoption scan.
    Adopt,
    /// Full filesystem reindex.
    Reindex,
}

/// Scan session lifecycle state.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ScanSessionStatus {
    /// Scan is actively running.
    Running,
    /// Scan completed successfully.
    Completed,
    /// Scan paused cleanly.
    Paused,
    /// Scan failed with errors.
    Failed,
    /// Scan was interrupted before a clean stop.
    Interrupted,
}

/// manual rescan preview item category.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ManualRescanPreviewItemKind {
    /// File would be inserted into AreaMatrix metadata.
    Added,
    /// Existing metadata would be updated in place.
    Updated,
    /// Metadata row no longer has a backing file at the expected path.
    Missing,
    /// Core found a possible rename based on an existing content hash.
    RenamedCandidate,
    /// A state requires review before Core can classify it safely.
    Conflict,
    /// File or metadata cannot be read with current permissions.
    Unreadable,
    /// Core could not classify the item safely.
    Unknown,
    /// File is ignored, unchanged, or otherwise not changed by the rescan.
    Skipped,
}

/// One display-safe item in a manual rescan dry-run preview.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ManualRescanPreviewItem {
    /// Preview category for the row.
    pub kind: ManualRescanPreviewItemKind,
    /// Repository-relative path, or a display-safe path when the path cannot be classified.
    pub relative_path: String,
    /// Human-readable reason for the preview classification.
    pub reason: String,
    /// Suggested UI route or user action.
    pub suggested_action: String,
}

/// Dry-run summary for manual rescan confirmation.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ManualRescanPreviewReport {
    /// Number of files that would be inserted.
    pub added: i64,
    /// Number of existing metadata rows that would be updated.
    pub updated: i64,
    /// Number of active metadata rows whose backing file appears missing.
    pub missing_or_deleted_from_fs: i64,
    /// Number of possible rename candidates detected by content hash.
    pub renamed_candidates: i64,
    /// Number of rows requiring conflict review.
    pub conflicts: i64,
    /// Number of unreadable paths.
    pub unreadable: i64,
    /// Number of paths Core could not classify safely.
    pub unknown: i64,
    /// Number of ignored or unchanged paths.
    pub skipped: i64,
    /// Stable snapshot id for the UI to compare against later watcher changes.
    pub snapshot_id: String,
    /// Unix timestamp for preview creation.
    pub created_at: i64,
    /// Whether the preview is already known to be stale.
    pub is_stale: bool,
    /// Bounded sample rows for the confirmation UI.
    pub items: Vec<ManualRescanPreviewItem>,
}

/// Persisted scan session state.
///
/// manual rescan consumers use `kind`, `status`, counters, timestamps,
/// `last_path`, and `errors` to render progress, completion, retry, and failure
/// state without parsing logs or inspecting user files.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ScanSession {
    /// Stable database identifier.
    pub id: i64,
    /// Scan session category.
    pub kind: ScanSessionKind,
    /// Current lifecycle state.
    pub status: ScanSessionStatus,
    /// Last processed repository-relative path.
    pub last_path: Option<String>,
    /// Number of inserted rows.
    pub inserted: i64,
    /// Number of updated rows.
    pub updated: i64,
    /// Number of active metadata rows whose backing file appears missing.
    pub missing: i64,
    /// Number of rows requiring conflict review.
    pub conflicts: i64,
    /// Number of unreadable paths recorded for review.
    pub unreadable: i64,
    /// Number of paths Core could not classify safely.
    pub unknown: i64,
    /// Number of skipped files.
    pub skipped: i64,
    /// Unix timestamp for start.
    pub started_at: i64,
    /// Unix timestamp for last update.
    pub updated_at: i64,
    /// Optional finish timestamp.
    pub finished_at: Option<i64>,
    /// Human-readable errors.
    pub errors: Vec<String>,
}
