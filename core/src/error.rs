//! Shared error and error-mapping contract types for the AreaMatrix core.

use thiserror::Error;

/// Result alias used by all fallible core APIs.
pub type CoreResult<T> = Result<T, CoreError>;

/// Stable error category exposed to Swift without requiring string parsing.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ErrorKind {
    /// Underlying filesystem or IO failure.
    Io,
    /// SQLite or repository metadata failure.
    Db,
    /// Configuration validation or persistence failure.
    Config,
    /// Classification rule failure.
    Classify,
    /// Path or naming conflict.
    Conflict,
    /// Duplicate file detected.
    DuplicateFile,
    /// Requested file does not exist.
    FileNotFound,
    /// Repository has not been initialized.
    RepoNotInitialized,
    /// Path is invalid or outside the allowed boundary.
    InvalidPath,
    /// iCloud placeholder has not been downloaded.
    ICloudPlaceholder,
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

/// Error variants exposed through the UniFFI boundary.
///
/// C1-21 treats each variant and payload as the structured input for Swift-side
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
    /// Repository has not been initialized.
    #[error("repo not initialized at: {path}")]
    RepoNotInitialized { path: String },
    /// Path is outside the allowed repository boundary or otherwise invalid.
    #[error("invalid path: {path}")]
    InvalidPath { path: String },
    /// iCloud placeholder has not been downloaded.
    #[error("iCloud placeholder not downloaded: {path}")]
    ICloudPlaceholder { path: String },
    /// Filesystem permission is insufficient.
    #[error("permission denied: {path}")]
    PermissionDenied { path: String },
    /// Placeholder for unimplemented or unexpected internal failures.
    #[error("internal error: {message}")]
    Internal { message: String },
}

impl CoreError {
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
            Self::Classify { .. } => ErrorKind::Classify,
            Self::Conflict { .. } => ErrorKind::Conflict,
            Self::DuplicateFile { .. } => ErrorKind::DuplicateFile,
            Self::FileNotFound { .. } => ErrorKind::FileNotFound,
            Self::RepoNotInitialized { .. } => ErrorKind::RepoNotInitialized,
            Self::InvalidPath { .. } => ErrorKind::InvalidPath,
            Self::ICloudPlaceholder { .. } => ErrorKind::ICloudPlaceholder,
            Self::PermissionDenied { .. } => ErrorKind::PermissionDenied,
            Self::Internal { .. } => ErrorKind::Internal,
        }
    }

    /// Returns the raw path, reason, or message carried by the error.
    pub fn raw_context(&self) -> &str {
        match self {
            Self::Io { message } | Self::Db { message } | Self::Internal { message } => message,
            Self::Config { reason } | Self::Classify { reason } => reason,
            Self::Conflict { path }
            | Self::FileNotFound { path }
            | Self::RepoNotInitialized { path }
            | Self::InvalidPath { path }
            | Self::ICloudPlaceholder { path }
            | Self::PermissionDenied { path } => path,
            Self::DuplicateFile { existing_path } => existing_path,
        }
    }

    /// Maps a structured `CoreError` to UI metadata without side effects.
    pub fn to_error_mapping(&self) -> ErrorMapping {
        let (user_message, severity, suggested_action, recoverability) = match self {
            Self::Io { .. } => (
                "文件操作失败",
                ErrorSeverity::Medium,
                "请重试；如果仍失败，请检查磁盘空间或文件状态",
                ErrorRecoverability::Retryable,
            ),
            Self::Db { .. } => (
                "数据库错误",
                ErrorSeverity::High,
                "请重启应用；如果仍失败，请重建索引或从备份恢复",
                ErrorRecoverability::UserActionRequired,
            ),
            Self::Config { .. } => (
                "配置错误",
                ErrorSeverity::Medium,
                "请打开设置检查配置，或恢复默认配置",
                ErrorRecoverability::UserActionRequired,
            ),
            Self::Classify { .. } => (
                "分类失败",
                ErrorSeverity::Low,
                "文件可先落入 inbox，稍后检查分类规则",
                ErrorRecoverability::RefreshRequired,
            ),
            Self::Conflict { .. } => (
                "路径冲突",
                ErrorSeverity::Medium,
                "请换一个名称或稍后重试",
                ErrorRecoverability::UserActionRequired,
            ),
            Self::DuplicateFile { .. } => (
                "文件已存在",
                ErrorSeverity::Low,
                "请选择跳过、覆盖现有文件或保留两份",
                ErrorRecoverability::UserActionRequired,
            ),
            Self::FileNotFound { .. } => (
                "文件不存在",
                ErrorSeverity::Low,
                "请刷新列表后重试",
                ErrorRecoverability::RefreshRequired,
            ),
            Self::RepoNotInitialized { .. } => (
                "资料库未初始化",
                ErrorSeverity::High,
                "请先完成资料库初始化",
                ErrorRecoverability::UserActionRequired,
            ),
            Self::InvalidPath { .. } => (
                "路径不合法",
                ErrorSeverity::Low,
                "请修改路径或文件名后重试",
                ErrorRecoverability::UserActionRequired,
            ),
            Self::ICloudPlaceholder { .. } => (
                "iCloud 文件未下载",
                ErrorSeverity::Medium,
                "请等待文件下载完成后自动重试",
                ErrorRecoverability::Retryable,
            ),
            Self::PermissionDenied { .. } => (
                "无访问权限",
                ErrorSeverity::High,
                "请在系统设置中授予权限，或选择其他资料库位置",
                ErrorRecoverability::UserActionRequired,
            ),
            Self::Internal { .. } => (
                "应用内部错误",
                ErrorSeverity::Critical,
                "请记录错误信息并重启应用",
                ErrorRecoverability::Fatal,
            ),
        };

        ErrorMapping {
            kind: self.kind(),
            user_message: user_message.to_owned(),
            severity,
            suggested_action: suggested_action.to_owned(),
            recoverability,
            raw_context: self.raw_context().to_owned(),
        }
    }
}

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
            ErrorKind::Classify => CoreError::Classify { reason },
            ErrorKind::Conflict => CoreError::Conflict { path },
            ErrorKind::DuplicateFile => CoreError::DuplicateFile {
                existing_path: path,
            },
            ErrorKind::FileNotFound => CoreError::FileNotFound { path },
            ErrorKind::RepoNotInitialized => CoreError::RepoNotInitialized { path },
            ErrorKind::InvalidPath => CoreError::InvalidPath { path },
            ErrorKind::ICloudPlaceholder => CoreError::ICloudPlaceholder { path },
            ErrorKind::PermissionDenied => CoreError::PermissionDenied { path },
            ErrorKind::Internal => CoreError::Internal { message },
        }
    }
}

/// Maps a structured error input to user-facing metadata.
///
/// This contract exists for C1-21 consumers that need the same mapping metadata
/// without first calling an API that throws `CoreError`. It is deterministic and
/// side-effect free.
pub fn map_core_error(input: ErrorMappingInput) -> ErrorMapping {
    input.into_core_error().to_error_mapping()
}

impl From<std::io::Error> for CoreError {
    fn from(error: std::io::Error) -> Self {
        match error.kind() {
            std::io::ErrorKind::NotFound => Self::file_not_found(error.to_string()),
            std::io::ErrorKind::PermissionDenied => Self::permission_denied(error.to_string()),
            std::io::ErrorKind::InvalidInput => Self::invalid_path(error.to_string()),
            _ => Self::io(error.to_string()),
        }
    }
}

impl From<rusqlite::Error> for CoreError {
    fn from(error: rusqlite::Error) -> Self {
        Self::db(error.to_string())
    }
}

impl From<serde_json::Error> for CoreError {
    fn from(error: serde_json::Error) -> Self {
        Self::internal(format!("json: {error}"))
    }
}

impl From<walkdir::Error> for CoreError {
    fn from(error: walkdir::Error) -> Self {
        Self::io(error.to_string())
    }
}
