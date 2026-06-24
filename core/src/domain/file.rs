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

/// Read-only availability of the file behind a metadata row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum FileAvailabilityStatus {
    /// The backing file is present or its availability is owned by another platform capability.
    Available,
    /// The metadata row is retained but the backing file is missing from its expected location.
    Missing,
}

/// A file entry visible through the core API.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FileEntry {
    /// Stable database identifier.
    pub id: i64,
    /// Path displayed for this entry.
    ///
    /// Repository-owned, adopted, and external reindex rows use a
    /// repository-relative path. Imported indexed rows point at the external
    /// source path and also preserve the same value in `source_path`.
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
    /// Read-only file availability status for list/detail consumers.
    pub availability_status: FileAvailabilityStatus,
    /// Unix timestamp for initial import.
    pub imported_at: i64,
    /// Unix timestamp for last update.
    pub updated_at: i64,
}

/// Read-only preview for a category move.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct MoveToCategoryPreview {
    /// Stable database identifier for the active file.
    pub file_id: i64,
    /// Current category slug before confirmation.
    pub from_category: String,
    /// Target category slug requested by the caller.
    pub to_category: String,
    /// Current entry path before confirmation.
    pub current_path: String,
    /// Final path that `move_to_category` will use if the user confirms.
    pub target_path: String,
    /// Final file name that `move_to_category` will use if the user confirms.
    pub target_name: String,
    /// Storage behavior for this entry.
    pub storage_mode: StorageMode,
    /// Whether confirmation only changes metadata and never moves an external file.
    pub index_only: bool,
    /// Whether name-conflict numbering changed the final file name.
    pub name_conflict_resolved: bool,
    /// Whether confirmation will physically move a repo-owned file.
    pub will_move_file: bool,
}
