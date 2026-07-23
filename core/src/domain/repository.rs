use serde::{Deserialize, Serialize};

use super::file::StorageMode;
use crate::{CoreError, CoreResult};

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

/// Concrete language frozen for one content-producing operation.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ContentLocale {
    /// Simplified Chinese content.
    ZhHans,
    /// English content.
    En,
}

impl ContentLocale {
    /// Stable persisted identifier used by SQLite and generated files.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::ZhHans => "zh-Hans",
            Self::En => "en",
        }
    }

    /// Parses a concrete locale without accepting repository policies.
    pub fn parse(value: &str) -> Option<Self> {
        match value.trim() {
            "zh-Hans" => Some(Self::ZhHans),
            "en" => Some(Self::En),
            _ => None,
        }
    }
}

/// Converts typed FFI values and validated Rust compatibility inputs into a
/// concrete content locale.
pub trait ContentLocaleInput {
    /// Resolves the input or rejects unsupported policy-like values.
    fn into_content_locale(self) -> CoreResult<ContentLocale>;
}

impl ContentLocaleInput for ContentLocale {
    fn into_content_locale(self) -> CoreResult<ContentLocale> {
        Ok(self)
    }
}

impl ContentLocaleInput for String {
    fn into_content_locale(self) -> CoreResult<ContentLocale> {
        ContentLocale::parse(&self)
            .ok_or_else(|| CoreError::config("unsupported content locale"))
    }
}

impl ContentLocaleInput for &str {
    fn into_content_locale(self) -> CoreResult<ContentLocale> {
        ContentLocale::parse(self).ok_or_else(|| CoreError::config("unsupported content locale"))
    }
}

/// Canonical repository content-language policy accepted for writes.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RepositoryLocalePolicy {
    /// Resolve from the application interface language at operation start.
    FollowInterface,
    /// Always generate Simplified Chinese content.
    ZhHans,
    /// Always generate English content.
    En,
}

impl RepositoryLocalePolicy {
    /// Stable persisted representation.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::FollowInterface => "system",
            Self::ZhHans => "zh-Hans",
            Self::En => "en",
        }
    }
}

/// Read state for a persisted repository locale, including unsupported values.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum RepositoryLocalePolicyState {
    /// Canonical follow-interface policy.
    FollowInterface,
    /// Canonical or compatible Simplified Chinese policy.
    ZhHans,
    /// Canonical or compatible English policy.
    En,
    /// Non-empty value unknown to this Core version.
    Unsupported,
}

/// Exact persisted repository locale together with its interpreted state.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RepositoryLocalePolicySnapshot {
    /// Interpreted read state.
    pub state: RepositoryLocalePolicyState,
    /// Exact persisted bytes after UTF-8 decoding; never silently rewritten.
    pub raw_value: String,
}

impl RepositoryLocalePolicySnapshot {
    /// Interprets a persisted locale while preserving its exact value.
    pub fn from_raw(raw_value: String) -> Self {
        let trimmed = raw_value.trim();
        let normalized = trimmed.replace('_', "-").to_ascii_lowercase();
        let state = match trimmed {
            "" | "system" => RepositoryLocalePolicyState::FollowInterface,
            "zh-Hans" | "zh-CN" | "zh-SG" => RepositoryLocalePolicyState::ZhHans,
            "en" => RepositoryLocalePolicyState::En,
            _ if normalized.starts_with("zh-hans-") => RepositoryLocalePolicyState::ZhHans,
            _ if normalized.starts_with("en-") => RepositoryLocalePolicyState::En,
            _ => RepositoryLocalePolicyState::Unsupported,
        };
        Self { state, raw_value }
    }

    /// Whether this value is canonical and safe to use for normal writes.
    pub fn is_canonical(&self) -> bool {
        matches!(
            (self.state.clone(), self.raw_value.as_str()),
            (RepositoryLocalePolicyState::FollowInterface, "system")
                | (RepositoryLocalePolicyState::ZhHans, "zh-Hans")
                | (RepositoryLocalePolicyState::En, "en")
        )
    }
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

/// Revisioned repository configuration returned across the FFI boundary.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RepoConfigSnapshot {
    /// Repository root path.
    pub repo_path: String,
    /// Monotonic revision used for compare-and-swap updates.
    pub revision: i64,
    /// Default storage behavior for imports.
    pub default_mode: StorageMode,
    /// Overview output location.
    pub overview_output: OverviewOutput,
    /// Whether AI features are enabled.
    pub ai_enabled: bool,
    /// Repository content-language policy with exact-value preservation.
    pub locale_policy: RepositoryLocalePolicySnapshot,
    /// Whether iCloud warnings are shown.
    pub icloud_warn: bool,
    /// Whether extension-based classifier rules are enabled.
    pub enable_extension_rules: bool,
    /// Whether keyword-based classifier rules are enabled.
    pub enable_keyword_rules: bool,
    /// Whether unmatched files fall back to inbox.
    pub fallback_to_inbox: bool,
    /// Whether import flows may expose the replace option.
    pub allow_replace_during_import: bool,
}

impl RepoConfigSnapshot {
    /// Builds a public snapshot without losing the exact locale value.
    pub fn from_config(config: RepoConfig, revision: i64) -> Self {
        Self {
            repo_path: config.repo_path,
            revision,
            default_mode: config.default_mode,
            overview_output: config.overview_output,
            ai_enabled: config.ai_enabled,
            locale_policy: RepositoryLocalePolicySnapshot::from_raw(config.locale),
            icloud_warn: config.icloud_warn,
            enable_extension_rules: config.enable_extension_rules,
            enable_keyword_rules: config.enable_keyword_rules,
            fallback_to_inbox: config.fallback_to_inbox,
            allow_replace_during_import: config.allow_replace_during_import,
        }
    }
}

/// Field-level compare-and-swap update for repository configuration.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct RepoConfigPatch {
    /// Revision observed by the editing window.
    pub expected_revision: i64,
    /// Optional default storage behavior replacement.
    pub default_mode: Option<StorageMode>,
    /// Optional overview output replacement.
    pub overview_output: Option<OverviewOutput>,
    /// Optional AI enabled replacement.
    pub ai_enabled: Option<bool>,
    /// Optional canonical repository content-language policy replacement.
    pub locale_policy: Option<RepositoryLocalePolicy>,
    /// Optional iCloud warning replacement.
    pub icloud_warn: Option<bool>,
    /// Optional extension-rule toggle replacement.
    pub enable_extension_rules: Option<bool>,
    /// Optional keyword-rule toggle replacement.
    pub enable_keyword_rules: Option<bool>,
    /// Optional unmatched-file fallback replacement.
    pub fallback_to_inbox: Option<bool>,
    /// Optional dangerous import replacement toggle.
    pub allow_replace_during_import: Option<bool>,
}

impl RepoConfigPatch {
    /// Whether the patch contains any field mutation.
    pub fn is_empty(&self) -> bool {
        self.default_mode.is_none()
            && self.overview_output.is_none()
            && self.ai_enabled.is_none()
            && self.locale_policy.is_none()
            && self.icloud_warn.is_none()
            && self.enable_extension_rules.is_none()
            && self.enable_keyword_rules.is_none()
            && self.fallback_to_inbox.is_none()
            && self.allow_replace_during_import.is_none()
    }

    /// Whether locale canonicalization is the patch's only mutation.
    pub fn is_locale_only(&self) -> bool {
        self.locale_policy.is_some()
            && self.default_mode.is_none()
            && self.overview_output.is_none()
            && self.ai_enabled.is_none()
            && self.icloud_warn.is_none()
            && self.enable_extension_rules.is_none()
            && self.enable_keyword_rules.is_none()
            && self.fallback_to_inbox.is_none()
            && self.allow_replace_during_import.is_none()
    }
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
    /// Persisted repository content-language policy.
    pub locale_policy: RepositoryLocalePolicy,
    /// Resolved content locale frozen when initialization starts.
    pub content_locale: ContentLocale,
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
