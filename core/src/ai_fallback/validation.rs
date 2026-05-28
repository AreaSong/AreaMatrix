use std::path::{Component, PathBuf};

use crate::{CoreError, CoreResult};

use super::AiFallbackStatusRequest;

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_IDENTIFIER_LEN: usize = 128;
const MAX_PROVIDER_ERROR_CODE_LEN: usize = 128;

pub(super) fn validate_repo_path(repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() || repo_path.contains('\0') {
        return Err(CoreError::config("AI fallback repository path is invalid"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "AI fallback repository path must not point inside metadata",
        ));
    }
    Ok(())
}

pub(super) fn validate_request(request: &AiFallbackStatusRequest) -> CoreResult<()> {
    if !has_reason_signal(request) {
        return Err(CoreError::config("AI fallback status reason is required"));
    }
    if request.call_log_id.is_some_and(|id| id <= 0) {
        return Err(CoreError::config("AI fallback call log id is invalid"));
    }
    if request.retry_after.is_some_and(|value| value < 0) {
        return Err(CoreError::config("AI fallback retry_after is invalid"));
    }
    if let Some(value) = request.provider_error_code.as_deref() {
        validate_provider_error_code(value)?;
    }
    if let Some(value) = request.privacy_rule_id.as_deref() {
        validate_identifier(value, "AI fallback privacy rule id is invalid")?;
    }
    Ok(())
}

fn has_reason_signal(request: &AiFallbackStatusRequest) -> bool {
    request.provider_error.is_some()
        || request.privacy_decision.is_some()
        || request.privacy_skipped_reason.is_some()
        || request.category_skipped_reason.is_some()
        || request.semantic_fallback_reason.is_some()
        || request.call_log_status.is_some()
}

fn validate_provider_error_code(value: &str) -> CoreResult<()> {
    if value.trim() != value
        || value.is_empty()
        || value.len() > MAX_PROVIDER_ERROR_CODE_LEN
        || value.contains('\0')
        || value.contains('/')
        || value.contains('\\')
        || !value.chars().all(is_identifier_char)
        || looks_sensitive(value)
    {
        return Err(CoreError::config(
            "AI fallback provider error code is invalid",
        ));
    }
    Ok(())
}

fn validate_identifier(value: &str, message: &str) -> CoreResult<()> {
    if value.trim() != value
        || value.is_empty()
        || value.len() > MAX_IDENTIFIER_LEN
        || value.contains('\0')
        || value.contains('/')
        || value.contains('\\')
        || !value.chars().all(is_identifier_char)
        || looks_sensitive(value)
    {
        return Err(CoreError::config(message));
    }
    Ok(())
}

fn is_identifier_char(value: char) -> bool {
    value.is_ascii_alphanumeric() || matches!(value, '-' | '_' | '.' | ':')
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    matches!(component, Component::Normal(value) if value == AREA_MATRIX_DIR)
}

fn looks_sensitive(value: &str) -> bool {
    let normalized = value.to_ascii_lowercase();
    normalized.starts_with("sk-")
        || normalized.starts_with("sk_")
        || normalized.contains("api_key")
        || normalized.contains("apikey")
        || normalized.contains("bearer")
        || normalized.contains("secret=")
        || normalized.contains("token=")
        || normalized.contains("-----begin")
}
