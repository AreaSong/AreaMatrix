//! Persistence and provider-scope helpers for C3-09 privacy metadata.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{db, remote_provider_config, CoreError, CoreResult, RemoteProviderConfigSnapshot};

use super::{
    AiPrivacyFieldRule, AiPrivacyFieldState, AiPrivacyInputField, AiPrivacyProviderScopeSnapshot,
    AiPrivacyRuleInput, AiPrivacyRuleRecord, AiPrivacyRulesSnapshot,
};

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub(super) struct StoredAiPrivacyRules {
    pub(super) privacy_gate_enabled: bool,
    pub(super) rules: Vec<AiPrivacyRuleRecord>,
    pub(super) remote_allowed_fields: Vec<AiPrivacyFieldState>,
    pub(super) provider_scope: AiPrivacyProviderScopeSnapshot,
    pub(super) remote_blocked_by_default: bool,
}

pub(super) fn load_snapshot(repo_path: &str) -> CoreResult<AiPrivacyRulesSnapshot> {
    let repo = PathBuf::from(repo_path);
    let record = db::load_ai_privacy_rules_record(&repo).map_err(map_storage_error)?;
    let provider_scope = provider_scope_for_repo(repo_path)?;
    let Some(serialized) = record.serialized.as_deref() else {
        return Ok(default_snapshot(provider_scope, record.updated_at));
    };

    let mut stored = deserialize_rules(serialized)?;
    validate_stored(&stored)?;
    stored.provider_scope = provider_scope;
    Ok(snapshot_from_stored(stored, record.updated_at))
}

pub(super) fn store_update(
    repo_path: &str,
    privacy_gate_enabled: bool,
    rules: Vec<AiPrivacyRuleInput>,
    fields: Vec<AiPrivacyFieldRule>,
    provider_scope: AiPrivacyProviderScopeSnapshot,
) -> CoreResult<AiPrivacyRulesSnapshot> {
    let repo = PathBuf::from(repo_path);
    let actual_provider_scope = provider_scope_for_repo(repo_path)?;
    if privacy_gate_enabled && actual_provider_scope != provider_scope {
        return Err(CoreError::config(
            "AI privacy provider scope snapshot is stale",
        ));
    }
    if privacy_gate_enabled {
        ensure_provider_ready(&actual_provider_scope)?;
    }
    let stored = StoredAiPrivacyRules {
        privacy_gate_enabled,
        rules: rules.into_iter().map(record_from_input).collect(),
        remote_allowed_fields: fields.into_iter().map(field_state_from_rule).collect(),
        provider_scope: actual_provider_scope,
        remote_blocked_by_default: true,
    };
    let serialized = serialize_rules(&stored)?;
    let updated_at =
        db::update_ai_privacy_rules_record(&repo, &serialized).map_err(map_storage_error)?;
    Ok(snapshot_from_stored(stored, Some(updated_at)))
}

pub(super) fn default_snapshot(
    provider_scope: AiPrivacyProviderScopeSnapshot,
    updated_at: Option<i64>,
) -> AiPrivacyRulesSnapshot {
    AiPrivacyRulesSnapshot {
        privacy_gate_enabled: false,
        rules: Vec::new(),
        remote_allowed_fields: default_field_states(),
        provider_scope,
        updated_at,
        remote_blocked_by_default: true,
    }
}

pub(super) fn default_field_states() -> Vec<AiPrivacyFieldState> {
    all_input_fields()
        .into_iter()
        .map(|field| AiPrivacyFieldState {
            field,
            allow_remote: false,
            last_matched_count: 0,
        })
        .collect()
}

pub(super) fn all_input_fields() -> Vec<AiPrivacyInputField> {
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

pub(super) fn generated_rule_id(rule: &AiPrivacyRuleInput) -> String {
    let kind = match rule.kind {
        super::AiPrivacyRuleKind::Folder => "folder",
        super::AiPrivacyRuleKind::Category => "category",
        super::AiPrivacyRuleKind::Keyword => "keyword",
        super::AiPrivacyRuleKind::Extension => "extension",
        super::AiPrivacyRuleKind::Tag => "tag",
    };
    let pattern = rule
        .pattern
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() {
                ch.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches('-')
        .to_owned();
    format!("rule:{kind}:{pattern}")
}

fn snapshot_from_stored(
    stored: StoredAiPrivacyRules,
    updated_at: Option<i64>,
) -> AiPrivacyRulesSnapshot {
    AiPrivacyRulesSnapshot {
        privacy_gate_enabled: stored.privacy_gate_enabled,
        rules: stored.rules,
        remote_allowed_fields: stored.remote_allowed_fields,
        provider_scope: stored.provider_scope,
        updated_at,
        remote_blocked_by_default: stored.remote_blocked_by_default,
    }
}

fn record_from_input(rule: AiPrivacyRuleInput) -> AiPrivacyRuleRecord {
    let rule_id = rule
        .rule_id
        .clone()
        .unwrap_or_else(|| generated_rule_id(&rule));
    AiPrivacyRuleRecord {
        rule_id,
        name: rule.name,
        kind: rule.kind,
        pattern: rule.pattern,
        applies_to: rule.applies_to,
        enabled: rule.enabled,
        description: rule.description,
        match_count: 0,
        last_matched_at: None,
    }
}

fn field_state_from_rule(rule: AiPrivacyFieldRule) -> AiPrivacyFieldState {
    AiPrivacyFieldState {
        field: rule.field,
        allow_remote: rule.allow_remote,
        last_matched_count: 0,
    }
}

fn provider_scope_for_repo(repo_path: &str) -> CoreResult<AiPrivacyProviderScopeSnapshot> {
    match remote_provider_config::load_remote_ai_provider_config(repo_path.to_owned()) {
        Ok(snapshot) => Ok(provider_scope_from_remote(snapshot)),
        Err(CoreError::Config { .. }) if !metadata_exists(Path::new(repo_path))? => {
            Ok(empty_provider_scope())
        }
        Err(error) => Err(error),
    }
}

fn metadata_exists(repo_path: &Path) -> CoreResult<bool> {
    repo_path
        .join(".areamatrix/index.db")
        .try_exists()
        .map_err(|error| match error.kind() {
            std::io::ErrorKind::PermissionDenied => {
                CoreError::permission_denied("permission denied")
            }
            std::io::ErrorKind::InvalidInput => CoreError::invalid_path("invalid path"),
            _ => CoreError::io("io error"),
        })
}

fn provider_scope_from_remote(
    snapshot: RemoteProviderConfigSnapshot,
) -> AiPrivacyProviderScopeSnapshot {
    AiPrivacyProviderScopeSnapshot {
        provider_configured: snapshot.provider_configured,
        provider_verified: snapshot.provider_verified,
        remote_provider_enabled: snapshot.remote_provider_enabled,
        feature_scope: snapshot.feature_scope,
    }
}

fn ensure_provider_ready(scope: &AiPrivacyProviderScopeSnapshot) -> CoreResult<()> {
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

fn empty_provider_scope() -> AiPrivacyProviderScopeSnapshot {
    AiPrivacyProviderScopeSnapshot {
        provider_configured: false,
        provider_verified: false,
        remote_provider_enabled: false,
        feature_scope: Vec::new(),
    }
}

fn serialize_rules(rules: &StoredAiPrivacyRules) -> CoreResult<String> {
    serde_json::to_string(rules)
        .map_err(|_| CoreError::config("AI privacy rules metadata is invalid"))
}

fn deserialize_rules(serialized: &str) -> CoreResult<StoredAiPrivacyRules> {
    serde_json::from_str(serialized)
        .map_err(|_| CoreError::config("AI privacy rules metadata is invalid"))
}

fn validate_stored(stored: &StoredAiPrivacyRules) -> CoreResult<()> {
    let expected_fields = all_input_fields();
    if stored.remote_allowed_fields.len() != expected_fields.len() {
        return Err(CoreError::config("AI privacy rules metadata is invalid"));
    }
    for field in expected_fields {
        if !stored
            .remote_allowed_fields
            .iter()
            .any(|state| state.field == field)
        {
            return Err(CoreError::config("AI privacy rules metadata is invalid"));
        }
    }
    Ok(())
}

fn map_storage_error(error: CoreError) -> CoreError {
    match error {
        CoreError::InvalidPath { .. } => CoreError::config("AI privacy repository path is invalid"),
        CoreError::RepoNotInitialized { .. } => {
            CoreError::config("AI privacy requires initialized repository metadata")
        }
        other => other,
    }
}
