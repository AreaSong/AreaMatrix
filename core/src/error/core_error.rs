use super::templates::{mapping_template_for_kind, ErrorMappingTemplate};
use super::types::{ErrorArgument, ErrorKind, ErrorMapping};
use thiserror::Error;

/// Error variants exposed through the UniFFI boundary.
///
/// error mapping treats each variant and payload as the structured input for Swift-side
/// error presentation. App code should branch on variants and payloads, not on
/// localized strings or `Display` output. Mapping an error to a stable code,
/// named arguments, recovery action identifiers, severity, and recoverability
/// is side-effect free: it must not
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
    /// SQLite reported a typed busy or locked condition.
    #[error("database locked: {message}")]
    DbLocked { message: String },
    /// SQLite reported a typed corruption or not-a-database condition.
    #[error("database corrupted: {message}")]
    DbCorrupted { message: String },
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
    /// Optimistic revision compare-and-swap conflict.
    #[error(
        "revision conflict for {resource}: expected {expected_revision}, current {current_revision}"
    )]
    RevisionConflict {
        resource: String,
        expected_revision: i64,
        current_revision: i64,
    },
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
    /// Unexpected internal failure or invariant violation.
    #[error("internal error: {message}")]
    Internal { message: String },
}

impl CoreError {
    fn mapping_template(&self) -> &'static ErrorMappingTemplate {
        mapping_template_for_kind(&self.kind())
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

    /// Creates a typed SQLite busy or locked error.
    pub fn db_locked(message: impl Into<String>) -> Self {
        Self::DbLocked {
            message: message.into(),
        }
    }

    /// Creates a typed SQLite corruption error.
    pub fn db_corrupted(message: impl Into<String>) -> Self {
        Self::DbCorrupted {
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

    /// Creates a typed optimistic revision conflict.
    pub fn revision_conflict(
        resource: impl Into<String>,
        expected_revision: i64,
        current_revision: i64,
    ) -> Self {
        Self::RevisionConflict {
            resource: resource.into(),
            expected_revision,
            current_revision,
        }
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
            Self::DbLocked { .. } => ErrorKind::DbLocked,
            Self::DbCorrupted { .. } => ErrorKind::DbCorrupted,
            Self::Config { .. } => ErrorKind::Config,
            Self::Validation { .. } => ErrorKind::Validation,
            Self::Classify { .. } => ErrorKind::Classify,
            Self::Conflict { .. } => ErrorKind::Conflict,
            Self::RevisionConflict { .. } => ErrorKind::RevisionConflict,
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
            Self::Io { message }
            | Self::Db { message }
            | Self::DbLocked { message }
            | Self::DbCorrupted { message }
            | Self::Internal { message } => message,
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
            Self::RevisionConflict { resource, .. } => resource,
        }
    }

    /// Maps a structured `CoreError` to UI metadata without side effects.
    pub fn to_error_mapping(&self) -> ErrorMapping {
        let kind = self.kind();
        let template = self.mapping_template();

        let code = match self {
            Self::RevisionConflict { resource, .. } if resource == "repo_config" => {
                "repo_config_revision_conflict"
            }
            _ => template.code,
        };
        ErrorMapping {
            kind,
            code: code.to_owned(),
            field: template.field.map(str::to_owned),
            arguments: self.error_arguments(),
            recovery_action_ids: template
                .recovery_action_ids
                .iter()
                .map(|value| (*value).to_owned())
                .collect(),
            severity: template.severity.clone(),
            recoverability: template.recoverability.clone(),
            technical_details: self.technical_details(),
        }
    }

    fn error_arguments(&self) -> Vec<ErrorArgument> {
        let argument = |name: &str, value: &str| ErrorArgument {
            name: name.to_owned(),
            value: value.to_owned(),
        };
        match self {
            Self::Conflict { path }
            | Self::FileNotFound { path }
            | Self::RepoNotInitialized { path }
            | Self::InvalidPath { path }
            | Self::ICloudPlaceholder { path }
            | Self::StagingRecoveryRequired { path }
            | Self::PermissionDenied { path } => vec![argument("path", path)],
            Self::DuplicateFile { existing_path } => {
                vec![argument("existing_path", existing_path)]
            }
            Self::ExpiredAction { action_id } => vec![argument("action_id", action_id)],
            Self::Config { reason } | Self::Validation { reason } | Self::Classify { reason } => {
                vec![argument("reason", reason)]
            }
            Self::RevisionConflict {
                resource,
                expected_revision,
                current_revision,
            } => vec![
                argument("resource", resource),
                argument("expected_revision", &expected_revision.to_string()),
                argument("current_revision", &current_revision.to_string()),
            ],
            Self::Io { .. }
            | Self::Db { .. }
            | Self::DbLocked { .. }
            | Self::DbCorrupted { .. }
            | Self::Internal { .. } => Vec::new(),
        }
    }

    fn technical_details(&self) -> Option<String> {
        match self {
            Self::RevisionConflict { .. } => None,
            _ => {
                let value = self.raw_context();
                (!value.is_empty()).then(|| value.to_owned())
            }
        }
    }
}
