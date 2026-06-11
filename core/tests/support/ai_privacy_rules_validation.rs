#![allow(dead_code)]

use std::{fs, path::Path};

use area_matrix_core::{
    evaluate_ai_privacy, list_ai_privacy_rules, update_ai_privacy_rules, AiFeatureKind,
    AiPrivacyEvaluationContext, AiPrivacyEvaluationReport, AiPrivacyEvaluationRequest,
    AiPrivacyEvaluationRoute, AiPrivacyFieldRule, AiPrivacyInputField,
    AiPrivacyProviderScopeSnapshot, AiPrivacyRuleAppliesTo, AiPrivacyRuleInput, AiPrivacyRuleKind,
    AiPrivacyRulesSnapshot, AiPrivacyRulesUpdateRequest, CoreResult,
};
use rusqlite::{params, Connection};

pub use super::remote_provider_common::path_string;
use super::remote_provider_common::{
    enable_request_for_endpoint, test_request_for_endpoint, ProbeRuntime, SECRET_VALUE,
    TEST_SECRET_ENV,
};
use area_matrix_core::{enable_remote_ai_provider, test_remote_ai_provider};

pub const PRIVACY_RULES_KEY: &str = "ai_privacy_rules";

const TASK: &str =
    include_str!("../../../tasks/prompts/phase-4/4-2-stage3-ai/task-44-c3-09-validation.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../../docs/core/capability-specs/stage-3-ai/C3-09-ai-privacy-rules.md");
const CONTROL_MAP: &str = include_str!("../../../docs/architecture/stage-3-control-map.md");
const TESTING_DOC: &str = include_str!("../../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../../docs/api/core-api.md");
const UDL: &str = include_str!("../../area_matrix.udl");
const API_RS: &str = include_str!("../../src/api.rs");
const LIB_RS: &str = include_str!("../../src/lib.rs");
const PRIVACY_RULES_RS: &str = include_str!("../../src/ai_privacy_rules.rs");
const PRIVACY_EVALUATION_RS: &str = include_str!("../../src/ai_privacy_rules/evaluation.rs");
const PRIVACY_PERSISTENCE_RS: &str = include_str!("../../src/ai_privacy_rules/persistence.rs");
const PRIVACY_VALIDATION_RS: &str = include_str!("../../src/ai_privacy_rules/validation.rs");
const DB_PRIVACY_RULES_RS: &str = include_str!("../../src/db/ai_privacy_rules.rs");
const CONTRACT_TEST: &str = include_str!("../ai_privacy_rules_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("../ai_privacy_rules_implementation.rs");
const FAILURE_TEST: &str = include_str!("../ai_privacy_rules_failure_recovery.rs");

#[derive(Debug, Eq, PartialEq)]
pub struct PrivacySnapshot {
    user_readme: String,
    user_overview: String,
    user_visible_paths: Vec<String>,
}

pub fn input_fields() -> Vec<AiPrivacyInputField> {
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

pub fn field_rules(allowed: &[AiPrivacyInputField]) -> Vec<AiPrivacyFieldRule> {
    input_fields()
        .into_iter()
        .map(|field| AiPrivacyFieldRule {
            allow_remote: allowed.contains(&field),
            field,
        })
        .collect()
}

pub fn disabled_provider_scope() -> AiPrivacyProviderScopeSnapshot {
    AiPrivacyProviderScopeSnapshot {
        provider_configured: false,
        provider_verified: false,
        remote_provider_enabled: false,
        feature_scope: Vec::new(),
    }
}

pub fn folder_rule() -> AiPrivacyRuleInput {
    AiPrivacyRuleInput {
        rule_id: Some("rule:private-folder".to_owned()),
        name: "Private folder".to_owned(),
        kind: AiPrivacyRuleKind::Folder,
        pattern: "finance/private/".to_owned(),
        applies_to: AiPrivacyRuleAppliesTo::RemoteAi,
        enabled: true,
        description: Some("Keep private folder out of remote AI".to_owned()),
    }
}

pub fn keyword_rule() -> AiPrivacyRuleInput {
    AiPrivacyRuleInput {
        rule_id: Some("rule:keyword:client-private".to_owned()),
        name: "Client private keyword".to_owned(),
        kind: AiPrivacyRuleKind::Keyword,
        pattern: "client-private".to_owned(),
        applies_to: AiPrivacyRuleAppliesTo::LocalAndRemoteAi,
        enabled: true,
        description: None,
    }
}

pub fn update_request(
    gate_enabled: bool,
    rules: Vec<AiPrivacyRuleInput>,
    allowed: &[AiPrivacyInputField],
    provider_scope: AiPrivacyProviderScopeSnapshot,
) -> AiPrivacyRulesUpdateRequest {
    AiPrivacyRulesUpdateRequest {
        privacy_gate_enabled: gate_enabled,
        rules,
        remote_allowed_fields: field_rules(allowed),
        provider_scope,
        confirmed: true,
    }
}

pub fn evaluation_request(
    gate_enabled: bool,
    rules: Vec<AiPrivacyRuleInput>,
    allowed: &[AiPrivacyInputField],
    provider_scope: AiPrivacyProviderScopeSnapshot,
    context: AiPrivacyEvaluationContext,
) -> AiPrivacyEvaluationRequest {
    AiPrivacyEvaluationRequest {
        feature: AiFeatureKind::AutoSummaries,
        route: AiPrivacyEvaluationRoute::Remote,
        requested_fields: vec![
            AiPrivacyInputField::FileName,
            AiPrivacyInputField::RepoRelativePath,
            AiPrivacyInputField::Extension,
        ],
        privacy_gate_enabled: gate_enabled,
        provider_scope,
        rules,
        remote_allowed_fields: field_rules(allowed),
        context,
    }
}

pub fn public_context() -> AiPrivacyEvaluationContext {
    AiPrivacyEvaluationContext {
        file_id: Some(7),
        repo_relative_path: Some("docs/public/report.pdf".to_owned()),
        file_name: Some("report.pdf".to_owned()),
        category: Some("docs".to_owned()),
        extension: Some(".pdf".to_owned()),
        tags: vec!["reference".to_owned()],
    }
}

pub fn private_context() -> AiPrivacyEvaluationContext {
    AiPrivacyEvaluationContext {
        file_id: Some(8),
        repo_relative_path: Some("finance/private/report.pdf".to_owned()),
        file_name: Some("client-private-report.pdf".to_owned()),
        category: Some("finance".to_owned()),
        extension: Some(".pdf".to_owned()),
        tags: vec!["client-private".to_owned()],
    }
}

pub fn snapshot_rules_as_input(snapshot: &AiPrivacyRulesSnapshot) -> Vec<AiPrivacyRuleInput> {
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

pub fn configure_remote_provider(repo: &Path) -> AiPrivacyProviderScopeSnapshot {
    let endpoint = "https://provider.example.test/privacy-validation";
    let runtime = ProbeRuntime::new("Succeeded");
    let tested = test_remote_ai_provider(path_string(repo), test_request_for_endpoint(endpoint))
        .expect("test remote provider");
    let payload = runtime.captured_payload();
    assert_contains(&payload, "provider.example.test/privacy-validation");
    assert_not_contains(&payload, "user readme");

    let enabled = enable_remote_ai_provider(
        path_string(repo),
        enable_request_for_endpoint(
            tested
                .verification_token
                .expect("successful provider test returns token"),
            endpoint,
        ),
    )
    .expect("enable remote provider");

    AiPrivacyProviderScopeSnapshot {
        provider_configured: enabled.provider_configured,
        provider_verified: enabled.provider_verified,
        remote_provider_enabled: enabled.remote_provider_enabled,
        feature_scope: enabled.feature_scope,
    }
}

pub fn snapshot(repo: &Path) -> PrivacySnapshot {
    PrivacySnapshot {
        user_readme: fs::read_to_string(repo.join("README.md")).expect("read user README"),
        user_overview: fs::read_to_string(repo.join("AREAMATRIX.md"))
            .expect("read user AREAMATRIX"),
        user_visible_paths: user_visible_paths(repo),
    }
}

pub fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .ok()
}

pub fn install_privacy_update_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER ai_privacy_rules_validation_abort_update
             BEFORE UPDATE ON repo_config
             WHEN NEW.key = 'ai_privacy_rules'
             BEGIN
               SELECT RAISE(ABORT, 'forced privacy validation failure');
             END;",
        )
        .expect("install privacy update failure trigger");
}

pub fn assert_secret_free(value: &str) {
    for fragment in [
        SECRET_VALUE,
        TEST_SECRET_ENV,
        "Bearer",
        "sk-secret",
        "api_key",
        "token=",
        "keychain:",
    ] {
        assert!(
            !value.contains(fragment),
            "unexpected secret fragment `{fragment}` in `{value}`"
        );
    }
}

pub fn assert_c3_09_validation_alignment() {
    assert_public_signatures();
    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_alignment();
    assert_rust_implementation_alignment();
    assert_existing_c3_09_test_layers_are_present();
}

fn assert_public_signatures() {
    fn assert_list(_: fn(String) -> CoreResult<AiPrivacyRulesSnapshot>) {}
    fn assert_update(
        _: fn(String, AiPrivacyRulesUpdateRequest) -> CoreResult<AiPrivacyRulesSnapshot>,
    ) {
    }
    fn assert_evaluate(
        _: fn(String, AiPrivacyEvaluationRequest) -> CoreResult<AiPrivacyEvaluationReport>,
    ) {
    }
    assert_list(list_ai_privacy_rules);
    assert_update(update_ai_privacy_rules);
    assert_evaluate(evaluate_ai_privacy);
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-2/task-44: C3-09 validation",
        "为 C3-09 ai-privacy-rules 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "./dev check task 4-2/task-44",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "计划新增：`list_ai_privacy_rules`、`update_ai_privacy_rules`、`evaluate_ai_privacy`",
        "目录规则、关键词规则、字段过滤规则、`privacy_gate_enabled`、provider scope snapshot。",
        "allow/deny/skipped reason。",
        "provider gate reason，例如 `privacy_gate_disabled`、`scope_not_allowed`、`provider_not_verified`。",
        "命中规则时不发送文件内容到 AI。",
        "默认策略偏保守。",
        "关闭 `privacy_gate_enabled` 只阻止远程调用，不删除 provider 配置、Keychain key 或既有 AI 结果。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-09 | ai-privacy-rules | C3-01, C3-03, C3-09 | privacy rule CRUD/evaluate | ai_privacy_rules |",
        "| S3-10 | ai-fallback | C3-04, C3-08, C3-10 | fallback status | ai_call_log |",
        "远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_alignment() {
    for fragment in [
        "AiPrivacyRulesSnapshot list_ai_privacy_rules(string repo_path);",
        "AiPrivacyRulesSnapshot update_ai_privacy_rules(",
        "AiPrivacyEvaluationReport evaluate_ai_privacy(",
        "dictionary AiPrivacyRulesSnapshot",
        "dictionary AiPrivacyRulesUpdateRequest",
        "dictionary AiPrivacyEvaluationRequest",
        "dictionary AiPrivacyEvaluationReport",
        "sequence<AiPrivacyInputField> sent_fields;",
        "enum AiPrivacySkippedReason",
        "\"PrivacyGateDisabled\"",
        "\"ScopeNotAllowed\"",
        "\"ProviderNotVerified\"",
        "\"NoEligibleInput\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "pub fn list_ai_privacy_rules(",
        "pub fn update_ai_privacy_rules(",
        "pub fn evaluate_ai_privacy(",
        "ai_privacy_rules::list_ai_privacy_rules",
        "ai_privacy_rules::update_ai_privacy_rules",
        "ai_privacy_rules::evaluate_ai_privacy",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "pub use ai_privacy_rules::{",
        "AiPrivacyDecision",
        "AiPrivacyEvaluationReport",
        "AiPrivacyRulesSnapshot",
        "AiPrivacyRulesUpdateRequest",
    ] {
        assert_contains(LIB_RS, fragment);
    }
}

fn assert_rust_implementation_alignment() {
    for fragment in [
        "pub enum AiPrivacyRuleKind",
        "pub enum AiPrivacySkippedReason",
        "pub struct AiPrivacyRulesSnapshot",
        "pub struct AiPrivacyRulesUpdateRequest",
        "pub struct AiPrivacyEvaluationReport",
        "pub fn list_ai_privacy_rules(",
        "pub fn update_ai_privacy_rules(",
        "pub fn evaluate_ai_privacy(",
    ] {
        assert_contains(PRIVACY_RULES_RS, fragment);
    }

    for fragment in [
        "remote_provider_gate",
        "matching_rules",
        "field_filter",
        "sent_fields: Vec::new()",
    ] {
        assert_contains(PRIVACY_EVALUATION_RS, fragment);
    }

    for fragment in [
        "remote_blocked_by_default: true",
        "provider_scope_for_repo",
        "ensure_provider_ready",
        "db::update_ai_privacy_rules_record",
    ] {
        assert_contains(PRIVACY_PERSISTENCE_RS, fragment);
    }

    for fragment in [
        "validate_update_request",
        "validate_evaluation_request",
        "validate_provider_ready",
        "validate_field_rules",
        "validate_relative_path",
    ] {
        assert_contains(PRIVACY_VALIDATION_RS, fragment);
    }

    for fragment in [
        "AI_PRIVACY_RULES_KEY",
        "load_ai_privacy_rules_record",
        "update_ai_privacy_rules_record",
        "transaction()",
    ] {
        assert_contains(DB_PRIVACY_RULES_RS, fragment);
    }
}

fn assert_existing_c3_09_test_layers_are_present() {
    let tests = format!("{CONTRACT_TEST}\n{IMPLEMENTATION_TEST}\n{FAILURE_TEST}");
    for fragment in [
        "ai_privacy_rules_contract_docs_api_udl_and_control_map_stay_aligned",
        "ai_privacy_rules_contract_documents_consumers_and_forbidden_adjacent_behavior",
        "ai_privacy_rules_implementation_persists_and_reloads_rules_without_user_file_writes",
        "ai_privacy_rules_implementation_evaluates_provider_gates_and_field_filters",
        "ai_privacy_rules_implementation_rejects_invalid_updates_and_rolls_back",
        "ai_privacy_rules_failure_empty_state_is_default_off_and_side_effect_free",
        "ai_privacy_rules_failure_invalid_inputs_are_config_and_non_mutating",
        "ai_privacy_rules_failure_db_abort_rolls_back_to_previous_snapshot",
        "ai_privacy_rules_failure_provider_keys_never_surface_through_c3_09",
    ] {
        assert_contains(&tests, fragment);
    }
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("path is inside repository")
            .to_string_lossy()
            .into_owned();
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_not_contains(haystack: &str, needle: &str) {
    assert!(
        !haystack.contains(needle),
        "expected text not to contain `{needle}`"
    );
}
