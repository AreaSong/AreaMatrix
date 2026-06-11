#[path = "support/remote_provider_config_common.rs"]
mod remote_provider_common;
#[path = "support/ai_privacy_rules_validation.rs"]
mod validation_support;

use std::fs;

use area_matrix_core::{
    evaluate_ai_privacy, list_ai_privacy_rules, update_ai_privacy_rules, AiPrivacyDecision,
    AiPrivacyInputField, AiPrivacyProviderGateReason, AiPrivacySkippedReason, CoreError,
};
use pretty_assertions::assert_eq;
use validation_support::{
    assert_c3_09_validation_alignment, assert_secret_free, configure_remote_provider,
    disabled_provider_scope, evaluation_request, folder_rule, keyword_rule, path_string,
    private_context, public_context, repo_config_value, snapshot, snapshot_rules_as_input,
    update_request, PRIVACY_RULES_KEY,
};

#[test]
fn ai_privacy_rules_validation_proves_ui_ready_success_gate_and_rule_paths() {
    let repo = remote_provider_common::initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    fs::write(repo.path().join("AREAMATRIX.md"), "user overview\n").expect("write user AREAMATRIX");
    let before = snapshot(repo.path());
    let provider_scope = configure_remote_provider(repo.path());

    let default =
        list_ai_privacy_rules(path_string(repo.path())).expect("load default privacy snapshot");
    assert!(!default.privacy_gate_enabled);
    assert!(default.remote_blocked_by_default);
    assert!(default.rules.is_empty());
    assert!(default.provider_scope.provider_configured);
    assert!(default.provider_scope.provider_verified);
    assert!(default.provider_scope.remote_provider_enabled);
    assert_secret_free(&serde_json::to_string(&default).expect("serialize default snapshot"));

    let updated = update_ai_privacy_rules(
        path_string(repo.path()),
        update_request(
            true,
            vec![folder_rule(), keyword_rule()],
            &[
                AiPrivacyInputField::FileName,
                AiPrivacyInputField::RepoRelativePath,
                AiPrivacyInputField::Extension,
            ],
            provider_scope.clone(),
        ),
    )
    .expect("persist UI-ready privacy rules");
    assert!(updated.privacy_gate_enabled);
    assert_eq!(updated.rules.len(), 2);
    assert_eq!(updated.provider_scope, provider_scope);
    assert_secret_free(&serde_json::to_string(&updated).expect("serialize updated snapshot"));

    let allowed = evaluate_ai_privacy(
        path_string(repo.path()),
        evaluation_request(
            true,
            snapshot_rules_as_input(&updated),
            &[
                AiPrivacyInputField::FileName,
                AiPrivacyInputField::RepoRelativePath,
                AiPrivacyInputField::Extension,
            ],
            provider_scope.clone(),
            public_context(),
        ),
    )
    .expect("evaluate allowed public context");
    assert_eq!(allowed.decision, AiPrivacyDecision::Allowed);
    assert_eq!(allowed.sent_fields, allowed.allowed_fields);

    let denied = evaluate_ai_privacy(
        path_string(repo.path()),
        evaluation_request(
            true,
            vec![folder_rule(), keyword_rule()],
            &[
                AiPrivacyInputField::FileName,
                AiPrivacyInputField::RepoRelativePath,
                AiPrivacyInputField::Extension,
            ],
            provider_scope.clone(),
            private_context(),
        ),
    )
    .expect("evaluate privacy rule match");
    assert_eq!(denied.decision, AiPrivacyDecision::Denied);
    assert_eq!(
        denied.skipped_reason,
        Some(AiPrivacySkippedReason::PrivacyRule)
    );
    assert!(denied.sent_fields.is_empty());
    assert!(denied
        .matched_rules
        .iter()
        .any(|rule| rule.rule_id == "rule:private-folder"));

    let blocked = update_ai_privacy_rules(
        path_string(repo.path()),
        update_request(false, vec![folder_rule()], &[], provider_scope.clone()),
    )
    .expect("block remote AI only through privacy gate");
    assert!(!blocked.privacy_gate_enabled);
    assert!(blocked.provider_scope.remote_provider_enabled);

    let skipped = evaluate_ai_privacy(
        path_string(repo.path()),
        evaluation_request(false, Vec::new(), &[], provider_scope, public_context()),
    )
    .expect("evaluate blocked privacy gate");
    assert_eq!(skipped.decision, AiPrivacyDecision::Skipped);
    assert_eq!(
        skipped.provider_gate_reason,
        Some(AiPrivacyProviderGateReason::PrivacyGateDisabled)
    );
    assert!(skipped.sent_fields.is_empty());
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn ai_privacy_rules_validation_covers_failure_paths_and_rollback() {
    let repo = remote_provider_common::initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    fs::write(repo.path().join("AREAMATRIX.md"), "user overview\n").expect("write user AREAMATRIX");
    let provider_scope = disabled_provider_scope();
    let baseline = update_request(
        false,
        vec![folder_rule()],
        &[AiPrivacyInputField::FileName],
        provider_scope.clone(),
    );
    update_ai_privacy_rules(path_string(repo.path()), baseline.clone())
        .expect("persist validation baseline");
    let before = snapshot(repo.path());
    let before_payload =
        repo_config_value(repo.path(), PRIVACY_RULES_KEY).expect("baseline privacy payload");

    let mut unconfirmed = baseline.clone();
    unconfirmed.confirmed = false;
    assert!(matches!(
        update_ai_privacy_rules(path_string(repo.path()), unconfirmed),
        Err(CoreError::Config { .. })
    ));

    let mut duplicate_rule = baseline.clone();
    duplicate_rule.rules.push(folder_rule());
    assert!(matches!(
        update_ai_privacy_rules(path_string(repo.path()), duplicate_rule),
        Err(CoreError::Config { .. })
    ));

    let mut duplicate_field = baseline.clone();
    duplicate_field
        .remote_allowed_fields
        .push(area_matrix_core::AiPrivacyFieldRule {
            field: AiPrivacyInputField::FileName,
            allow_remote: true,
        });
    assert!(matches!(
        update_ai_privacy_rules(path_string(repo.path()), duplicate_field),
        Err(CoreError::Config { .. })
    ));

    let mut unsafe_context = evaluation_request(
        true,
        Vec::new(),
        &[AiPrivacyInputField::FileName],
        provider_scope,
        public_context(),
    );
    unsafe_context.context.repo_relative_path = Some("../private/report.pdf".to_owned());
    assert!(matches!(
        evaluate_ai_privacy(path_string(repo.path()), unsafe_context),
        Err(CoreError::Config { .. })
    ));

    assert_eq!(snapshot(repo.path()), before);
    assert_eq!(
        repo_config_value(repo.path(), PRIVACY_RULES_KEY).expect("payload after config failures"),
        before_payload
    );

    validation_support::install_privacy_update_failure(repo.path());
    let mut changed = baseline;
    changed.rules = Vec::new();
    assert!(matches!(
        update_ai_privacy_rules(path_string(repo.path()), changed),
        Err(CoreError::Db { .. })
    ));
    assert_eq!(
        repo_config_value(repo.path(), PRIVACY_RULES_KEY).expect("payload after db rollback"),
        before_payload
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn ai_privacy_rules_validation_locks_api_udl_rust_and_test_evidence() {
    assert_c3_09_validation_alignment();
}
