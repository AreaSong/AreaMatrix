use super::templates::{
    is_db_corrupted_message, is_db_locked_message, mapping_template_for_kind, ErrorMappingTemplate,
    DB_CORRUPTED_MAPPING, DB_LOCKED_MAPPING,
};
use super::types::{ErrorKind, ErrorMapping};
use thiserror::Error;

/// Error variants exposed through the UniFFI boundary.
///
/// error mapping treats each variant and payload as the structured input for Swift-side
/// error presentation. App code should branch on variants and payloads, not on
/// localized strings or `Display` output. Mapping an error to UI severity, user
/// copy, suggested action, and recoverability is side-effect free: it must not
/// inspect the filesystem, open the database, write logs, or mutate repository
/// state.
#[derive(Clone, Debug, Eq, Error, PartialEq)]
pub enum CoreError {
    /// Underlying filesystem or IO failure.
    #[error("io error: {message}")]
    Io { message: String },
    /// SQLite or repository metadata failure.
    #[error("db error: {message}")]
    Db { message: String },
    /// Configuration validation or persistence failure.
    #[error("config error: {reason}")]
    Config { reason: String },
    /// User input validation failure.
    #[error("validation error: {reason}")]
    Validation { reason: String },
    /// Classification rule failure.
    #[error("classification failed: {reason}")]
    Classify { reason: String },
    /// Path or naming conflict.
    #[error("path conflict: {path}")]
    Conflict { path: String },
    /// Duplicate file detected, with the first active path that owns the hash.
    #[error("duplicate file already exists at: {existing_path}")]
    DuplicateFile { existing_path: String },
    /// Requested file does not exist.
    #[error("file not found: {path}")]
    FileNotFound { path: String },
    /// Undo or redo action is no longer available.
    #[error("expired action: {action_id}")]
    ExpiredAction { action_id: String },
    /// Repository has not been initialized.
    #[error("repo not initialized at: {path}")]
    RepoNotInitialized { path: String },
    /// Path is outside the allowed repository boundary or otherwise invalid.
    #[error("invalid path: {path}")]
    InvalidPath { path: String },
    /// iCloud placeholder has not been downloaded.
    #[error("iCloud placeholder not downloaded: {path}")]
    ICloudPlaceholder { path: String },
    /// Import staging state must be recovered before continuing.
    #[error("staging recovery required: {path}")]
    StagingRecoveryRequired { path: String },
    /// Filesystem permission is insufficient.
    #[error("permission denied: {path}")]
    PermissionDenied { path: String },
    /// Placeholder for unimplemented or unexpected internal failures.
    #[error("internal error: {message}")]
    Internal { message: String },
}

impl CoreError {
    fn mapping_template(&self) -> &'static ErrorMappingTemplate {
        match self {
            Self::Db { message } if is_db_corrupted_message(message) => &DB_CORRUPTED_MAPPING,
            Self::Db { message } if is_db_locked_message(message) => &DB_LOCKED_MAPPING,
            _ => mapping_template_for_kind(&self.kind()),
        }
    }

    /// Creates an IO error with the raw source message.
    pub fn io(message: impl Into<String>) -> Self {
        Self::Io {
            message: message.into(),
        }
    }

    /// Creates a database error with the raw database message.
    pub fn db(message: impl Into<String>) -> Self {
        Self::Db {
            message: message.into(),
        }
    }

    /// Creates a configuration error with a user-actionable reason.
    pub fn config(reason: impl Into<String>) -> Self {
        Self::Config {
            reason: reason.into(),
        }
    }

    /// Creates a validation error with a user-actionable reason.
    pub fn validation(reason: impl Into<String>) -> Self {
        Self::Validation {
            reason: reason.into(),
        }
    }

    /// Creates a classification error with a user-actionable reason.
    pub fn classify(reason: impl Into<String>) -> Self {
        Self::Classify {
            reason: reason.into(),
        }
    }

    /// Creates a conflict error with the conflicting path.
    pub fn conflict(path: impl Into<String>) -> Self {
        Self::Conflict { path: path.into() }
    }

    /// Creates a file-not-found error with the missing path.
    pub fn file_not_found(path: impl Into<String>) -> Self {
        Self::FileNotFound { path: path.into() }
    }

    /// Creates an expired-action error with the blocked action id.
    pub fn expired_action(action_id: impl Into<String>) -> Self {
        Self::ExpiredAction {
            action_id: action_id.into(),
        }
    }

    /// Creates a repo-not-initialized error with the repository path.
    pub fn repo_not_initialized(path: impl Into<String>) -> Self {
        Self::RepoNotInitialized { path: path.into() }
    }

    /// Creates an invalid-path error with the rejected path or input.
    pub fn invalid_path(path: impl Into<String>) -> Self {
        Self::InvalidPath { path: path.into() }
    }

    /// Creates an iCloud placeholder error with the unavailable path.
    pub fn icloud_placeholder(path: impl Into<String>) -> Self {
        Self::ICloudPlaceholder { path: path.into() }
    }

    /// Creates a staging-recovery-required error with the blocked path.
    pub fn staging_recovery_required(path: impl Into<String>) -> Self {
        Self::StagingRecoveryRequired { path: path.into() }
    }

    /// Creates a permission error with the blocked path.
    pub fn permission_denied(path: impl Into<String>) -> Self {
        Self::PermissionDenied { path: path.into() }
    }

    /// Creates an internal error with the raw internal message.
    pub fn internal(message: impl Into<String>) -> Self {
        Self::Internal {
            message: message.into(),
        }
    }

    /// Returns the stable category for this error.
    pub fn kind(&self) -> ErrorKind {
        match self {
            Self::Io { .. } => ErrorKind::Io,
            Self::Db { .. } => ErrorKind::Db,
            Self::Config { .. } => ErrorKind::Config,
            Self::Validation { .. } => ErrorKind::Validation,
            Self::Classify { .. } => ErrorKind::Classify,
            Self::Conflict { .. } => ErrorKind::Conflict,
            Self::DuplicateFile { .. } => ErrorKind::DuplicateFile,
            Self::FileNotFound { .. } => ErrorKind::FileNotFound,
            Self::ExpiredAction { .. } => ErrorKind::ExpiredAction,
            Self::RepoNotInitialized { .. } => ErrorKind::RepoNotInitialized,
            Self::InvalidPath { .. } => ErrorKind::InvalidPath,
            Self::ICloudPlaceholder { .. } => ErrorKind::ICloudPlaceholder,
            Self::StagingRecoveryRequired { .. } => ErrorKind::StagingRecoveryRequired,
            Self::PermissionDenied { .. } => ErrorKind::PermissionDenied,
            Self::Internal { .. } => ErrorKind::Internal,
        }
    }

    /// Returns the raw path, reason, or message carried by the error.
    pub fn raw_context(&self) -> &str {
        match self {
            Self::Io { message } | Self::Db { message } | Self::Internal { message } => message,
            Self::Config { reason } | Self::Validation { reason } | Self::Classify { reason } => {
                reason
            }
            Self::ExpiredAction { action_id } => action_id,
            Self::Conflict { path }
            | Self::FileNotFound { path }
            | Self::RepoNotInitialized { path }
            | Self::InvalidPath { path }
            | Self::ICloudPlaceholder { path }
            | Self::StagingRecoveryRequired { path }
            | Self::PermissionDenied { path } => path,
            Self::DuplicateFile { existing_path } => existing_path,
        }
    }

    /// Maps a structured `CoreError` to UI metadata without side effects.
    pub fn to_error_mapping(&self) -> ErrorMapping {
        let kind = self.kind();
        let template = self.mapping_template();

        ErrorMapping {
            kind,
            user_message: template.user_message.to_owned(),
            severity: template.severity.clone(),
            suggested_action: template.suggested_action.to_owned(),
            recoverability: template.recoverability.clone(),
            raw_context: self.raw_context().to_owned(),
        }
    }
}
