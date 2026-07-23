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
    /// Whether repair should preserve the damaged metadata state before mutation.
    pub preserve_diagnostics_snapshot: bool,
    /// Opaque token returned by the read-only repair preflight.
    pub preflight_token: String,
    /// Exact healthy policy or explicit canonical recovery policy.
    pub repository_locale_policy: String,
}

/// Metadata and locale state observed before repair confirmation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RepairMetadataLocaleState {
    /// Metadata and the persisted locale are healthy.
    Healthy,
    /// The `.areamatrix` directory is absent.
    MetadataAbsent,
    /// The metadata directory exists but `index.db` is absent.
    DatabaseMissing,
    /// The database cannot pass read-only integrity and schema checks.
    DatabaseCorrupt,
    /// The locale row is missing or empty.
    LocaleMissing,
    /// The locale row contains an unsupported exact value.
    LocaleUnsupported,
}

/// Read-only repair observation that must be returned with the mutation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RepairMetadataPreflight {
    /// Observed metadata and locale state.
    pub locale_state: RepairMetadataLocaleState,
    /// Exact healthy policy that can be preserved without canonicalization.
    pub repository_locale_policy: Option<String>,
    /// Exact unsupported value shown only for explicit recovery.
    pub unsupported_locale: Option<String>,
    /// Whether the UI must require an explicit canonical policy selection.
    pub requires_explicit_locale_selection: bool,
    /// Opaque state and identity token used for compare-and-swap repair.
    pub preflight_token: String,
}

/// Result of a metadata-only repair.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RepairMetadataOutcome {
    /// Existing metadata was verified without replacement.
    Verified,
    /// Missing metadata or database state was initialized.
    Initialized,
    /// Corrupt metadata was rebuilt or an invalid locale was repaired.
    Rebuilt,
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
    /// Optional diagnostics snapshot path preserved before repair mutation.
    pub diagnostics_snapshot_path: Option<String>,
    /// Metadata-only outcome; reindex counters belong to `ReindexReport`.
    pub outcome: RepairMetadataOutcome,
}
