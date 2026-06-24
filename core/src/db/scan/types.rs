use crate::{FileOrigin, StorageMode};

#[derive(Debug)]
pub(crate) struct FileIndexInput {
    pub path: String,
    pub original_name: String,
    pub current_name: String,
    pub category: String,
    pub size_bytes: i64,
    pub hash_sha256: String,
}

#[derive(Debug)]
pub(crate) struct ScanFileSnapshot {
    pub path: String,
    pub original_name: String,
    pub current_name: String,
    pub category: String,
    pub size_bytes: i64,
    pub hash_sha256: String,
    pub storage_mode: StorageMode,
    pub origin: FileOrigin,
    pub source_path: Option<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum ScanFileChange {
    Inserted,
    Updated,
    Missing,
    Conflict,
    Unreadable,
    Unknown,
    Skipped,
}
