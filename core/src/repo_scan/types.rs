use std::path::PathBuf;

use crate::{
    db::{FileIndexInput, ScanFileSnapshot},
    FileOrigin, ScanSessionKind, StorageMode,
};

pub(super) struct ScanPlan {
    pub(super) files: Vec<AdoptFile>,
    pub(super) skipped: i64,
}

pub(super) struct AdoptFile {
    pub(super) path: PathBuf,
    pub(super) relative_path: String,
}

#[derive(Clone)]
pub(super) struct FileSnapshot {
    pub(super) path: String,
    original_name: String,
    current_name: String,
    category: String,
    size_bytes: i64,
    pub(super) hash_sha256: String,
    pub(super) storage_mode: StorageMode,
    origin: FileOrigin,
    pub(super) source_path: Option<String>,
}

impl FileSnapshot {
    pub(super) fn matches(&self, input: &FileIndexInput, origin: FileOrigin) -> bool {
        self.original_name == input.original_name
            && self.current_name == input.current_name
            && self.category == input.category
            && self.size_bytes == input.size_bytes
            && self.hash_sha256 == input.hash_sha256
            && self.storage_mode == StorageMode::Indexed
            && self.origin == origin
    }
}

impl From<ScanFileSnapshot> for FileSnapshot {
    fn from(entry: ScanFileSnapshot) -> Self {
        Self {
            path: entry.path,
            original_name: entry.original_name,
            current_name: entry.current_name,
            category: entry.category,
            size_bytes: entry.size_bytes,
            hash_sha256: entry.hash_sha256,
            storage_mode: entry.storage_mode,
            origin: entry.origin,
            source_path: entry.source_path,
        }
    }
}

#[derive(Clone, Copy, Eq, PartialEq)]
pub(super) enum DuplicateHashReviewState {
    None,
    RenamedCandidate,
    Conflict,
}

#[derive(Clone, Copy)]
pub(super) enum ScanMode {
    Adopt,
    Reindex,
}

impl ScanMode {
    pub(super) fn from_kind(kind: &ScanSessionKind) -> Self {
        match kind {
            ScanSessionKind::Adopt => Self::Adopt,
            ScanSessionKind::Reindex => Self::Reindex,
        }
    }
}
