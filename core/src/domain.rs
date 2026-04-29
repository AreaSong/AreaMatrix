//! Domain types shared by the Rust core and UniFFI boundary.

use serde::{Deserialize, Serialize};

/// How AreaMatrix stores a file relative to the repository.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum StorageMode {
    /// Move the source file into the repository.
    Moved,
    /// Copy the source file into the repository.
    Copied,
    /// Index the source file without copying it.
    Indexed,
}

/// Where a file entry came from.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum FileOrigin {
    /// Added through an explicit AreaMatrix import.
    Imported,
    /// Discovered during initial adoption of an existing folder.
    Adopted,
    /// Discovered from external filesystem changes.
    External,
}

/// Repository initialization mode.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RepoInitMode {
    /// Create a new repository in an empty folder.
    CreateEmpty,
    /// Adopt an existing folder without changing user files.
    AdoptExisting,
}

/// Where generated overview output is written.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum OverviewOutput {
    /// Write generated overviews under `.areamatrix/generated/`.
    GeneratedOnly,
    /// Also maintain the root-level `AREAMATRIX.md` file.
    RootAreaMatrixFile,
}

/// Destination selection for an import.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ImportDestination {
    /// Use classifier rules to select a destination.
    AutoClassify,
    /// Use a user-selected directory under the repository root.
    SelectedDirectory,
    /// Use a named category.
    Category,
}

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

/// How duplicate file hashes should be handled.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum DuplicateStrategy {
    /// Do not import the duplicate.
    Skip,
    /// Replace the existing entry when allowed by later storage logic.
    Overwrite,
    /// Keep both files with conflict-free naming.
    KeepBoth,
    /// Return a duplicate error so the UI can ask the user.
    Ask,
}

/// Why a category was selected.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ClassifyReason {
    /// A keyword rule matched.
    Keyword,
    /// A file extension rule matched.
    Extension,
    /// A future AI classifier selected the category.
    AiPredicted,
    /// The default category was used.
    Default,
}

/// Filesystem event kind sent from the platform layer.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ExternalEventKind {
    /// A path was created.
    Created,
    /// A path was removed.
    Removed,
    /// A path was modified.
    Modified,
    /// A path was renamed.
    Renamed,
}

/// Repository-level configuration.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RepoConfig {
    /// Repository root path.
    pub repo_path: String,
    /// Default storage behavior for imports.
    pub default_mode: StorageMode,
    /// Overview output location.
    pub overview_output: OverviewOutput,
    /// Whether AI features are enabled.
    pub ai_enabled: bool,
    /// User-facing locale, for example `zh-Hans` or `en`.
    pub locale: String,
    /// Whether iCloud warnings are shown.
    pub icloud_warn: bool,
}

/// Options used when initializing a repository.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RepoInitOptions {
    /// Initialization mode.
    pub mode: RepoInitMode,
    /// Whether default category directories should be created.
    pub create_default_categories: bool,
    /// Overview output location.
    pub overview_output: OverviewOutput,
}

/// Options used for a single file import.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ImportOptions {
    /// Storage behavior for the imported file.
    pub mode: StorageMode,
    /// Destination selection mode.
    pub destination: ImportDestination,
    /// Optional repository-relative directory for selected-directory imports.
    pub target_directory: Option<String>,
    /// Optional category override.
    pub override_category: Option<String>,
    /// Optional destination filename override.
    pub override_filename: Option<String>,
    /// Duplicate handling behavior.
    pub duplicate_strategy: DuplicateStrategy,
}

/// Filter used when listing files.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FileFilter {
    /// Optional category slug.
    pub category: Option<String>,
    /// Whether deleted entries should be included.
    pub include_deleted: Option<bool>,
    /// Lower import timestamp bound.
    pub imported_after: Option<i64>,
    /// Upper import timestamp bound.
    pub imported_before: Option<i64>,
    /// Maximum number of rows to return.
    pub limit: i64,
    /// Offset for paginated reads.
    pub offset: i64,
}

/// Filter used when listing change-log entries.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ChangeFilter {
    /// Optional file identifier.
    pub file_id: Option<i64>,
    /// Optional category slug.
    pub category: Option<String>,
    /// Optional action string.
    pub action: Option<String>,
    /// Lower timestamp bound.
    pub since: Option<i64>,
    /// Upper timestamp bound.
    pub until: Option<i64>,
    /// Maximum number of rows to return.
    pub limit: i64,
    /// Offset for paginated reads.
    pub offset: i64,
}

/// A file entry visible through the core API.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FileEntry {
    /// Stable database identifier.
    pub id: i64,
    /// Repository-relative path.
    pub path: String,
    /// Original source filename.
    pub original_name: String,
    /// Current filename.
    pub current_name: String,
    /// Category slug.
    pub category: String,
    /// File size in bytes.
    pub size_bytes: i64,
    /// SHA-256 content hash.
    pub hash_sha256: String,
    /// Storage behavior used for this file.
    pub storage_mode: StorageMode,
    /// Origin of this file entry.
    pub origin: FileOrigin,
    /// Optional original source path.
    pub source_path: Option<String>,
    /// Unix timestamp for initial import.
    pub imported_at: i64,
    /// Unix timestamp for last update.
    pub updated_at: i64,
}

/// A user-visible change-log entry.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ChangeLogEntry {
    /// Stable database identifier.
    pub id: i64,
    /// Optional related file identifier.
    pub file_id: Option<i64>,
    /// Filename snapshot for display.
    pub filename: String,
    /// Category snapshot for display.
    pub category: String,
    /// Action string.
    pub action: String,
    /// JSON detail payload.
    pub detail_json: String,
    /// Unix timestamp for the event.
    pub occurred_at: i64,
}

/// Classification result for a filename.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ClassifyResult {
    /// Category slug.
    pub category: String,
    /// Suggested destination filename.
    pub suggested_name: String,
    /// Classification reason.
    pub reason: ClassifyReason,
    /// Confidence score from 0.0 to 1.0.
    pub confidence: f32,
}

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
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ReindexReport {
    /// Optional scan session identifier.
    pub scan_session_id: Option<i64>,
    /// Number of inserted rows.
    pub inserted: i64,
    /// Number of updated rows.
    pub updated: i64,
    /// Number of skipped files.
    pub skipped: i64,
    /// Human-readable errors.
    pub errors: Vec<String>,
}

/// Persisted scan session state.
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

/// External filesystem event from the platform layer.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ExternalEvent {
    /// Repository-relative or absolute path supplied by the platform layer.
    pub path: String,
    /// Event kind.
    pub kind: ExternalEventKind,
    /// Platform filesystem event identifier.
    pub fs_event_id: i64,
}

/// Summary of external-change synchronization.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SyncResult {
    /// Number of created paths detected.
    pub detected_creates: i64,
    /// Number of renames detected.
    pub detected_renames: i64,
    /// Number of deletes detected.
    pub detected_deletes: i64,
    /// Number of modifications detected.
    pub detected_modifies: i64,
    /// Human-readable errors.
    pub errors: Vec<String>,
}
