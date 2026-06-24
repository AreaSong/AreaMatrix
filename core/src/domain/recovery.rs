use serde::{Deserialize, Serialize};

/// Startup recovery summary.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RecoveryReport {
    /// Number of staging files removed.
    pub cleaned_staging_files: i64,
    /// Number of staging database rows reverted.
    pub reverted_staging_db_rows: i64,
    /// Human-readable warnings.
    pub warnings: Vec<String>,
}

/// Filesystem reindex summary.
///
/// manual rescan consumers use this as the post-confirmation summary for
/// an entire-repository scan after [`crate::domain::ManualRescanPreviewReport`] has shown the
/// dry-run impact. Missing, conflict, unreadable, and unknown counts are
/// review signals; Core does not silently delete or merge those items.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ReindexReport {
    /// Optional scan session identifier.
    pub scan_session_id: Option<i64>,
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
    /// Human-readable errors.
    pub errors: Vec<String>,
}

/// Options for metadata repair.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RepairOptions {
    /// Whether repair should run a full filesystem rescan after diagnostics.
    pub full_rescan: bool,
    /// Whether repair should preserve the damaged metadata state before mutation.
    pub preserve_diagnostics_snapshot: bool,
}

/// Reference to an AreaMatrix-owned diagnostics snapshot.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct DiagnosticsSnapshot {
    /// Repository-relative path under `.areamatrix/` where the snapshot was written.
    pub snapshot_path: String,
    /// Unix timestamp for snapshot creation.
    pub created_at: i64,
    /// Human-readable warnings about partial or skipped diagnostics.
    pub warnings: Vec<String>,
}

/// Metadata repair summary returned to Swift.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RepairReport {
    /// Optional scan session identifier used by a full repair rescan.
    pub scan_session_id: Option<i64>,
    /// Optional diagnostics snapshot path preserved before repair mutation.
    pub diagnostics_snapshot_path: Option<String>,
    /// Number of metadata rows inserted by the repair pass.
    pub inserted: i64,
    /// Number of metadata rows updated by the repair pass.
    pub updated: i64,
    /// Number of filesystem entries skipped by the repair pass.
    pub skipped: i64,
    /// Human-readable errors that did not delete user files or clear diagnostics.
    pub errors: Vec<String>,
}
