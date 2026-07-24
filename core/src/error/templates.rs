use super::types::{ErrorKind, ErrorRecoverability, ErrorSeverity};

pub(super) struct ErrorMappingTemplate {
    pub(super) code: &'static str,
    pub(super) field: Option<&'static str>,
    pub(super) severity: ErrorSeverity,
    pub(super) recoverability: ErrorRecoverability,
    pub(super) recovery_action_ids: &'static [&'static str],
}

const IO_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "io_error",
    field: None,
    severity: ErrorSeverity::Medium,
    recoverability: ErrorRecoverability::Retryable,
    recovery_action_ids: &["retry", "collect_diagnostics"],
};

const DB_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "database_error",
    field: None,
    severity: ErrorSeverity::High,
    recoverability: ErrorRecoverability::UserActionRequired,
    recovery_action_ids: &["collect_diagnostics", "open_recovery"],
};

pub(super) const DB_LOCKED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "database_locked",
    field: None,
    severity: ErrorSeverity::Medium,
    recoverability: ErrorRecoverability::Retryable,
    recovery_action_ids: &["retry", "collect_diagnostics"],
};

pub(super) const DB_CORRUPTED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "database_corrupted",
    field: None,
    severity: ErrorSeverity::Critical,
    recoverability: ErrorRecoverability::Fatal,
    recovery_action_ids: &["open_recovery", "collect_diagnostics"],
};

const CONFIG_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "config_error",
    field: None,
    severity: ErrorSeverity::Medium,
    recoverability: ErrorRecoverability::UserActionRequired,
    recovery_action_ids: &["open_settings", "review_configuration"],
};

const VALIDATION_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "validation_error",
    field: None,
    severity: ErrorSeverity::Low,
    recoverability: ErrorRecoverability::UserActionRequired,
    recovery_action_ids: &["fix_input"],
};

const CLASSIFY_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "classification_error",
    field: None,
    severity: ErrorSeverity::Low,
    recoverability: ErrorRecoverability::RefreshRequired,
    recovery_action_ids: &["open_classifier", "refresh"],
};

const CONFLICT_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "conflict",
    field: None,
    severity: ErrorSeverity::Medium,
    recoverability: ErrorRecoverability::UserActionRequired,
    recovery_action_ids: &["review_conflict", "reload_latest"],
};

const REVISION_CONFLICT_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "revision_conflict",
    field: Some("revision"),
    severity: ErrorSeverity::Medium,
    recoverability: ErrorRecoverability::UserActionRequired,
    recovery_action_ids: &["review_changes", "reload_latest"],
};

const DUPLICATE_FILE_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "duplicate_file",
    field: Some("existing_path"),
    severity: ErrorSeverity::Low,
    recoverability: ErrorRecoverability::UserActionRequired,
    recovery_action_ids: &["skip", "keep_both", "review_replace"],
};

const FILE_NOT_FOUND_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "file_not_found",
    field: Some("path"),
    severity: ErrorSeverity::Low,
    recoverability: ErrorRecoverability::RefreshRequired,
    recovery_action_ids: &["refresh", "locate_file"],
};

const EXPIRED_ACTION_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "expired_action",
    field: Some("action_id"),
    severity: ErrorSeverity::Low,
    recoverability: ErrorRecoverability::RefreshRequired,
    recovery_action_ids: &["refresh_history"],
};

const REPO_NOT_INITIALIZED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "repository_not_initialized",
    field: Some("path"),
    severity: ErrorSeverity::High,
    recoverability: ErrorRecoverability::UserActionRequired,
    recovery_action_ids: &["initialize_repository", "choose_repository"],
};

const INVALID_PATH_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "invalid_path",
    field: Some("path"),
    severity: ErrorSeverity::Low,
    recoverability: ErrorRecoverability::UserActionRequired,
    recovery_action_ids: &["change_path"],
};

const ICLOUD_PLACEHOLDER_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "icloud_placeholder_not_downloaded",
    field: Some("path"),
    severity: ErrorSeverity::Medium,
    recoverability: ErrorRecoverability::Retryable,
    recovery_action_ids: &["download_and_retry", "choose_local_repository"],
};

const STAGING_RECOVERY_REQUIRED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "staging_recovery_required",
    field: Some("path"),
    severity: ErrorSeverity::High,
    recoverability: ErrorRecoverability::UserActionRequired,
    recovery_action_ids: &["open_recovery"],
};

const PERMISSION_DENIED_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "permission_denied",
    field: Some("path"),
    severity: ErrorSeverity::High,
    recoverability: ErrorRecoverability::UserActionRequired,
    recovery_action_ids: &["choose_folder", "open_system_settings"],
};

const INTERNAL_MAPPING: ErrorMappingTemplate = ErrorMappingTemplate {
    code: "internal_error",
    field: None,
    severity: ErrorSeverity::Critical,
    recoverability: ErrorRecoverability::Fatal,
    recovery_action_ids: &["collect_diagnostics", "leave_flow", "open_issue"],
};

pub(super) fn mapping_template_for_kind(kind: &ErrorKind) -> &'static ErrorMappingTemplate {
    match kind {
        ErrorKind::Io => &IO_MAPPING,
        ErrorKind::Db => &DB_MAPPING,
        ErrorKind::DbLocked => &DB_LOCKED_MAPPING,
        ErrorKind::DbCorrupted => &DB_CORRUPTED_MAPPING,
        ErrorKind::Config => &CONFIG_MAPPING,
        ErrorKind::Validation => &VALIDATION_MAPPING,
        ErrorKind::Classify => &CLASSIFY_MAPPING,
        ErrorKind::Conflict => &CONFLICT_MAPPING,
        ErrorKind::RevisionConflict => &REVISION_CONFLICT_MAPPING,
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
