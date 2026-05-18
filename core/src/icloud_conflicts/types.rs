use std::path::PathBuf;

use crate::{ICloudConflictPair, ICloudConflictStatus, ICloudConflictVersionRole};

pub(super) struct ConflictCandidate {
    pub(super) relative_path: String,
    pub(super) original_relative_path: Option<String>,
    pub(super) original_modified_at: Option<i64>,
    pub(super) conflicted_modified_at: i64,
    pub(super) uncertainty_reason: Option<String>,
}

pub(super) struct ConflictBinding {
    pub(super) conflict_id: String,
    pub(super) original_relative_path: Option<String>,
    pub(super) conflicted_relative_path: String,
    pub(super) original_path: Option<PathBuf>,
    pub(super) conflicted_path: PathBuf,
}

pub(super) struct VersionState {
    pub(super) role: ICloudConflictVersionRole,
    pub(super) relative_path: String,
    pub(super) absolute_path: PathBuf,
    pub(super) modified_at: i64,
    pub(super) size_bytes: i64,
    pub(super) hash_sha256: String,
}

impl ConflictCandidate {
    pub(super) fn into_pair(self) -> ICloudConflictPair {
        ICloudConflictPair {
            conflict_id: self.relative_path.clone(),
            original_path: self.original_relative_path,
            conflicted_copy_path: self.relative_path,
            original_modified_at: self.original_modified_at,
            conflicted_modified_at: self.conflicted_modified_at,
            status: ICloudConflictStatus::NeedsReview,
            uncertainty_reason: self.uncertainty_reason,
        }
    }
}
