use serde::{Deserialize, Serialize};

use super::file::StorageMode;

/// Repository initialization mode.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RepoInitMode {
    /// Create a new repository in an empty folder.
    CreateEmpty,
    /// Adopt an existing folder without changing user files.
    AdoptExisting,
}

/// Structured issue discovered while validating a candidate repository path.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RepoPathIssue {
    /// The selected path does not exist.
    MissingPath,
    /// The selected path exists but is not a directory.
    NotDirectory,
    /// The selected directory cannot be read.
    NotReadable,
    /// The selected directory cannot be written.
    NotWritable,
    /// The directory contains user-visible entries.
    NonEmptyDirectory,
    /// The directory already contains AreaMatrix metadata.
    AlreadyInitialized,
    /// The selected path is the `.areamatrix` directory or one of its children.
    InsideAreaMatrix,
    /// The path appears to be managed by iCloud.
    ICloudPath,
    /// The path appears to be managed by OneDrive.
    OneDrivePath,
    /// A Windows path component uses a reserved device name.
    WindowsReservedName,
    /// A Windows-shaped path has case-insensitive comparison semantics.
    WindowsCaseInsensitive,
    /// A previous adopt or reindex scan did not finish cleanly.
    UnfinishedScanSession,
}

/// Platform-neutral classification of a repository path location.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum PlatformPathKind {
    /// No cloud or network marker was detected.
    Local,
    /// iCloud Drive or CloudDocs-managed path.
    ICloudDrive,
    /// OneDrive-managed path.
    OneDrive,
    /// Windows UNC or network-share style path.
    NetworkShare,
    /// Core cannot identify the location type from path shape alone.
    Unknown,
}

/// Where generated overview output is written.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum OverviewOutput {
    /// Write generated overviews under `.areamatrix/generated/`.
    GeneratedOnly,
    /// Also maintain the root-level `AREAMATRIX.md` file.
    RootAreaMatrixFile,
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
    /// Whether extension-based classifier rules are enabled.
    pub enable_extension_rules: bool,
    /// Whether keyword-based classifier rules are enabled.
    pub enable_keyword_rules: bool,
    /// Whether files without a classifier match fall back to the inbox category.
    pub fallback_to_inbox: bool,
    /// Whether import flows may expose the dangerous replace option.
    pub allow_replace_during_import: bool,
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

/// Read-only validation result for a candidate repository root.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RepoPathValidation {
    /// Original repository path supplied by the caller.
    pub repo_path: String,
    /// Whether the path exists on disk.
    pub exists: bool,
    /// Whether the path is a directory.
    pub is_directory: bool,
    /// Whether Core can inspect the directory contents.
    pub is_readable: bool,
    /// Whether Core can create repository metadata there in a later init task.
    pub is_writable: bool,
    /// Whether the directory has no user-visible entries.
    pub is_empty: bool,
    /// Whether `.areamatrix/` metadata already exists under the selected path.
    pub is_initialized: bool,
    /// Whether the selected path is inside an `.areamatrix/` metadata directory.
    pub is_inside_area_matrix: bool,
    /// Whether the path appears to be managed by iCloud.
    pub is_icloud_path: bool,
    /// Whether the path appears to be managed by OneDrive.
    pub is_onedrive_path: bool,
    /// Platform-neutral location classification for UI routing and risk copy.
    pub platform_path_kind: PlatformPathKind,
    /// Whether callers should treat path comparison as case-sensitive.
    pub is_case_sensitive_path: bool,
    /// Whether the latest scan session is still running, paused, failed, or interrupted.
    pub has_unfinished_scan_session: bool,
    /// Suggested initialization mode when the path is eligible.
    pub recommended_mode: Option<RepoInitMode>,
    /// Structured issues the UI can display without parsing error text.
    pub issues: Vec<RepoPathIssue>,
}
