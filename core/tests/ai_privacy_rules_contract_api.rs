use std::path::Path;

use area_matrix_core::{
    evaluate_ai_privacy, list_ai_privacy_rules, update_ai_privacy_rules, AiFeatureKind,
    AiPrivacyDecision, AiPrivacyEvaluationContext, AiPrivacyEvaluationReport,
    AiPrivacyEvaluationRequest, AiPrivacyEvaluationRoute, AiPrivacyFieldRule, AiPrivacyInputField,
    AiPrivacyProviderGateReason, AiPrivacyProviderScopeSnapshot, AiPrivacyRuleAppliesTo,
    AiPrivacyRuleInput, AiPrivacyRuleKind, AiPrivacyRuleMatch, AiPrivacyRulesSnapshot,
    AiPrivacyRulesUpdateRequest, AiPrivacySkippedReason, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-41-c3-09-contract-api.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-09-ai-privacy-rules.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const AI_PRIVACY_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-09-ai-privacy-rules.md");
const FALLBACK_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-10-ai-fallback.md");
const STAGE_3_INDEX: &str = include_str!("../../docs/ux/page-specs/stage-3-ai.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const PRIVACY_RULES_RS: &str = include_str!("../src/ai_privacy_rules.rs");
const PRIVACY_RULES_VALIDATION_RS: &str = include_str!("../src/ai_privacy_rules/validation.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const UDL: &str = include_str!("../area_matrix.udl");

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

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
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

fn field_rules() -> Vec<AiPrivacyFieldRule> {
    input_fields()
        .into_iter()
        .map(|field| AiPrivacyFieldRule {
            allow_remote: matches!(
                field,
                AiPrivacyInputField::FileName
                    | AiPrivacyInputField::RepoRelativePath
                    | AiPrivacyInputField::Extension
            ),
            field,
        })
        .collect()
}

fn provider_scope() -> AiPrivacyProviderScopeSnapshot {
    AiPrivacyProviderScopeSnapshot {
        provider_configured: true,
        provider_verified: true,
        remote_provider_enabled: true,
        feature_scope: vec![AiFeatureKind::AutoSummaries, AiFeatureKind::AutoTags],
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

fn folder_rule() -> AiPrivacyRuleInput {
    AiPrivacyRuleInput {
        rule_id: Some("rule:private-folder".to_owned()),
        name: "Private finance folder".to_owned(),
        kind: AiPrivacyRuleKind::Folder,
        pattern: "finance/private/".to_owned(),
        applies_to: AiPrivacyRuleAppliesTo::RemoteAi,
        enabled: true,
        description: Some("Block remote AI for private finance files".to_owned()),
    }
}

fn update_request() -> AiPrivacyRulesUpdateRequest {
    AiPrivacyRulesUpdateRequest {
        privacy_gate_enabled: true,
        rules: vec![folder_rule()],
        remote_allowed_fields: field_rules(),
        provider_scope: provider_scope(),
        confirmed: true,
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
        rules: vec![folder_rule()],
        remote_allowed_fields: field_rules(),
        context: evaluation_context(),
    }
}

#[test]
fn ai_privacy_rules_contract_exposes_signatures_inputs_outputs_and_errors() {
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

    let snapshot = AiPrivacyRulesSnapshot {
        privacy_gate_enabled: false,
        rules: Vec::new(),
        remote_allowed_fields: input_fields()
            .into_iter()
            .map(|field| area_matrix_core::AiPrivacyFieldState {
                field,
                allow_remote: false,
                last_matched_count: 0,
            })
            .collect(),
        provider_scope: disabled_provider_scope(),
        updated_at: None,
        remote_blocked_by_default: true,
    };
    assert!(!snapshot.privacy_gate_enabled);
    assert!(snapshot.remote_blocked_by_default);
    assert!(snapshot
        .remote_allowed_fields
        .iter()
        .all(|field| { !field.allow_remote && field.last_matched_count == 0 }));

    let report = AiPrivacyEvaluationReport {
        decision: AiPrivacyDecision::Skipped,
        skipped_reason: Some(AiPrivacySkippedReason::PrivacyRule),
        provider_gate_reason: None,
        matched_rules: vec![AiPrivacyRuleMatch {
            rule_id: "rule:private-folder".to_owned(),
            name: "Private finance folder".to_owned(),
            kind: AiPrivacyRuleKind::Folder,
            pattern: "finance/private/".to_owned(),
            applies_to: AiPrivacyRuleAppliesTo::RemoteAi,
            matched_field: Some(AiPrivacyInputField::RepoRelativePath),
        }],
        matched_field_type: Some(AiPrivacyInputField::RepoRelativePath),
        allowed_fields: vec![AiPrivacyInputField::FileName],
        blocked_fields: vec![AiPrivacyInputField::ExtractedTextExcerpt],
        sent_fields: Vec::new(),
        message: "Skipped by privacy rule".to_owned(),
    };
    assert_eq!(report.decision, AiPrivacyDecision::Skipped);
    assert_eq!(
        report.skipped_reason,
        Some(AiPrivacySkippedReason::PrivacyRule)
    );
    assert!(report.sent_fields.is_empty());

    let provider_skip = AiPrivacyEvaluationReport {
        decision: AiPrivacyDecision::Skipped,
        skipped_reason: Some(AiPrivacySkippedReason::ProviderNotVerified),
        provider_gate_reason: Some(AiPrivacyProviderGateReason::ProviderNotVerified),
        matched_rules: Vec::new(),
        matched_field_type: None,
        allowed_fields: Vec::new(),
        blocked_fields: Vec::new(),
        sent_fields: Vec::new(),
        message: "Remote provider needs connection test".to_owned(),
    };
    assert_eq!(
        provider_skip.provider_gate_reason,
        Some(AiPrivacyProviderGateReason::ProviderNotVerified)
    );

    let documented_errors = [
        CoreError::config("invalid AI privacy rule input"),
        CoreError::db("AI privacy metadata unavailable"),
    ];
    assert_eq!(documented_errors.len(), 2);
}

#[test]
fn ai_privacy_rules_contract_validates_inputs_without_fake_update_or_evaluate_success() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let repo_path = path_string(repo.path());

    let snapshot =
        list_ai_privacy_rules(repo_path.clone()).expect("load conservative privacy default");
    assert!(!snapshot.privacy_gate_enabled);
    assert!(snapshot.remote_blocked_by_default);
    assert_eq!(snapshot.remote_allowed_fields.len(), input_fields().len());
    assert!(!repo.path().join(".areamatrix").exists());

    assert!(matches!(
        list_ai_privacy_rules(String::new()),
        Err(CoreError::Config { .. })
    ));
    assert!(matches!(
        list_ai_privacy_rules(path_string(&repo.path().join(".areamatrix"))),
        Err(CoreError::Config { .. })
    ));

    let mut missing_confirmation = update_request();
    missing_confirmation.confirmed = false;
    assert!(matches!(
        update_ai_privacy_rules(repo_path.clone(), missing_confirmation),
        Err(CoreError::Config { .. })
    ));

    let mut provider_not_ready = update_request();
    provider_not_ready.provider_scope = disabled_provider_scope();
    assert!(matches!(
        update_ai_privacy_rules(repo_path.clone(), provider_not_ready),
        Err(CoreError::Config { .. })
    ));

    let mut stale_provider_scope = update_request();
    stale_provider_scope.privacy_gate_enabled = false;
    assert!(matches!(
        update_ai_privacy_rules(repo_path.clone(), stale_provider_scope),
        Err(CoreError::Config { .. })
    ));

    let mut missing_field = update_request();
    missing_field.remote_allowed_fields.pop();
    assert!(matches!(
        update_ai_privacy_rules(repo_path.clone(), missing_field),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        update_ai_privacy_rules(repo_path.clone(), update_request()),
        Err(CoreError::Config { .. })
    ));

    let mut duplicate_requested_field = evaluation_request();
    duplicate_requested_field
        .requested_fields
        .push(AiPrivacyInputField::FileName);
    assert!(matches!(
        evaluate_ai_privacy(repo_path.clone(), duplicate_requested_field),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_context = evaluation_request();
    invalid_context.context.repo_relative_path = Some("../private/report.pdf".to_owned());
    assert!(matches!(
        evaluate_ai_privacy(repo_path.clone(), invalid_context),
        Err(CoreError::Config { .. })
    ));

    let report =
        evaluate_ai_privacy(repo_path, evaluation_request()).expect("evaluate privacy request");
    assert_eq!(report.decision, AiPrivacyDecision::Denied);
    assert_eq!(
        report.skipped_reason,
        Some(AiPrivacySkippedReason::PrivacyRule)
    );
    assert!(report.sent_fields.is_empty());
}

#[test]
fn ai_privacy_rules_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-2/task-41: C3-09 contract-api",
        "为 C3-09 ai-privacy-rules 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C3-09 ai-privacy-rules",
        "- S3-09 ai-privacy-rules",
        "- S3-10 ai-fallback",
        "计划新增：`list_ai_privacy_rules`、`update_ai_privacy_rules`、`evaluate_ai_privacy`",
        "目录规则、关键词规则、字段过滤规则、`privacy_gate_enabled`、provider scope snapshot。",
        "allow/deny/skipped reason。",
        "provider gate reason，例如 `privacy_gate_disabled`、`scope_not_allowed`、`provider_not_verified`。",
        "- `Config`",
        "- `Db`",
        "默认策略偏保守。",
        "关闭 `privacy_gate_enabled` 只阻止远程调用，不删除 provider 配置、Keychain key 或既有 AI 结果。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-03 | remote-model-enable | C3-03, C3-09 | provider test/enable | provider metadata, Keychain ref",
        "| S3-04 | ai-classification-suggestion | C3-04, C3-09, C3-10 | AI category suggestion | ai_call_log",
        "| S3-06 | ai-summary-editor | C3-06, C3-09 | generate/save/clear summary | summary metadata, ai_call_log",
        "| S3-07 | ai-tags-suggestion | C3-07, C3-09 | suggest/apply tags | tags after confirm, ai_call_log",
        "| S3-08 | semantic-search-results | C3-08, C3-09, C3-10 | semantic search / embedding | embedding metadata, ai_call_log",
        "| S3-09 | ai-privacy-rules | C3-01, C3-03, C3-09 | privacy rule CRUD/evaluate | ai_privacy_rules",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "AiPrivacyRulesSnapshot list_ai_privacy_rules(string repo_path);",
        "AiPrivacyRulesSnapshot update_ai_privacy_rules(",
        "string repo_path, AiPrivacyRulesUpdateRequest request",
        "AiPrivacyEvaluationReport evaluate_ai_privacy(",
        "string repo_path, AiPrivacyEvaluationRequest request",
        "dictionary AiPrivacyRuleInput",
        "AiPrivacyRuleKind kind;",
        "AiPrivacyRuleAppliesTo applies_to;",
        "dictionary AiPrivacyRuleRecord",
        "i64 match_count;",
        "dictionary AiPrivacyFieldRule",
        "AiPrivacyInputField field;",
        "dictionary AiPrivacyProviderScopeSnapshot",
        "boolean provider_configured;",
        "boolean provider_verified;",
        "boolean remote_provider_enabled;",
        "sequence<AiFeatureKind> feature_scope;",
        "dictionary AiPrivacyRulesSnapshot",
        "boolean privacy_gate_enabled;",
        "sequence<AiPrivacyRuleRecord> rules;",
        "sequence<AiPrivacyFieldState> remote_allowed_fields;",
        "boolean remote_blocked_by_default;",
        "dictionary AiPrivacyEvaluationRequest",
        "sequence<AiPrivacyInputField> requested_fields;",
        "dictionary AiPrivacyEvaluationReport",
        "AiPrivacyDecision decision;",
        "AiPrivacySkippedReason? skipped_reason;",
        "AiPrivacyProviderGateReason? provider_gate_reason;",
        "sequence<AiPrivacyInputField> sent_fields;",
        "enum AiPrivacyRuleKind",
        "\"Folder\"",
        "\"Category\"",
        "\"Keyword\"",
        "\"Extension\"",
        "\"Tag\"",
        "enum AiPrivacySkippedReason",
        "\"PrivacyGateDisabled\"",
        "\"ScopeNotAllowed\"",
        "\"ProviderNotVerified\"",
        "\"FieldRule\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `list_ai_privacy_rules(repo)` | ai/privacy | √ | Config / Db |",
        "| `update_ai_privacy_rules(repo, request)` | ai/privacy | √ | Config / Db |",
        "| `evaluate_ai_privacy(repo, request)` | ai/privacy | √ | Config / Db |",
        "### `list_ai_privacy_rules(repoPath: String) throws -> AiPrivacyRulesSnapshot`",
        "### `update_ai_privacy_rules(repoPath: String, request: AiPrivacyRulesUpdateRequest) throws -> AiPrivacyRulesSnapshot`",
        "### `evaluate_ai_privacy(repoPath: String, request: AiPrivacyEvaluationRequest) throws -> AiPrivacyEvaluationReport`",
        "C3-09 的 AI 隐私规则读取入口",
        "C3-09 的隐私规则保存入口",
        "C3-09 的隐私 gate 评估入口",
        "默认保守策略",
        "本合同不新增 control map 之外的页面能力",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Config", "Db"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}

#[test]
fn ai_privacy_rules_contract_documents_consumers_and_forbidden_adjacent_behavior() {
    for fragment in [
        "Remote AI privacy gate",
        "Block remote AI with privacy gate",
        "本区是隐私 gate，不是 provider 禁用页",
        "`Block remote AI with privacy gate` 不得被实现为 S3-03 的 `Disable remote AI`",
        "provider_configured",
        "provider_verified",
        "remote_provider_enabled",
        "feature_scope",
        "Remote allowed fields",
        "`note summary` 说明：`Derived from your note. Full note text is never sent.`",
        "Folder、Category、Keyword、Extension、Tag 五类规则均可编辑。",
        "Test rules 能显示 provider/scope/gate 三类阻断来源",
        "远程 gate 或字段过滤命中时 AI 页面显示跳过",
    ] {
        assert_contains(AI_PRIVACY_PAGE, fragment);
    }

    for fragment in [
        "Skipped by privacy rule",
        "`privacy_skipped`",
        "This file matches a privacy rule, so AI was skipped.",
        "Retry 不应重复发送被隐私规则禁止的内容。",
        "隐私跳过可跳转规则详情",
        "sent fields none",
    ] {
        assert_contains(FALLBACK_PAGE, fragment);
    }

    for fragment in [
        "AI 默认关闭；本地模型为默认推荐路径。",
        "远程模型必须由用户显式配置 key、选择使用范围、测试连接成功并确认数据流向后启用",
        "远程 AI 可发送的字段类型必须逐项展示，并在调用前经过 S3-09 隐私规则 gate",
        "AI 失败不得自动切换远程 provider；本地模型失败不得自动启用远程 AI。",
    ] {
        assert_contains(STAGE_3_INDEX, fragment);
    }

    for fragment in [
        "C3-09 AI privacy rules contract types and entry points",
        "pub enum AiPrivacyRuleKind",
        "pub enum AiPrivacyRuleAppliesTo",
        "pub enum AiPrivacyInputField",
        "pub enum AiPrivacySkippedReason",
        "pub struct AiPrivacyRulesSnapshot",
        "pub struct AiPrivacyRulesUpdateRequest",
        "pub struct AiPrivacyEvaluationRequest",
        "pub struct AiPrivacyEvaluationReport",
        "pub fn list_ai_privacy_rules(",
        "pub fn update_ai_privacy_rules(",
        "pub fn evaluate_ai_privacy(",
        "mod validation",
    ] {
        assert_contains(PRIVACY_RULES_RS, fragment);
    }

    for fragment in ["validate_field_rules", "validate_provider_ready"] {
        assert_contains(PRIVACY_RULES_VALIDATION_RS, fragment);
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
        "AiPrivacyDecision",
        "AiPrivacyEvaluationReport",
        "AiPrivacyRulesSnapshot",
        "AiPrivacyRulesUpdateRequest",
    ] {
        assert_contains(LIB_RS, fragment);
    }

    for forbidden in [
        "disable_remote_ai_provider",
        "clear_ai_call_log",
        "generate_ai_summary(",
        "suggest_tags_with_ai(",
        "semantic_search(",
    ] {
        assert_not_contains(PRIVACY_RULES_RS, forbidden);
    }
}
