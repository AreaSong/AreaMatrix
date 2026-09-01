#![allow(dead_code)]

use std::path::Path;

use area_matrix_core::{
    list_ai_privacy_rules, update_ai_privacy_rules, AiPrivacyFieldRule, AiPrivacyRuleAppliesTo,
    AiPrivacyRuleInput, AiPrivacyRuleKind, AiPrivacyRulesSnapshot, AiPrivacyRulesUpdateRequest,
};

pub fn allow_remote_ai(repo: &Path) {
    update(repo, true, None, true);
}

pub fn install_blocking_rule(repo: &Path, rule_id: &str, kind: AiPrivacyRuleKind, pattern: &str) {
    let rule = AiPrivacyRuleInput {
        rule_id: Some(rule_id.to_owned()),
        name: "Test blocking rule".to_owned(),
        kind,
        pattern: pattern.to_owned(),
        applies_to: AiPrivacyRuleAppliesTo::LocalAndRemoteAi,
        enabled: true,
        description: Some("Persisted privacy evaluator regression fixture".to_owned()),
    };
    update(
        repo,
        current_snapshot(repo).privacy_gate_enabled,
        Some(rule),
        false,
    );
}

fn update(
    repo: &Path,
    privacy_gate_enabled: bool,
    replacement_rule: Option<AiPrivacyRuleInput>,
    allow_all_remote_fields: bool,
) {
    let snapshot = current_snapshot(repo);
    let rules = replacement_rule
        .map(|rule| vec![rule])
        .unwrap_or_else(|| rules_from_snapshot(&snapshot));
    let remote_allowed_fields = snapshot
        .remote_allowed_fields
        .iter()
        .map(|state| AiPrivacyFieldRule {
            field: state.field.clone(),
            allow_remote: allow_all_remote_fields || state.allow_remote,
        })
        .collect();
    update_ai_privacy_rules(
        repo.to_string_lossy().into_owned(),
        AiPrivacyRulesUpdateRequest {
            privacy_gate_enabled,
            rules,
            remote_allowed_fields,
            provider_scope: snapshot.provider_scope,
            confirmed: true,
        },
    )
    .expect("persist AI privacy fixture");
}

fn current_snapshot(repo: &Path) -> AiPrivacyRulesSnapshot {
    list_ai_privacy_rules(repo.to_string_lossy().into_owned()).expect("load AI privacy fixture")
}

fn rules_from_snapshot(snapshot: &AiPrivacyRulesSnapshot) -> Vec<AiPrivacyRuleInput> {
    snapshot
        .rules
        .iter()
        .map(|rule| AiPrivacyRuleInput {
            rule_id: Some(rule.rule_id.clone()),
            name: rule.name.clone(),
            kind: rule.kind.clone(),
            pattern: rule.pattern.clone(),
            applies_to: rule.applies_to.clone(),
            enabled: rule.enabled,
            description: rule.description.clone(),
        })
        .collect()
}
