/// Stable error category exposed to Swift without requiring string parsing.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ErrorKind {
    /// Underlying filesystem or IO failure.
    Io,
    /// SQLite or repository metadata failure.
    Db,
    /// SQLite busy or locked condition.
    DbLocked,
    /// SQLite corruption or not-a-database condition.
    DbCorrupted,
    /// Configuration validation or persistence failure.
    Config,
    /// User input validation failed.
    Validation,
    /// Classification rule failure.
    Classify,
    /// Path or naming conflict.
    Conflict,
    /// Optimistic revision compare-and-swap conflict.
    RevisionConflict,
    /// Duplicate file detected.
    DuplicateFile,
    /// Requested file does not exist.
    FileNotFound,
    /// Undo or redo action is no longer available.
    ExpiredAction,
    /// Repository has not been initialized.
    RepoNotInitialized,
    /// Path is invalid or outside the allowed boundary.
    InvalidPath,
    /// iCloud placeholder has not been downloaded.
    ICloudPlaceholder,
    /// Import staging state must be recovered before continuing.
    StagingRecoveryRequired,
    /// Filesystem permission is insufficient.
    PermissionDenied,
    /// Unexpected internal failure.
    Internal,
}

/// User-facing severity used by Swift to choose toast, banner, or modal UI.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ErrorSeverity {
    /// Low interruption, usually a short toast.
    Low,
    /// Medium interruption, usually a dismissible banner.
    Medium,
    /// High interruption, usually a modal alert.
    High,
    /// Critical interruption, usually blocking recovery UI.
    Critical,
}

/// Recovery posture for the mapped error.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ErrorRecoverability {
    /// Retrying the same operation can succeed without changing input.
    Retryable,
    /// The user must change permissions, config, path, or import decision.
    UserActionRequired,
    /// The UI should refresh state before allowing a retry.
    RefreshRequired,
    /// Recovery must leave the current flow and enter a blocking error state.
    Fatal,
}

/// FFI-safe input used when Swift wants mapping metadata without throwing.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ErrorMappingInput {
    /// Error category corresponding to a `CoreError` variant.
    pub kind: ErrorKind,
    /// Original path when the error is path based.
    pub path: Option<String>,
    /// Original reason when the error is configuration or classifier based.
    pub reason: Option<String>,
    /// Original message when the error comes from IO, DB, or internal code.
    pub message: Option<String>,
    /// Revision observed by the caller for a revision conflict.
    pub expected_revision: Option<i64>,
    /// Current persisted revision for a revision conflict.
    pub current_revision: Option<i64>,
}

/// Stable named argument used by Swift when localizing error presentation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ErrorArgument {
    /// Stable argument name.
    pub name: String,
    /// Verbatim argument value.
    pub value: String,
}

/// Structured, non-localized error metadata returned to Swift.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ErrorMapping {
    /// Stable error category.
    pub kind: ErrorKind,
    /// Stable error code used as the String Catalog lookup key.
    pub code: String,
    /// Optional stable field identifier.
    pub field: Option<String>,
    /// Stable named arguments whose values remain verbatim.
    pub arguments: Vec<ErrorArgument>,
    /// Stable recovery action identifiers.
    pub recovery_action_ids: Vec<String>,
    /// Severity used to select the UI treatment.
    pub severity: ErrorSeverity,
    /// Recovery posture for retries and blocking states.
    pub recoverability: ErrorRecoverability,
    /// Optional verbatim technical detail for a controlled disclosure surface.
    pub technical_details: Option<String>,
}
