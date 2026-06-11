use std::path::Path;

use crate::{CoreError, ImportSourceRemovalStatus, StorageMode};

use super::safe_move::remove_imported_source;

pub(crate) struct SourceRemovalOutcome {
    pub(crate) status: ImportSourceRemovalStatus,
    pub(crate) failure: Option<String>,
}

pub(crate) fn finalize_source_removal(mode: &StorageMode, source: &Path) -> SourceRemovalOutcome {
    if !matches!(mode, StorageMode::Moved) {
        return SourceRemovalOutcome {
            status: ImportSourceRemovalStatus::NotRequested,
            failure: None,
        };
    }
    match remove_imported_source(source) {
        Ok(()) => SourceRemovalOutcome {
            status: ImportSourceRemovalStatus::Removed,
            failure: None,
        },
        Err(error) => SourceRemovalOutcome {
            status: ImportSourceRemovalStatus::Retained,
            failure: Some(source_removal_failure_reason(error)),
        },
    }
}

fn source_removal_failure_reason(error: CoreError) -> String {
    match error {
        CoreError::PermissionDenied { path }
        | CoreError::InvalidPath { path }
        | CoreError::FileNotFound { path }
        | CoreError::ICloudPlaceholder { path }
        | CoreError::Conflict { path } => path,
        CoreError::Io { message }
        | CoreError::Db { message }
        | CoreError::Internal { message }
        | CoreError::RepoNotInitialized { path: message } => message,
        CoreError::StagingRecoveryRequired { path } => path,
        CoreError::Config { reason }
        | CoreError::Validation { reason }
        | CoreError::Classify { reason } => reason,
        CoreError::DuplicateFile { existing_path } => existing_path,
        CoreError::ExpiredAction { action_id } => action_id,
    }
}
