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

struct ErrorMappingTemplate {
    user_message: &'static str,
    severity: ErrorSeverity,
    suggested_action: &'static str,
    recoverability: ErrorRecoverability,
}

static IO_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "文件操作失败",
    severity: ErrorSeverity::Medium,
    suggested_action: "请重试；如果仍失败，请检查磁盘空间或文件状态",
    recoverability: ErrorRecoverability::Retryable,
};

static DB_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "数据库错误",
    severity: ErrorSeverity::High,
    suggested_action: "请重启应用；如果仍失败，请重建索引或从备份恢复",
    recoverability: ErrorRecoverability::UserActionRequired,
};

static DB_LOCKED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "数据库暂时被占用",
    severity: ErrorSeverity::Medium,
    suggested_action: "请稍后重试；如果仍失败，请导出诊断信息",
    recoverability: ErrorRecoverability::Retryable,
};

static DB_CORRUPTED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "资料库索引损坏",
    severity: ErrorSeverity::Critical,
    suggested_action: "请打开修复并重建索引，或从备份恢复",
    recoverability: ErrorRecoverability::Fatal,
};

static CONFIG_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "配置错误",
    severity: ErrorSeverity::Medium,
    suggested_action: "请打开设置检查配置，或恢复默认配置",
    recoverability: ErrorRecoverability::UserActionRequired,
};

static VALIDATION_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "输入无效",
    severity: ErrorSeverity::Low,
    suggested_action: "请修改输入后重试",
    recoverability: ErrorRecoverability::UserActionRequired,
};

static CLASSIFY_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "分类失败",
    severity: ErrorSeverity::Low,
    suggested_action: "文件可先落入 inbox，稍后检查分类规则",
    recoverability: ErrorRecoverability::RefreshRequired,
};

static CONFLICT_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "路径冲突",
    severity: ErrorSeverity::Medium,
    suggested_action: "请换一个名称或稍后重试",
    recoverability: ErrorRecoverability::UserActionRequired,
};

static DUPLICATE_FILE_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "文件已存在",
    severity: ErrorSeverity::Low,
    suggested_action: "请选择跳过、覆盖现有文件或保留两份",
    recoverability: ErrorRecoverability::UserActionRequired,
};

static FILE_NOT_FOUND_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "文件不存在",
    severity: ErrorSeverity::Low,
    suggested_action: "请刷新列表后重试",
    recoverability: ErrorRecoverability::RefreshRequired,
};

static EXPIRED_ACTION_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "操作已过期",
    severity: ErrorSeverity::Low,
    suggested_action: "请刷新撤销历史后继续操作",
    recoverability: ErrorRecoverability::RefreshRequired,
};

static REPO_NOT_INITIALIZED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "资料库未初始化",
    severity: ErrorSeverity::High,
    suggested_action: "请先完成资料库初始化",
    recoverability: ErrorRecoverability::UserActionRequired,
};

static INVALID_PATH_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "路径不合法",
    severity: ErrorSeverity::Low,
    suggested_action: "请修改路径或文件名后重试",
    recoverability: ErrorRecoverability::UserActionRequired,
};

static ICLOUD_PLACEHOLDER_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "iCloud 文件未下载",
    severity: ErrorSeverity::Medium,
    suggested_action: "请等待文件下载完成后自动重试",
    recoverability: ErrorRecoverability::Retryable,
};

static STAGING_RECOVERY_REQUIRED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "导入暂存需要恢复",
    severity: ErrorSeverity::High,
    suggested_action: "请先运行导入恢复后再重试当前操作",
    recoverability: ErrorRecoverability::UserActionRequired,
};

static PERMISSION_DENIED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "无访问权限",
    severity: ErrorSeverity::High,
    suggested_action: "请在系统设置中授予权限，或选择其他资料库位置",
    recoverability: ErrorRecoverability::UserActionRequired,
};

static INTERNAL_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "应用内部错误",
    severity: ErrorSeverity::Critical,
    suggested_action: "请记录错误信息并重启应用",
    recoverability: ErrorRecoverability::Fatal,
};

impl ErrorKind {
    fn mapping_template(&self) -> &'static ErrorMappingTemplate {
        match self {
            Self::Io => &IO_MAPPING,
            Self::Db => &DB_MAPPING,
            Self::Config => &CONFIG_MAPPING,
            Self::Validation => &VALIDATION_MAPPING,
            Self::Classify => &CLASSIFY_MAPPING,
            Self::Conflict => &CONFLICT_MAPPING,
            Self::DuplicateFile => &DUPLICATE_FILE_MAPPING,
            Self::FileNotFound => &FILE_NOT_FOUND_MAPPING,
            Self::ExpiredAction => &EXPIRED_ACTION_MAPPING,
            Self::RepoNotInitialized => &REPO_NOT_INITIALIZED_MAPPING,
            Self::InvalidPath => &INVALID_PATH_MAPPING,
            Self::ICloudPlaceholder => &ICLOUD_PLACEHOLDER_MAPPING,
            Self::StagingRecoveryRequired => &STAGING_RECOVERY_REQUIRED_MAPPING,
            Self::PermissionDenied => &PERMISSION_DENIED_MAPPING,
            Self::Internal => &INTERNAL_MAPPING,
        }
    }
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
            _ => self.kind().mapping_template(),
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

fn is_db_locked_message(message: &str) -> bool {
    let normalized = message.to_ascii_lowercase();
    let retryable_markers = [
        "database is locked",
        "database table is locked",
        "database is busy",
        "sqlite_busy",
    ];

    retryable_markers
        .iter()
        .any(|marker| normalized.contains(marker))
}

fn is_db_corrupted_message(message: &str) -> bool {
    let normalized = message.to_ascii_lowercase();
    let repair_markers = [
        "corrupt",
        "corrupted",
        "damaged",
        "database corrupted",
        "database disk image is malformed",
        "file is not a database",
        "not a database",
        "schema_version",
        "no such table",
        "integrity_check",
        "malformed",
    ];

    repair_markers
        .iter()
        .any(|marker| normalized.contains(marker))
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
