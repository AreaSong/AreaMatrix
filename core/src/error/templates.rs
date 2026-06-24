use super::types::{ErrorKind, ErrorRecoverability, ErrorSeverity};

pub(super) struct ErrorMappingTemplate {
    pub(super) user_message: &'static str,
    pub(super) severity: ErrorSeverity,
    pub(super) suggested_action: &'static str,
    pub(super) recoverability: ErrorRecoverability,
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

pub(super) static DB_LOCKED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    user_message: "数据库暂时被占用",
    severity: ErrorSeverity::Medium,
    suggested_action: "请稍后重试；如果仍失败，请导出诊断信息",
    recoverability: ErrorRecoverability::Retryable,
};

pub(super) static DB_CORRUPTED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
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

pub(super) fn mapping_template_for_kind(kind: &ErrorKind) -> &'static ErrorMappingTemplate {
    match kind {
        ErrorKind::Io => &IO_MAPPING,
        ErrorKind::Db => &DB_MAPPING,
        ErrorKind::Config => &CONFIG_MAPPING,
        ErrorKind::Validation => &VALIDATION_MAPPING,
        ErrorKind::Classify => &CLASSIFY_MAPPING,
        ErrorKind::Conflict => &CONFLICT_MAPPING,
        ErrorKind::DuplicateFile => &DUPLICATE_FILE_MAPPING,
        ErrorKind::FileNotFound => &FILE_NOT_FOUND_MAPPING,
        ErrorKind::ExpiredAction => &EXPIRED_ACTION_MAPPING,
        ErrorKind::RepoNotInitialized => &REPO_NOT_INITIALIZED_MAPPING,
        ErrorKind::InvalidPath => &INVALID_PATH_MAPPING,
        ErrorKind::ICloudPlaceholder => &ICLOUD_PLACEHOLDER_MAPPING,
        ErrorKind::StagingRecoveryRequired => &STAGING_RECOVERY_REQUIRED_MAPPING,
        ErrorKind::PermissionDenied => &PERMISSION_DENIED_MAPPING,
        ErrorKind::Internal => &INTERNAL_MAPPING,
    }
}

pub(super) fn is_db_locked_message(message: &str) -> bool {
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

pub(super) fn is_db_corrupted_message(message: &str) -> bool {
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
