use area_matrix_core::{
    get_ai_fallback_status, AiCallLogRoute, AiCallLogStatus, AiCategorySuggestionSkipReason,
    AiFallbackAction, AiFallbackCategory, AiFallbackKind, AiFallbackOperation,
    AiFallbackProviderErrorKind, AiFallbackStatus, AiFallbackStatusRequest, AiPrivacyDecision,
    AiPrivacySkippedReason, CoreError, CoreResult, SemanticSearchFallbackReason,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-46-c3-10-contract-api.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-10-ai-fallback.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const FALLBACK_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-10-ai-fallback.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const AI_FALLBACK_RS: &str = include_str!("../src/ai_fallback.rs");
const AI_FALLBACK_VALIDATION_RS: &str = include_str!("../src/ai_fallback/validation.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn privacy_request() -> AiFallbackStatusRequest {
    AiFallbackStatusRequest {
        operation: AiFallbackOperation::ClassificationSuggestion,
        route: None,
        provider_error: None,
        provider_error_code: None,
        privacy_decision: Some(AiPrivacyDecision::Denied),
        privacy_skipped_reason: Some(AiPrivacySkippedReason::PrivacyRule),
        category_skipped_reason: Some(AiCategorySuggestionSkipReason::PrivacyRule),
        semantic_fallback_reason: None,
        call_log_status: Some(AiCallLogStatus::Skipped),
        call_log_id: Some(7),
        privacy_rule_id: Some("rule:private-folder".to_owned()),
        retry_after: None,
    }
}

fn remote_failed_request() -> AiFallbackStatusRequest {
    AiFallbackStatusRequest {
        operation: AiFallbackOperation::SemanticSearch,
        route: Some(AiCallLogRoute::Remote),
        provider_error: Some(AiFallbackProviderErrorKind::RemoteFailed),
        provider_error_code: Some("ProviderUnavailable".to_owned()),
        privacy_decision: Some(AiPrivacyDecision::Allowed),
        privacy_skipped_reason: None,
        category_skipped_reason: None,
        semantic_fallback_reason: None,
        call_log_status: Some(AiCallLogStatus::Failed),
        call_log_id: Some(8),
        privacy_rule_id: None,
        retry_after: None,
    }
}

#[test]
fn ai_fallback_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_status(_: fn(String, AiFallbackStatusRequest) -> CoreResult<AiFallbackStatus>) {}
    assert_status(get_ai_fallback_status);

    let privacy_status =
        get_ai_fallback_status("/tmp/repo".to_owned(), privacy_request()).expect("status");
    assert_eq!(privacy_status.kind, AiFallbackKind::PrivacySkipped);
    assert_eq!(privacy_status.category, AiFallbackCategory::Skipped);
    assert!(!privacy_status.retryable);
    assert_eq!(
        privacy_status.primary_action,
        Some(AiFallbackAction::ViewPrivacyRule)
    );
    assert_eq!(
        privacy_status.secondary_action,
        Some(AiFallbackAction::ViewCallLog)
    );
    assert_eq!(
        privacy_status.non_ai_fallback_action,
        AiFallbackAction::ClassifyManually
    );

    let remote_status =
        get_ai_fallback_status("/tmp/repo".to_owned(), remote_failed_request()).expect("status");
    assert_eq!(remote_status.kind, AiFallbackKind::RemoteFailed);
    assert_eq!(remote_status.category, AiFallbackCategory::Error);
    assert!(remote_status.retryable);
    assert_eq!(remote_status.primary_action, Some(AiFallbackAction::Retry));
    assert_eq!(
        remote_status.non_ai_fallback_action,
        AiFallbackAction::UseNormalSearch
    );

    let semantic_index_status = get_ai_fallback_status(
        "/tmp/repo".to_owned(),
        AiFallbackStatusRequest {
            operation: AiFallbackOperation::EmbeddingIndexBuild,
            route: Some(AiCallLogRoute::Local),
            provider_error: None,
            provider_error_code: None,
            privacy_decision: Some(AiPrivacyDecision::Allowed),
            privacy_skipped_reason: None,
            category_skipped_reason: None,
            semantic_fallback_reason: Some(SemanticSearchFallbackReason::SemanticIndexNotReady),
            call_log_status: Some(AiCallLogStatus::Unavailable),
            call_log_id: None,
            privacy_rule_id: None,
            retry_after: None,
        },
    )
    .expect("status");
    assert_eq!(
        semantic_index_status.primary_action,
        Some(AiFallbackAction::BuildSemanticIndex)
    );
    assert_eq!(
        semantic_index_status.secondary_action,
        Some(AiFallbackAction::UseNormalSearch)
    );

    let documented_errors = [
        CoreError::config("invalid AI fallback request"),
        CoreError::permission_denied("fallback metadata unavailable"),
        CoreError::internal("fallback status resolution failed"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn ai_fallback_contract_rejects_invalid_inputs_without_fake_success() {
    assert!(matches!(
        get_ai_fallback_status(String::new(), privacy_request()),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        get_ai_fallback_status("/tmp/repo/.areamatrix".to_owned(), privacy_request()),
        Err(CoreError::Config { .. })
    ));

    let mut missing_reason = privacy_request();
    missing_reason.provider_error = None;
    missing_reason.provider_error_code = None;
    missing_reason.privacy_decision = None;
    missing_reason.privacy_skipped_reason = None;
    missing_reason.category_skipped_reason = None;
    missing_reason.semantic_fallback_reason = None;
    missing_reason.call_log_status = None;
    assert!(matches!(
        get_ai_fallback_status("/tmp/repo".to_owned(), missing_reason),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_log = privacy_request();
    invalid_log.call_log_id = Some(0);
    assert!(matches!(
        get_ai_fallback_status("/tmp/repo".to_owned(), invalid_log),
        Err(CoreError::Config { .. })
    ));

    let mut raw_secret = remote_failed_request();
    raw_secret.provider_error_code = Some("sk-secret-key-material".to_owned());
    assert!(matches!(
        get_ai_fallback_status("/tmp/repo".to_owned(), raw_secret),
        Err(CoreError::Config { .. })
    ));

    let mut unsafe_rule = privacy_request();
    unsafe_rule.privacy_rule_id = Some("rules/private-folder".to_owned());
    assert!(matches!(
        get_ai_fallback_status("/tmp/repo".to_owned(), unsafe_rule),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_retry = remote_failed_request();
    invalid_retry.retry_after = Some(-1);
    assert!(matches!(
        get_ai_fallback_status("/tmp/repo".to_owned(), invalid_retry),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn ai_fallback_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-2/task-46: C3-10 contract-api",
        "为 C3-10 ai-fallback 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C3-10 ai-fallback",
        "- S3-10 ai-fallback",
        "计划新增：`get_ai_fallback_status`。",
        "AI operation、provider error、privacy decision。",
        "fallback kind、user message、retry ability。",
        "记录 AI call failure。",
        "- `Config`",
        "- `Internal`",
        "- `PermissionDenied`",
        "AI 失败不阻断导入、普通搜索、本地规则分类。",
        "不自动切换远程 provider。",
        "UI 能展示是失败、禁用、隐私跳过还是模型不可用。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-04 | ai-classification-suggestion | C3-04, C3-09, C3-10 | AI category suggestion | ai_call_log, no write before confirm",
        "| S3-08 | semantic-search-results | C3-08, C3-09, C3-10 | semantic search / embedding | embedding metadata, ai_call_log",
        "| S3-10 | ai-fallback | C3-04, C3-08, C3-10 | fallback status | ai_call_log",
        "| S3-06 | ai-summary-editor | C3-06, C3-09 | generate/save/clear summary",
        "| S3-07 | ai-tags-suggestion | C3-07, C3-09 | suggest/apply tags",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "AiFallbackStatus get_ai_fallback_status(",
        "string repo_path, AiFallbackStatusRequest request",
        "dictionary AiFallbackStatusRequest",
        "AiFallbackOperation operation;",
        "AiFallbackProviderErrorKind? provider_error;",
        "AiPrivacyDecision? privacy_decision;",
        "SemanticSearchFallbackReason? semantic_fallback_reason;",
        "dictionary AiFallbackStatus",
        "AiFallbackKind kind;",
        "AiFallbackCategory category;",
        "boolean retryable;",
        "AiFallbackAction non_ai_fallback_action;",
        "enum AiFallbackOperation",
        "\"ClassificationSuggestion\"",
        "\"EmbeddingIndexBuild\"",
        "enum AiFallbackKind",
        "\"PrivacySkipped\"",
        "\"SemanticIndexNotReady\"",
        "enum AiFallbackAction",
        "\"OpenLocalModelStatus\"",
        "\"UseNormalSearch\"",
        "\"ClassifyManually\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `get_ai_fallback_status(repoPath: String, request: AiFallbackStatusRequest) throws -> AiFallbackStatus`",
        "C3-10 的 AI fallback 状态标准化入口",
        "S3-10 可以从 `kind`、`category`、`title`、`message`、`retryable`",
        "本合同不新增 control map 之外的页面能力",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn ai_fallback_contract_documents_consumer_state_and_safety_boundaries() {
    for fragment in [
        "显示 AI 失败原因。",
        "区分错误、跳过、未配置、不可用。",
        "`Retry` 禁用条件",
        "远程失败不得自动改用另一个 provider。",
        "本地失败不得自动启用远程 AI。",
        "AI 失败不改变文件、分类、标签或摘要。",
        "隐私跳过可跳转规则详情，并在调用日志中以 sent fields none 追溯。",
    ] {
        assert_contains(FALLBACK_PAGE, fragment);
    }

    for fragment in [
        "Normalizes C3-10 AI fallback metadata",
        "must not include raw provider output",
        "does not execute AI calls, switch providers, enable remote AI",
        "Returns `CoreError::Config { reason }`",
        "`CoreError::PermissionDenied { path }`",
        "`CoreError::Internal { message }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C3-10 AI fallback status contract",
        "AI operation whose failure or skipped state needs standard fallback UI",
        "Standard AI fallback status returned to S3-10 consumers",
        "Remote AI could not be reached. Your files were not changed.",
    ] {
        assert_contains(AI_FALLBACK_RS, fragment);
    }

    for fragment in [
        "AI fallback repository path must not point inside metadata",
        "AI fallback provider error code is invalid",
        "AI fallback privacy rule id is invalid",
    ] {
        assert_contains(AI_FALLBACK_VALIDATION_RS, fragment);
    }

    for error_name in ["Config", "Internal", "PermissionDenied"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
    }
}
