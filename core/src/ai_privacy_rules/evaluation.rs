//! Pure C3-09 privacy decision logic.

use std::collections::HashMap;

use super::{
    persistence::generated_rule_id, AiPrivacyDecision, AiPrivacyEvaluationContext,
    AiPrivacyEvaluationReport, AiPrivacyEvaluationRequest, AiPrivacyEvaluationRoute,
    AiPrivacyInputField, AiPrivacyProviderGateReason, AiPrivacyRuleAppliesTo, AiPrivacyRuleInput,
    AiPrivacyRuleKind, AiPrivacyRuleMatch, AiPrivacySkippedReason,
};

pub(super) fn evaluate(request: AiPrivacyEvaluationRequest) -> AiPrivacyEvaluationReport {
    if matches!(request.route, AiPrivacyEvaluationRoute::Remote) {
        if let Some(reason) = remote_provider_gate(&request) {
            return skipped_by_provider(reason);
        }
    }

    let matched_rules = matching_rules(&request);
    if !matched_rules.is_empty() {
        return denied_by_rule(matched_rules);
    }

    let (allowed_fields, blocked_fields) = field_filter(&request);
    if blocked_fields.len() == request.requested_fields.len() {
        return denied_by_field(allowed_fields, blocked_fields);
    }

    AiPrivacyEvaluationReport {
        decision: AiPrivacyDecision::Allowed,
        skipped_reason: None,
        provider_gate_reason: None,
        matched_rules: Vec::new(),
        matched_field_type: None,
        sent_fields: allowed_fields.clone(),
        allowed_fields,
        blocked_fields,
        message: "AI privacy rules allowed the requested fields".to_owned(),
    }
}

fn remote_provider_gate(
    request: &AiPrivacyEvaluationRequest,
) -> Option<AiPrivacyProviderGateReason> {
    if !request.privacy_gate_enabled {
        Some(AiPrivacyProviderGateReason::PrivacyGateDisabled)
    } else if !request.provider_scope.provider_configured {
        Some(AiPrivacyProviderGateReason::ProviderNotConfigured)
    } else if !request.provider_scope.provider_verified {
        Some(AiPrivacyProviderGateReason::ProviderNotVerified)
    } else if !request.provider_scope.remote_provider_enabled {
        Some(AiPrivacyProviderGateReason::ProviderDisabled)
    } else if !request
        .provider_scope
        .feature_scope
        .contains(&request.feature)
    {
        Some(AiPrivacyProviderGateReason::ScopeNotAllowed)
    } else {
        None
    }
}

fn skipped_by_provider(reason: AiPrivacyProviderGateReason) -> AiPrivacyEvaluationReport {
    AiPrivacyEvaluationReport {
        decision: AiPrivacyDecision::Skipped,
        skipped_reason: Some(skipped_reason_from_provider(&reason)),
        provider_gate_reason: Some(reason),
        matched_rules: Vec::new(),
        matched_field_type: None,
        allowed_fields: Vec::new(),
        blocked_fields: Vec::new(),
        sent_fields: Vec::new(),
        message: "Remote AI was skipped by provider or privacy gate state".to_owned(),
    }
}

fn denied_by_rule(matched_rules: Vec<AiPrivacyRuleMatch>) -> AiPrivacyEvaluationReport {
    let matched_field_type = matched_rules
        .first()
        .and_then(|rule| rule.matched_field.clone());
    AiPrivacyEvaluationReport {
        decision: AiPrivacyDecision::Denied,
        skipped_reason: Some(AiPrivacySkippedReason::PrivacyRule),
        provider_gate_reason: None,
        blocked_fields: matched_field_type.iter().cloned().collect(),
        matched_field_type,
        matched_rules,
        allowed_fields: Vec::new(),
        sent_fields: Vec::new(),
        message: "AI input was blocked by a privacy rule".to_owned(),
    }
}

fn denied_by_field(
    allowed_fields: Vec<AiPrivacyInputField>,
    blocked_fields: Vec<AiPrivacyInputField>,
) -> AiPrivacyEvaluationReport {
    AiPrivacyEvaluationReport {
        decision: AiPrivacyDecision::Denied,
        skipped_reason: Some(AiPrivacySkippedReason::NoEligibleInput),
        provider_gate_reason: None,
        matched_rules: Vec::new(),
        matched_field_type: blocked_fields.first().cloned(),
        allowed_fields,
        blocked_fields,
        sent_fields: Vec::new(),
        message: "No requested AI input field is eligible after privacy filtering".to_owned(),
    }
}

fn skipped_reason_from_provider(reason: &AiPrivacyProviderGateReason) -> AiPrivacySkippedReason {
    match reason {
        AiPrivacyProviderGateReason::PrivacyGateDisabled => {
            AiPrivacySkippedReason::PrivacyGateDisabled
        }
        AiPrivacyProviderGateReason::ScopeNotAllowed => AiPrivacySkippedReason::ScopeNotAllowed,
        AiPrivacyProviderGateReason::ProviderNotConfigured => {
            AiPrivacySkippedReason::ProviderNotConfigured
        }
        AiPrivacyProviderGateReason::ProviderNotVerified => {
            AiPrivacySkippedReason::ProviderNotVerified
        }
        AiPrivacyProviderGateReason::ProviderDisabled => AiPrivacySkippedReason::ProviderDisabled,
    }
}

fn field_filter(
    request: &AiPrivacyEvaluationRequest,
) -> (Vec<AiPrivacyInputField>, Vec<AiPrivacyInputField>) {
    if matches!(request.route, AiPrivacyEvaluationRoute::Local) {
        return (request.requested_fields.clone(), Vec::new());
    }
    let allowed = request
        .remote_allowed_fields
        .iter()
        .map(|rule| (rule.field.clone(), rule.allow_remote))
        .collect::<HashMap<_, _>>();
    let mut allowed_fields = Vec::new();
    let mut blocked_fields = Vec::new();
    for field in &request.requested_fields {
        if allowed.get(field).copied().unwrap_or(false) {
            allowed_fields.push(field.clone());
        } else {
            blocked_fields.push(field.clone());
        }
    }
    (allowed_fields, blocked_fields)
}

fn matching_rules(request: &AiPrivacyEvaluationRequest) -> Vec<AiPrivacyRuleMatch> {
    request
        .rules
        .iter()
        .filter(|rule| rule.enabled && rule_applies_to_route(rule, &request.route))
        .filter_map(|rule| matching_rule(rule, &request.context))
        .collect()
}

fn matching_rule(
    rule: &AiPrivacyRuleInput,
    context: &AiPrivacyEvaluationContext,
) -> Option<AiPrivacyRuleMatch> {
    let matched_field = matched_field(rule, context)?;
    Some(AiPrivacyRuleMatch {
        rule_id: rule
            .rule_id
            .clone()
            .unwrap_or_else(|| generated_rule_id(rule)),
        name: rule.name.clone(),
        kind: rule.kind.clone(),
        pattern: rule.pattern.clone(),
        applies_to: rule.applies_to.clone(),
        matched_field: Some(matched_field),
    })
}

fn matched_field(
    rule: &AiPrivacyRuleInput,
    context: &AiPrivacyEvaluationContext,
) -> Option<AiPrivacyInputField> {
    match rule.kind {
        AiPrivacyRuleKind::Folder => {
            folder_matches(&rule.pattern, context).then_some(AiPrivacyInputField::RepoRelativePath)
        }
        AiPrivacyRuleKind::Category => text_matches(&context.category, &rule.pattern)
            .then_some(AiPrivacyInputField::TagCategoryContext),
        AiPrivacyRuleKind::Keyword => keyword_matches(&rule.pattern, context),
        AiPrivacyRuleKind::Extension => extension_matches(&context.extension, &rule.pattern)
            .then_some(AiPrivacyInputField::Extension),
        AiPrivacyRuleKind::Tag => context
            .tags
            .iter()
            .any(|tag| normalized_text(tag) == normalized_text(&rule.pattern))
            .then_some(AiPrivacyInputField::TagCategoryContext),
    }
}

fn rule_applies_to_route(rule: &AiPrivacyRuleInput, route: &AiPrivacyEvaluationRoute) -> bool {
    match (&rule.applies_to, route) {
        (AiPrivacyRuleAppliesTo::LocalAndRemoteAi, _) => true,
        (AiPrivacyRuleAppliesTo::RemoteAi, AiPrivacyEvaluationRoute::Remote) => true,
        (AiPrivacyRuleAppliesTo::RemoteAi, AiPrivacyEvaluationRoute::Local) => false,
    }
}

fn folder_matches(pattern: &str, context: &AiPrivacyEvaluationContext) -> bool {
    let Some(path) = context.repo_relative_path.as_deref() else {
        return false;
    };
    let pattern = normalized_folder(pattern);
    let path = normalized_folder(path);
    path == pattern || path.starts_with(&format!("{pattern}/"))
}

fn keyword_matches(
    pattern: &str,
    context: &AiPrivacyEvaluationContext,
) -> Option<AiPrivacyInputField> {
    let pattern = normalized_text(pattern);
    for (field, value) in context_texts(context) {
        if normalized_text(value).contains(&pattern) {
            return Some(field);
        }
    }
    None
}

fn context_texts(context: &AiPrivacyEvaluationContext) -> Vec<(AiPrivacyInputField, &str)> {
    let mut values = Vec::new();
    push_optional(
        &mut values,
        AiPrivacyInputField::RepoRelativePath,
        context.repo_relative_path.as_deref(),
    );
    push_optional(
        &mut values,
        AiPrivacyInputField::FileName,
        context.file_name.as_deref(),
    );
    push_optional(
        &mut values,
        AiPrivacyInputField::TagCategoryContext,
        context.category.as_deref(),
    );
    push_optional(
        &mut values,
        AiPrivacyInputField::Extension,
        context.extension.as_deref(),
    );
    values.extend(
        context
            .tags
            .iter()
            .map(|tag| (AiPrivacyInputField::TagCategoryContext, tag.as_str())),
    );
    values
}

fn push_optional<'a>(
    values: &mut Vec<(AiPrivacyInputField, &'a str)>,
    field: AiPrivacyInputField,
    value: Option<&'a str>,
) {
    if let Some(value) = value {
        values.push((field, value));
    }
}

fn extension_matches(extension: &Option<String>, pattern: &str) -> bool {
    let Some(extension) = extension.as_deref() else {
        return false;
    };
    normalized_extension(extension) == normalized_extension(pattern)
}

fn text_matches(value: &Option<String>, pattern: &str) -> bool {
    value
        .as_deref()
        .is_some_and(|value| normalized_text(value) == normalized_text(pattern))
}

fn normalized_folder(value: &str) -> String {
    normalized_text(value.trim_matches('/'))
}

fn normalized_extension(value: &str) -> String {
    normalized_text(value.trim_start_matches('.'))
}

fn normalized_text(value: &str) -> String {
    value.to_lowercase()
}
