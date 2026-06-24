use area_matrix_core::{
    suggest_category_with_ai, AiCategorySuggestion, AiCategorySuggestionContextField,
    AiCategorySuggestionContextPolicy, AiCategorySuggestionRequest, AiCategorySuggestionRoute,
    AiCategorySuggestionSkipReason, AiCategorySuggestionStatus, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../workflow/versions/v1-mvp/execution/phase-4/4-2-stage3-ai/task-16-c3-04-contract-api.md"
);
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
const AI_CLASSIFICATION_RS: &str = include_str!("../src/ai_classification_suggestion.rs");
const AI_CLASSIFICATION_IMPL_RS: &str =
    include_str!("../src/ai_classification_suggestion/implementation.rs");
const AI_CALL_LOG_SCHEMA_RS: &str = include_str!("../src/db/ai_call_log/schema.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn request() -> AiCategorySuggestionRequest {
    AiCategorySuggestionRequest {
        file_id: 42,
        context_policy: AiCategorySuggestionContextPolicy::LimitedTextSummary,
        privacy_policy_ref: Some("default-remote-gate".to_owned()),
    }
}

#[test]
fn ai_classification_suggestion_contract_exposes_signature_input_output_and_errors() {
    fn assert_suggest(
        _: fn(String, AiCategorySuggestionRequest) -> CoreResult<AiCategorySuggestion>,
    ) {
    }
    assert_suggest(suggest_category_with_ai);

    let suggestion = AiCategorySuggestion {
        file_id: 42,
        status: AiCategorySuggestionStatus::Suggested,
        current_category: Some("inbox".to_owned()),
        suggested_category: Some("finance/invoices".to_owned()),
        confidence: 0.86,
        reason: Some("filename and limited summary mention invoice".to_owned()),
        route: Some(AiCategorySuggestionRoute::Local),
        used_context: vec![
            AiCategorySuggestionContextField::FileName,
            AiCategorySuggestionContextField::Extension,
            AiCategorySuggestionContextField::LimitedTextSummary,
        ],
        skipped_reason: None,
        privacy_rule_id: None,
        call_log_id: Some(7),
        requires_user_confirmation: true,
    };
    assert_eq!(suggestion.status, AiCategorySuggestionStatus::Suggested);
    assert_eq!(
        suggestion.suggested_category.as_deref(),
        Some("finance/invoices")
    );
    assert!(suggestion.requires_user_confirmation);

    let skipped = AiCategorySuggestion {
        file_id: 42,
        status: AiCategorySuggestionStatus::Skipped,
        current_category: Some("inbox".to_owned()),
        suggested_category: None,
        confidence: 0.0,
        reason: Some("Skipped by privacy rule".to_owned()),
        route: None,
        used_context: Vec::new(),
        skipped_reason: Some(AiCategorySuggestionSkipReason::PrivacyRule),
        privacy_rule_id: Some("rule:private-folder".to_owned()),
        call_log_id: Some(8),
        requires_user_confirmation: true,
    };
    assert_eq!(
        skipped.skipped_reason,
        Some(AiCategorySuggestionSkipReason::PrivacyRule)
    );

    let documented_errors = [
        CoreError::config("invalid AI category suggestion request"),
        CoreError::permission_denied("AI context unavailable"),
        CoreError::internal("AI runtime unavailable"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn ai_classification_suggestion_contract_rejects_invalid_inputs_without_fake_success() {
    assert!(matches!(
        suggest_category_with_ai(String::new(), request()),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_file = request();
    invalid_file.file_id = 0;
    assert!(matches!(
        suggest_category_with_ai("/tmp/repo".to_owned(), invalid_file),
        Err(CoreError::Config { .. })
    ));

    let mut raw_secret = request();
    raw_secret.privacy_policy_ref = Some("sk-secret-key-material".to_owned());
    assert!(matches!(
        suggest_category_with_ai("/tmp/repo".to_owned(), raw_secret),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        suggest_category_with_ai("/tmp/repo/.areamatrix".to_owned(), request()),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        suggest_category_with_ai("/tmp/repo".to_owned(), request()),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn ai_classification_suggestion_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-2/task-16: C3-04 contract-api",
        "为 C3-04 ai-classification-suggestion 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "AiCategorySuggestion suggest_category_with_ai(",
        "string repo_path, AiCategorySuggestionRequest request",
        "dictionary AiCategorySuggestionRequest",
        "i64 file_id;",
        "AiCategorySuggestionContextPolicy context_policy;",
        "string? privacy_policy_ref;",
        "dictionary AiCategorySuggestion",
        "AiCategorySuggestionStatus status;",
        "string? current_category;",
        "string? suggested_category;",
        "f32 confidence;",
        "AiCategorySuggestionRoute? route;",
        "sequence<AiCategorySuggestionContextField> used_context;",
        "AiCategorySuggestionSkipReason? skipped_reason;",
        "string? privacy_rule_id;",
        "i64? call_log_id;",
        "boolean requires_user_confirmation;",
        "enum AiCategorySuggestionContextPolicy",
        "\"FileNameOnly\"",
        "\"FileNameAndPath\"",
        "\"LimitedTextSummary\"",
        "enum AiCategorySuggestionStatus",
        "\"Suggested\"",
        "\"Skipped\"",
        "\"Unavailable\"",
        "enum AiCategorySuggestionSkipReason",
        "\"PrivacyRule\"",
        "\"ProviderUnavailable\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `suggest_category_with_ai(repo, request)` | ai | √ | Config / PermissionDenied / Internal |",
        "### `suggest_category_with_ai(repoPath: String, request: AiCategorySuggestionRequest) throws -> AiCategorySuggestion`",
        "AI category suggestion 的 AI 分类建议入口",
        "`AI category suggestion surface ai-classification-suggestion`",
        "`AI fallback`",
        "返回 `AiCategorySuggestion`",
        "本 API 只生成建议草稿",
        "不得写 `files.category`",
        "不得移动、删除、重命名、覆盖用户文件",
        "高置信规则结果必须返回",
        "远程路线必须同时通过 AI settings、remote provider gate、AI privacy gate",
        "隐私规则命中时必须返回 `Skipped` / `PrivacyRule`",
        "AI category suggestion surface 可以从合同得到当前分类、建议分类、confidence、reason、local/remote route",
        "AI fallback surface 可以从 `status`、`skipped_reason`、`route` 和 `call_log_id`",
        "本合同不新增 control map 之外的页面能力",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Internal"] {
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}

#[test]
fn ai_classification_suggestion_contract_documents_consumers_and_boundaries() {
    assert_contains(
        AI_CLASSIFICATION_RS,
        "AI category suggestion AI classification suggestion contract types and entry point",
    );
    for fragment in [
        "suggest_category_with_ai",
        "looks_sensitive",
        "privacy policy reference is invalid",
    ] {
        assert_contains(AI_CLASSIFICATION_RS, fragment);
    }

    for fragment in [
        "get_active_file_by_id",
        "requires_user_confirmation: true",
        "RuleResultConfident",
        "PrivacyRule",
        "ProviderUnavailable",
        "execute_suggestion",
        "unavailable_after_runtime_error",
        "insert_call_log",
    ] {
        assert_contains(AI_CLASSIFICATION_IMPL_RS, fragment);
    }

    for fragment in [
        "CREATE TABLE IF NOT EXISTS ai_call_log",
        "sent_fields_json",
        "status TEXT NOT NULL CHECK",
        "FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE SET NULL",
    ] {
        assert_contains(AI_CALL_LOG_SCHEMA_RS, fragment);
    }

    for fragment in [
        "Requests an AI category suggestion without applying it.",
        "Returned suggestions are drafts only",
        "must not overwrite classifier rules",
        "requires_user_confirmation",
        "log persistence and privacy-rule CRUD remain owned by",
    ] {
        assert_contains(API_RS, fragment);
    }
}
