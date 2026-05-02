//! Shared error types for the AreaMatrix core.

use thiserror::Error;

/// Result alias used by all fallible core APIs.
pub type CoreResult<T> = Result<T, CoreError>;

/// Error variants exposed through the UniFFI boundary.
#[derive(Clone, Debug, Eq, Error, PartialEq)]
pub enum CoreError {
    /// Underlying filesystem or IO failure.
    #[error("io")]
    Io,
    /// SQLite or repository metadata failure.
    #[error("db")]
    Db,
    /// Configuration validation or persistence failure.
    #[error("config")]
    Config,
    /// Classification rule failure.
    #[error("classify")]
    Classify,
    /// Path or naming conflict.
    #[error("conflict")]
    Conflict,
    /// Duplicate file detected, with the first active path that owns the hash.
    #[error("duplicate file already exists at: {existing_path}")]
    DuplicateFile { existing_path: String },
    /// Requested file does not exist.
    #[error("file not found")]
    FileNotFound,
    /// Repository has not been initialized.
    #[error("repo not initialized")]
    RepoNotInitialized,
    /// Path is outside the allowed repository boundary or otherwise invalid.
    #[error("invalid path")]
    InvalidPath,
    /// iCloud placeholder has not been downloaded.
    #[error("icloud placeholder")]
    ICloudPlaceholder,
    /// Filesystem permission is insufficient.
    #[error("permission denied")]
    PermissionDenied,
    /// Placeholder for unimplemented or unexpected internal failures.
    #[error("internal")]
    Internal,
}
