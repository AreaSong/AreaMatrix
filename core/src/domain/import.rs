use serde::{Deserialize, Serialize};

use super::file::{FileEntry, StorageMode};
use super::repository::ContentLocale;

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

/// How duplicate file hashes should be handled.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum DuplicateStrategy {
    /// Do not import the duplicate.
    Skip,
    /// Replace the existing active entry after the UI has confirmed the danger.
    Overwrite,
    /// Keep both files with conflict-free naming.
    KeepBoth,
    /// Return a duplicate error so the UI can ask the user.
    Ask,
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
    /// Resolved content locale frozen when the import starts.
    pub content_locale: ContentLocale,
}

/// Final source-file outcome for a committed import.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum ImportSourceRemovalStatus {
    /// Copy or index mode did not request source removal.
    NotRequested,
    /// Move mode removed the original source after repository commit.
    Removed,
    /// Move mode committed the repository file but could not remove the original source.
    Retained,
}

/// Structured result returned by desktop import flows.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ImportResult {
    /// Active file entry created or replaced by the import.
    pub entry: FileEntry,
    /// Source-file outcome after the repository file and metadata are safe.
    pub source_removal_status: ImportSourceRemovalStatus,
    /// Failure reason when `source_removal_status` is `Retained`.
    pub source_removal_failure: Option<String>,
}
