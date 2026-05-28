use std::{fs, path::Path};

use area_matrix_core::{
    evaluate_ai_privacy, init_repo, list_ai_privacy_rules, update_ai_privacy_rules, AiFeatureKind,
    AiPrivacyDecision, AiPrivacyEvaluationContext, AiPrivacyEvaluationRequest,
    AiPrivacyEvaluationRoute, AiPrivacyFieldRule, AiPrivacyInputField, AiPrivacyProviderGateReason,
    AiPrivacyProviderScopeSnapshot, AiPrivacyRuleAppliesTo, AiPrivacyRuleInput, AiPrivacyRuleKind,
    AiPrivacySkippedReason, CoreError, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");
    repo
}

fn input_fields() -> Vec<AiPrivacyInputField> {
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

fn field_rules(allowed: &[AiPrivacyInputField]) -> Vec<AiPrivacyFieldRule> {
    input_fields()
        .into_iter()
        .map(|field| AiPrivacyFieldRule {
            allow_remote: allowed.contains(&field),
            field,
        })
        .collect()
}

fn provider_scope() -> AiPrivacyProviderScopeSnapshot {
    AiPrivacyProviderScopeSnapshot {
        provider_configured: true,
        provider_verified: true,
        remote_provider_enabled: true,
        feature_scope: vec![AiFeatureKind::AutoSummaries],
    }
}

fn disabled_provider_scope() -> AiPrivacyProviderScopeSnapshot {
    AiPrivacyProviderScopeSnapshot {
        provider_configured: false,
        provider_verified: false,
        remote_provider_enabled: false,
        feature_scope: Vec::new(),
    }
}

fn folder_rule(applies_to: AiPrivacyRuleAppliesTo) -> AiPrivacyRuleInput {
    AiPrivacyRuleInput {
        rule_id: Some("rule:private-folder".to_owned()),
        name: "Private folder".to_owned(),
        kind: AiPrivacyRuleKind::Folder,
        pattern: "finance/private/".to_owned(),
        applies_to,
        enabled: true,
        description: Some("Keep private folder out of AI".to_owned()),
    }
}

fn evaluation_context() -> AiPrivacyEvaluationContext {
    AiPrivacyEvaluationContext {
        file_id: Some(42),
        repo_relative_path: Some("finance/private/report.pdf".to_owned()),
        file_name: Some("report.pdf".to_owned()),
        category: Some("finance".to_owned()),
        extension: Some(".pdf".to_owned()),
        tags: vec!["client-private".to_owned()],
    }
}

fn evaluation_request() -> AiPrivacyEvaluationRequest {
    AiPrivacyEvaluationRequest {
        feature: AiFeatureKind::AutoSummaries,
        route: AiPrivacyEvaluationRoute::Remote,
        requested_fields: vec![
            AiPrivacyInputField::FileName,
            AiPrivacyInputField::ExtractedTextExcerpt,
        ],
        privacy_gate_enabled: true,
        provider_scope: provider_scope(),
        rules: Vec::new(),
        remote_allowed_fields: field_rules(&[AiPrivacyInputField::FileName]),
        context: evaluation_context(),
    }
}

fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .ok()
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

#[test]
fn ai_privacy_rules_implementation_persists_and_reloads_rules_without_user_file_writes() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let readme_path = repo.path().join("README.md");
    let overview_path = repo.path().join("AREAMATRIX.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&overview_path, "user overview\n").expect("write user overview");

    let request = area_matrix_core::AiPrivacyRulesUpdateRequest {
        privacy_gate_enabled: false,
        rules: vec![folder_rule(AiPrivacyRuleAppliesTo::RemoteAi)],
        remote_allowed_fields: field_rules(&[
            AiPrivacyInputField::FileName,
            AiPrivacyInputField::Extension,
        ]),
        provider_scope: disabled_provider_scope(),
        confirmed: true,
    };
    let updated =
        update_ai_privacy_rules(repo_path.clone(), request).expect("persist privacy rules");
    let reloaded = list_ai_privacy_rules(repo_path).expect("reload privacy rules");

    assert_eq!(updated.rules[0].rule_id, "rule:private-folder");
    assert_eq!(updated.rules[0].match_count, 0);
    assert!(updated.updated_at.is_some());
    assert_eq!(reloaded.rules, updated.rules);
    assert_eq!(
        reloaded.remote_allowed_fields,
        updated.remote_allowed_fields
    );
    assert!(!reloaded.privacy_gate_enabled);
    assert!(reloaded.remote_blocked_by_default);
    assert!(!reloaded.provider_scope.provider_configured);

    let stored = repo_config_value(repo.path(), "ai_privacy_rules")
        .expect("privacy rules metadata persisted");
    assert!(stored.contains("\"id\":\"rule:private-folder\""));
    assert!(stored.contains("Remote AI"));
    assert_eq!(
        fs::read_to_string(&readme_path).expect("read README"),
        "user readme\n"
    );
    assert_eq!(
        fs::read_to_string(&overview_path).expect("read AREAMATRIX"),
        "user overview\n"
    );
    assert!(!repo.path().join(".areamatrix/secrets").exists());
}

#[test]
fn ai_privacy_rules_implementation_evaluates_provider_gates_and_field_filters() {
    let mut request = evaluation_request();
    request.privacy_gate_enabled = false;
    let gate_disabled = evaluate_ai_privacy("/tmp/repo".to_owned(), request)
        .expect("evaluate disabled privacy gate");
    assert_eq!(gate_disabled.decision, AiPrivacyDecision::Skipped);
    assert_eq!(
        gate_disabled.provider_gate_reason,
        Some(AiPrivacyProviderGateReason::PrivacyGateDisabled)
    );

    let mut request = evaluation_request();
    request.provider_scope = disabled_provider_scope();
    let provider_missing =
        evaluate_ai_privacy("/tmp/repo".to_owned(), request).expect("evaluate provider missing");
    assert_eq!(
        provider_missing.skipped_reason,
        Some(AiPrivacySkippedReason::ProviderNotConfigured)
    );

    let allowed =
        evaluate_ai_privacy("/tmp/repo".to_owned(), evaluation_request()).expect("evaluate field");
    assert_eq!(allowed.decision, AiPrivacyDecision::Allowed);
    assert_eq!(allowed.sent_fields, vec![AiPrivacyInputField::FileName]);
    assert_eq!(
        allowed.blocked_fields,
        vec![AiPrivacyInputField::ExtractedTextExcerpt]
    );

    let mut request = evaluation_request();
    request.remote_allowed_fields = field_rules(&[]);
    let no_fields =
        evaluate_ai_privacy("/tmp/repo".to_owned(), request).expect("evaluate field deny");
    assert_eq!(no_fields.decision, AiPrivacyDecision::Denied);
    assert_eq!(
        no_fields.skipped_reason,
        Some(AiPrivacySkippedReason::NoEligibleInput)
    );
    assert!(no_fields.sent_fields.is_empty());
}

#[test]
fn ai_privacy_rules_implementation_matches_rules_without_reading_file_contents() {
    let mut request = evaluation_request();
    request.rules = vec![folder_rule(AiPrivacyRuleAppliesTo::RemoteAi)];
    let denied =
        evaluate_ai_privacy("/tmp/repo".to_owned(), request).expect("evaluate folder rule");
    assert_eq!(denied.decision, AiPrivacyDecision::Denied);
    assert_eq!(
        denied.skipped_reason,
        Some(AiPrivacySkippedReason::PrivacyRule)
    );
    assert_eq!(denied.matched_rules[0].rule_id, "rule:private-folder");
    assert_eq!(
        denied.matched_field_type,
        Some(AiPrivacyInputField::RepoRelativePath)
    );
    assert!(denied.sent_fields.is_empty());

    let mut local = evaluation_request();
    local.route = AiPrivacyEvaluationRoute::Local;
    local.rules = vec![folder_rule(AiPrivacyRuleAppliesTo::RemoteAi)];
    let allowed_local =
        evaluate_ai_privacy("/tmp/repo".to_owned(), local).expect("evaluate local route");
    assert_eq!(allowed_local.decision, AiPrivacyDecision::Allowed);

    let mut keyword = evaluation_request();
    keyword.route = AiPrivacyEvaluationRoute::Local;
    keyword.rules = vec![AiPrivacyRuleInput {
        rule_id: Some("rule:keyword:private".to_owned()),
        name: "Private keyword".to_owned(),
        kind: AiPrivacyRuleKind::Keyword,
        pattern: "client-private".to_owned(),
        applies_to: AiPrivacyRuleAppliesTo::LocalAndRemoteAi,
        enabled: true,
        description: None,
    }];
    let denied_keyword =
        evaluate_ai_privacy("/tmp/repo".to_owned(), keyword).expect("evaluate keyword rule");
    assert_eq!(denied_keyword.decision, AiPrivacyDecision::Denied);
    assert_eq!(
        denied_keyword.matched_field_type,
        Some(AiPrivacyInputField::TagCategoryContext)
    );
}

#[test]
fn ai_privacy_rules_implementation_rejects_invalid_updates_and_rolls_back() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let valid = area_matrix_core::AiPrivacyRulesUpdateRequest {
        privacy_gate_enabled: false,
        rules: vec![folder_rule(AiPrivacyRuleAppliesTo::RemoteAi)],
        remote_allowed_fields: field_rules(&[AiPrivacyInputField::FileName]),
        provider_scope: disabled_provider_scope(),
        confirmed: true,
    };
    update_ai_privacy_rules(repo_path.clone(), valid.clone()).expect("persist baseline");
    let before = repo_config_value(repo.path(), "ai_privacy_rules").expect("baseline metadata");

    let mut invalid = valid.clone();
    invalid.remote_allowed_fields.pop();
    assert!(matches!(
        update_ai_privacy_rules(repo_path.clone(), invalid),
        Err(CoreError::Config { .. })
    ));
    assert_eq!(
        repo_config_value(repo.path(), "ai_privacy_rules").expect("metadata after invalid"),
        before
    );

    open_db(repo.path())
        .execute_batch(
            "CREATE TRIGGER fail_ai_privacy_rules_update
             BEFORE UPDATE ON repo_config
             WHEN NEW.key = 'ai_privacy_rules'
             BEGIN
               SELECT RAISE(ABORT, 'forced privacy rules write failure');
             END;",
        )
        .expect("install failing privacy trigger");

    let mut changed = valid;
    changed.rules = Vec::new();
    assert!(matches!(
        update_ai_privacy_rules(repo_path, changed),
        Err(CoreError::Db { .. })
    ));
    assert_eq!(
        repo_config_value(repo.path(), "ai_privacy_rules").expect("metadata after rollback"),
        before
    );
}
