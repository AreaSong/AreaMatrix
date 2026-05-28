use std::{
    collections::HashSet,
    path::{Component, PathBuf},
};

use crate::{CoreError, CoreResult};

use super::{
    AiPrivacyEvaluationContext, AiPrivacyEvaluationRequest, AiPrivacyFieldRule,
    AiPrivacyFieldState, AiPrivacyInputField, AiPrivacyProviderScopeSnapshot, AiPrivacyRuleInput,
    AiPrivacyRuleKind, AiPrivacyRulesSnapshot, AiPrivacyRulesUpdateRequest,
};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_RULES: usize = 200;
const MAX_RULE_ID_LEN: usize = 128;
const MAX_RULE_NAME_LEN: usize = 128;
const MAX_PATTERN_LEN: usize = 256;
const MAX_DESCRIPTION_LEN: usize = 500;

pub(super) fn default_snapshot() -> AiPrivacyRulesSnapshot {
    AiPrivacyRulesSnapshot {
        privacy_gate_enabled: false,
        rules: Vec::new(),
        remote_allowed_fields: default_field_states(),
        provider_scope: default_provider_scope(),
        updated_at: None,
        remote_blocked_by_default: true,
    }
}

pub(super) fn validate_update_request(request: &AiPrivacyRulesUpdateRequest) -> CoreResult<()> {
    if !request.confirmed {
        return Err(CoreError::config(
            "AI privacy rules update confirmation is required",
        ));
    }
    validate_rules(&request.rules)?;
    validate_field_rules(&request.remote_allowed_fields)?;
    validate_provider_scope(&request.provider_scope)?;
    if request.privacy_gate_enabled {
        validate_provider_ready(&request.provider_scope)?;
    }
    Ok(())
}

pub(super) fn validate_evaluation_request(request: &AiPrivacyEvaluationRequest) -> CoreResult<()> {
    validate_rules(&request.rules)?;
    validate_field_rules(&request.remote_allowed_fields)?;
    validate_provider_scope(&request.provider_scope)?;
    validate_requested_fields(&request.requested_fields)?;
    validate_context(&request.context)?;
    Ok(())
}

pub(super) fn validate_repo_path(repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() || repo_path.contains('\0') {
        return Err(CoreError::config("AI privacy repository path is invalid"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::config(
            "AI privacy repository path must not point inside metadata",
        ));
    }
    Ok(())
}

fn default_provider_scope() -> AiPrivacyProviderScopeSnapshot {
    AiPrivacyProviderScopeSnapshot {
        provider_configured: false,
        provider_verified: false,
        remote_provider_enabled: false,
        feature_scope: Vec::new(),
    }
}

fn default_field_states() -> Vec<AiPrivacyFieldState> {
    all_input_fields()
        .into_iter()
        .map(|field| AiPrivacyFieldState {
            field,
            allow_remote: false,
            last_matched_count: 0,
        })
        .collect()
}

fn validate_rules(rules: &[AiPrivacyRuleInput]) -> CoreResult<()> {
    if rules.len() > MAX_RULES {
        return Err(CoreError::config("AI privacy rule count is too large"));
    }
    let mut seen = HashSet::new();
    for rule in rules {
        validate_rule(rule)?;
        if let Some(rule_id) = rule.rule_id.as_deref() {
            if !seen.insert(rule_id.to_owned()) {
                return Err(CoreError::config("AI privacy rule ids must be unique"));
            }
        }
    }
    Ok(())
}

fn validate_rule(rule: &AiPrivacyRuleInput) -> CoreResult<()> {
    validate_optional_identifier(rule.rule_id.as_deref(), "AI privacy rule id is invalid")?;
    validate_text(
        &rule.name,
        MAX_RULE_NAME_LEN,
        "AI privacy rule name is invalid",
    )?;
    validate_pattern(&rule.kind, &rule.pattern)?;
    if let Some(description) = rule.description.as_deref() {
        validate_text(
            description,
            MAX_DESCRIPTION_LEN,
            "AI privacy rule description is invalid",
        )?;
    }
    Ok(())
}

fn validate_pattern(kind: &AiPrivacyRuleKind, pattern: &str) -> CoreResult<()> {
    match kind {
        AiPrivacyRuleKind::Folder => {
            validate_relative_path(pattern, "AI privacy folder pattern is invalid")
        }
        AiPrivacyRuleKind::Extension => validate_extension(pattern),
        AiPrivacyRuleKind::Category | AiPrivacyRuleKind::Keyword | AiPrivacyRuleKind::Tag => {
            validate_text(
                pattern,
                MAX_PATTERN_LEN,
                "AI privacy rule pattern is invalid",
            )
        }
    }
}

fn validate_field_rules(fields: &[AiPrivacyFieldRule]) -> CoreResult<()> {
    let mut seen = HashSet::new();
    for field in fields {
        if !seen.insert(field.field.clone()) {
            return Err(CoreError::config("AI privacy field rules must be unique"));
        }
    }
    if seen.len() != all_input_fields().len() {
        return Err(CoreError::config(
            "AI privacy field rules must include every remote field",
        ));
    }
    Ok(())
}

fn validate_provider_scope(scope: &AiPrivacyProviderScopeSnapshot) -> CoreResult<()> {
    let mut seen = HashSet::new();
    for feature in &scope.feature_scope {
        if !seen.insert(feature.clone()) {
            return Err(CoreError::config(
                "AI privacy provider feature scope must be unique",
            ));
        }
    }
    Ok(())
}

fn validate_provider_ready(scope: &AiPrivacyProviderScopeSnapshot) -> CoreResult<()> {
    if !scope.provider_configured {
        return Err(CoreError::config("AI privacy provider is not configured"));
    }
    if !scope.provider_verified {
        return Err(CoreError::config("AI privacy provider is not verified"));
    }
    if !scope.remote_provider_enabled {
        return Err(CoreError::config("AI privacy remote provider is disabled"));
    }
    if scope.feature_scope.is_empty() {
        return Err(CoreError::config("AI privacy provider scope is empty"));
    }
    Ok(())
}

fn validate_requested_fields(fields: &[AiPrivacyInputField]) -> CoreResult<()> {
    if fields.is_empty() {
        return Err(CoreError::config(
            "AI privacy evaluation requires at least one input field",
        ));
    }
    let mut seen = HashSet::new();
    for field in fields {
        if !seen.insert(field.clone()) {
            return Err(CoreError::config(
                "AI privacy evaluation fields must be unique",
            ));
        }
    }
    Ok(())
}

fn validate_context(context: &AiPrivacyEvaluationContext) -> CoreResult<()> {
    if context.file_id.is_some_and(|file_id| file_id <= 0) {
        return Err(CoreError::config(
            "AI privacy evaluation file id is invalid",
        ));
    }
    validate_optional_relative_path(&context.repo_relative_path)?;
    validate_optional_text(&context.file_name, "AI privacy file name is invalid")?;
    validate_optional_text(&context.category, "AI privacy category is invalid")?;
    validate_optional_text(&context.extension, "AI privacy extension is invalid")?;
    for tag in &context.tags {
        validate_text(tag, MAX_PATTERN_LEN, "AI privacy tag is invalid")?;
    }
    Ok(())
}

fn validate_optional_identifier(value: Option<&str>, message: &str) -> CoreResult<()> {
    if let Some(value) = value {
        validate_identifier(value, message)?;
    }
    Ok(())
}

fn validate_identifier(value: &str, message: &str) -> CoreResult<()> {
    if value.trim() != value
        || value.is_empty()
        || value.len() > MAX_RULE_ID_LEN
        || value.contains('\0')
        || !value.chars().all(is_identifier_char)
    {
        return Err(CoreError::config(message));
    }
    Ok(())
}

fn validate_text(value: &str, max_len: usize, message: &str) -> CoreResult<()> {
    if value.trim() != value
        || value.is_empty()
        || value.len() > max_len
        || value.contains('\0')
        || value.chars().any(char::is_control)
    {
        return Err(CoreError::config(message));
    }
    Ok(())
}

fn validate_optional_text(value: &Option<String>, message: &str) -> CoreResult<()> {
    if let Some(value) = value.as_deref() {
        validate_text(value, MAX_PATTERN_LEN, message)?;
    }
    Ok(())
}

fn validate_optional_relative_path(value: &Option<String>) -> CoreResult<()> {
    if let Some(value) = value.as_deref() {
        validate_relative_path(value, "AI privacy repo-relative path is invalid")?;
    }
    Ok(())
}

fn validate_relative_path(value: &str, message: &str) -> CoreResult<()> {
    let normalized = value.strip_suffix('/').unwrap_or(value);
    if value.trim() != value
        || value.is_empty()
        || normalized.is_empty()
        || value.starts_with('/')
        || value.contains('\\')
        || value.contains('\0')
        || normalized
            .split('/')
            .any(|part| part.is_empty() || part == "." || part == "..")
    {
        return Err(CoreError::config(message));
    }
    Ok(())
}

fn validate_extension(value: &str) -> CoreResult<()> {
    if value.trim() != value
        || !value.starts_with('.')
        || value.len() < 2
        || value.len() > MAX_PATTERN_LEN
        || value.contains('/')
        || value.contains('\\')
        || value.contains('\0')
        || value.chars().any(char::is_control)
    {
        return Err(CoreError::config("AI privacy extension pattern is invalid"));
    }
    Ok(())
}

fn all_input_fields() -> Vec<AiPrivacyInputField> {
    vec![
        AiPrivacyInputField::FileName,
        AiPrivacyInputField::RepoRelativePath,
        AiPrivacyInputField::Extension,
        AiPrivacyInputField::ExtractedTextExcerpt,
        AiPrivacyInputField::AiSummary,
        AiPrivacyInputField::NoteSummary,
        AiPrivacyInputField::TagCategoryContext,
    ]
}

fn is_identifier_char(value: char) -> bool {
    value.is_ascii_alphanumeric() || matches!(value, '-' | '_' | '.' | ':')
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    matches!(component, Component::Normal(value) if value == AREA_MATRIX_DIR)
}
