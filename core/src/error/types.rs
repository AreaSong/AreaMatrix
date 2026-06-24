/// Stable error category exposed to Swift without requiring string parsing.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ErrorKind {
    /// Underlying filesystem or IO failure.
    Io,
    /// SQLite or repository metadata failure.
    Db,
    /// Configuration validation or persistence failure.
    Config,
    /// User input validation failed.
    Validation,
    /// Classification rule failure.
    Classify,
    /// Path or naming conflict.
    Conflict,
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
}

/// User-facing error mapping metadata returned to Swift.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ErrorMapping {
    /// Stable error category.
    pub kind: ErrorKind,
    /// Localizable short user message.
    pub user_message: String,
    /// Severity used to select the UI treatment.
    pub severity: ErrorSeverity,
    /// Suggested next action for the user.
    pub suggested_action: String,
    /// Recovery posture for retries and blocking states.
    pub recoverability: ErrorRecoverability,
    /// Raw path, reason, or message for logs and detailed UI.
    pub raw_context: String,
}
