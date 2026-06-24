use super::core_error::CoreError;
use super::types::{ErrorKind, ErrorMapping, ErrorMappingInput};

impl ErrorMappingInput {
    fn into_core_error(self) -> CoreError {
        let path = self.path.unwrap_or_else(|| "unknown path".to_owned());
        let reason = self
            .reason
            .unwrap_or_else(|| "unspecified reason".to_owned());
        let message = self
            .message
            .unwrap_or_else(|| "unspecified message".to_owned());

        match self.kind {
            ErrorKind::Io => CoreError::Io { message },
            ErrorKind::Db => CoreError::Db { message },
            ErrorKind::Config => CoreError::Config { reason },
            ErrorKind::Validation => CoreError::Validation { reason },
            ErrorKind::Classify => CoreError::Classify { reason },
            ErrorKind::Conflict => CoreError::Conflict { path },
            ErrorKind::DuplicateFile => CoreError::DuplicateFile {
                existing_path: path,
            },
            ErrorKind::FileNotFound => CoreError::FileNotFound { path },
            ErrorKind::ExpiredAction => CoreError::ExpiredAction { action_id: path },
            ErrorKind::RepoNotInitialized => CoreError::RepoNotInitialized { path },
            ErrorKind::InvalidPath => CoreError::InvalidPath { path },
            ErrorKind::ICloudPlaceholder => CoreError::ICloudPlaceholder { path },
            ErrorKind::StagingRecoveryRequired => CoreError::StagingRecoveryRequired { path },
            ErrorKind::PermissionDenied => CoreError::PermissionDenied { path },
            ErrorKind::Internal => CoreError::Internal { message },
        }
    }
}

/// Maps a structured error input to user-facing metadata.
///
/// This contract exists for error mapping consumers that need the same mapping metadata
/// without first calling an API that throws `CoreError`. It is deterministic and
/// side-effect free.
pub fn map_core_error(input: ErrorMappingInput) -> ErrorMapping {
    input.into_core_error().to_error_mapping()
}
