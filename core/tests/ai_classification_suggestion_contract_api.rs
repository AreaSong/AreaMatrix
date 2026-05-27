use area_matrix_core::{
    suggest_category_with_ai, AiCategorySuggestion, AiCategorySuggestionContextField,
    AiCategorySuggestionContextPolicy, AiCategorySuggestionRequest, AiCategorySuggestionRoute,
    AiCategorySuggestionSkipReason, AiCategorySuggestionStatus, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-16-c3-04-contract-api.md");
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-3-ai/C3-04-ai-classification-suggestion.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const CLASSIFICATION_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-04-ai-classification-suggestion.md");
const FALLBACK_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-10-ai-fallback.md");
const STAGE_3_INDEX: &str = include_str!("../../docs/ux/page-specs/stage-3-ai.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const AI_CLASSIFICATION_RS: &str = include_str!("../src/ai_classification_suggestion.rs");
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
        "# C3-04 ai-classification-suggestion",
        "- S3-04 ai-classification-suggestion",
        "- S3-10 ai-fallback",
        "计划新增：`suggest_category_with_ai(repo_path, file_id) -> AiCategorySuggestion`",
        "file_id、上下文提取策略、privacy policy。",
        "建议分类、confidence、reason、是否本地/远程。",
        "写 AI call log。",
        "用户采纳前不改 `files.category`。",
        "可只读提取文件名、路径、有限文本摘要；受隐私规则限制。",
        "- `Config`",
        "- `PermissionDenied`",
        "- `Internal`",
        "只在规则分类失败或低置信时介入。",
        "建议必须等待用户确认。",
        "隐私规则命中时返回 skipped reason。",
        "全自动重分类不在 Stage 3。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-04 | ai-classification-suggestion | C3-04, C3-09, C3-10 | AI category suggestion | ai_call_log, no write before confirm",
        "| S3-10 | ai-fallback | C3-04, C3-08, C3-10 | fallback status | ai_call_log",
        "AI 默认关闭，本地优先。",
        "AI 结果在用户确认前都是草稿，不直接写分类、标签、摘要。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
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
        "C3-04 的 AI 分类建议入口",
        "`S3-04 ai-classification-suggestion`",
        "`S3-10 ai-fallback`",
        "返回 `AiCategorySuggestion`",
        "本 API 只生成建议草稿",
        "不得写 `files.category`",
        "不得移动、删除、重命名、覆盖用户文件",
        "高置信规则结果必须返回",
        "远程路线必须同时通过 C3-01 AI settings、C3-03 remote provider gate、C3-09 privacy gate",
        "隐私规则命中时必须返回 `Skipped` / `PrivacyRule`",
        "S3-04 可以从合同得到当前分类、建议分类、confidence、reason、local/remote route",
        "S3-10 可以从 `status`、`skipped_reason`、`route` 和 `call_log_id`",
        "本合同不新增 control map 之外的页面能力",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Internal"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}

#[test]
fn ai_classification_suggestion_contract_documents_consumers_and_boundaries() {
    for fragment in [
        "AI 只给建议，用户确认前不移动文件、不改分类。",
        "显示文件当前分类和 AI 建议分类。",
        "显示置信度和建议理由。",
        "显示使用的数据范围：文件名、扩展名、摘要、文本片段等。",
        "支持 `Accept`、`Change...`、`Reject`。",
        "支持查看 AI 调用日志条目。",
        "支持用户手动请求 AI 建议，但请求前必须经过 AI 设置、provider 状态和隐私规则 gate。",
        "Skipped by privacy rule",
        "AI 失败时进入 `S3-10 ai-fallback`。",
        "Accept 前只显示目标分类和目标路径预览，不修改分类、不移动文件。",
        "远程建议能从日志中追溯到 provider。",
    ] {
        assert_contains(CLASSIFICATION_PAGE, fragment);
    }

    for fragment in [
        "显示 AI 失败原因。",
        "区分错误、跳过、未配置、不可用。",
        "提供非 AI 回退动作。",
        "Retry 只重试同一 provider、同一 model、同一 feature scope 和同一输入快照",
        "隐私规则命中不是错误",
        "AI 失败不改变文件、分类、标签或摘要。",
        "宿主级非 AI 回退映射",
        "AI 分类宿主：显示 `Classify manually`",
    ] {
        assert_contains(FALLBACK_PAGE, fragment);
    }

    for fragment in [
        "AI 默认关闭；本地模型为默认推荐路径。",
        "AI 只在规则分类失败或低置信度时介入；失败时回退到本地规则或 inbox。",
        "自动摘要、自动标签、AI 分类结果在用户确认前都是建议或草稿",
        "隐私规则命中必须在对应 AI 页面显示跳过原因，并在 AI 调用日志中可追溯。",
        "AI 失败不得自动切换远程 provider；本地模型失败不得自动启用远程 AI。",
    ] {
        assert_contains(STAGE_3_INDEX, fragment);
    }

    assert_contains(
        AI_CLASSIFICATION_RS,
        "C3-04 AI classification suggestion contract types",
    );
    for fragment in [
        "suggest_category_with_ai",
        "AI classification suggestion implementation is pending",
        "looks_sensitive",
        "privacy policy reference is invalid",
    ] {
        assert_contains(AI_CLASSIFICATION_RS, fragment);
    }

    for fragment in [
        "Requests a C3-04 AI category suggestion without applying it.",
        "Returned suggestions are drafts only",
        "must not overwrite classifier rules",
        "requires_user_confirmation",
        "log persistence and privacy-rule CRUD remain owned by",
    ] {
        assert_contains(API_RS, fragment);
    }
}
