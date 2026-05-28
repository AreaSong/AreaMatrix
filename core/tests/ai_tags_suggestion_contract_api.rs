use area_matrix_core::{
    apply_ai_tag_suggestions, suggest_tags_with_ai, AiTagSuggestion,
    AiTagSuggestionApplyItemResult, AiTagSuggestionApplyReport, AiTagSuggestionApplyStatus,
    AiTagSuggestionCandidateStatus, AiTagSuggestionInputField, AiTagSuggestionMergeAction,
    AiTagSuggestionReport, AiTagSuggestionReportStatus, AiTagSuggestionRequest,
    AiTagSuggestionRoute, AiTagSuggestionSkipReason, ApplyAiTagSuggestionItem,
    ApplyAiTagSuggestionsRequest, CoreError, CoreResult, TagRecord, TagSet,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-31-c3-07-contract-api.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-07-ai-tags-suggestion.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const AI_TAGS_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-07-ai-tags-suggestion.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const AI_TAGS_RS: &str = include_str!("../src/ai_tags_suggestion.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn request() -> AiTagSuggestionRequest {
    AiTagSuggestionRequest {
        file_id: 42,
        candidate_tags: vec!["finance".to_owned(), "invoice".to_owned()],
        privacy_policy_ref: Some("default-remote-gate".to_owned()),
    }
}

fn apply_item() -> ApplyAiTagSuggestionItem {
    ApplyAiTagSuggestionItem {
        suggestion_id: "ai-tag:finance".to_owned(),
        slug: "finance".to_owned(),
        display_name: "Finance".to_owned(),
        confidence: 0.86,
        edited_by_user: false,
        merge_target_slug: None,
    }
}

fn apply_request() -> ApplyAiTagSuggestionsRequest {
    ApplyAiTagSuggestionsRequest {
        file_id: 42,
        suggestions: vec![apply_item()],
        call_log_id: Some(7),
        privacy_rule_id: None,
        confirmed: true,
    }
}

fn tag_set() -> TagSet {
    TagSet {
        file_id: 42,
        file_tags: vec![TagRecord {
            value: "finance".to_owned(),
            label: "Finance".to_owned(),
            file_count: 12,
            selected: true,
            disabled: false,
            updated_at: 1_777_300_900,
        }],
        available_tags: Vec::new(),
        recent_tags: Vec::new(),
        updated_at: 1_777_300_900,
    }
}

#[test]
fn ai_tags_suggestion_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_suggest(_: fn(String, AiTagSuggestionRequest) -> CoreResult<AiTagSuggestionReport>) {}
    fn assert_apply(
        _: fn(String, ApplyAiTagSuggestionsRequest) -> CoreResult<AiTagSuggestionApplyReport>,
    ) {
    }
    assert_suggest(suggest_tags_with_ai);
    assert_apply(apply_ai_tag_suggestions);

    let suggestion = AiTagSuggestion {
        suggestion_id: "ai-tag:finance".to_owned(),
        slug: "finance".to_owned(),
        display_name: "Finance".to_owned(),
        confidence: 0.86,
        reason: "filename and summary mention invoice and payment".to_owned(),
        status: AiTagSuggestionCandidateStatus::Suggested,
        merge_action: AiTagSuggestionMergeAction::UseExistingTag,
        matched_existing_slug: Some("finance".to_owned()),
        selected_by_default: true,
        disabled_reason: None,
    };
    let report = AiTagSuggestionReport {
        file_id: 42,
        status: AiTagSuggestionReportStatus::Suggested,
        suggestions: vec![suggestion],
        route: Some(AiTagSuggestionRoute::Local),
        model_name: Some("Local tag model".to_owned()),
        generated_at: Some(1_777_300_800),
        used_context: vec![
            AiTagSuggestionInputField::FileName,
            AiTagSuggestionInputField::AiSummary,
        ],
        skipped_reason: None,
        privacy_rule_id: None,
        call_log_id: Some(7),
        requires_user_confirmation: true,
        confidence_threshold: 0.8,
        contents_read: true,
        ai_used: true,
        network_used: false,
    };
    assert_eq!(report.status, AiTagSuggestionReportStatus::Suggested);
    assert_eq!(report.suggestions[0].confidence, 0.86);
    assert!(report.requires_user_confirmation);
    assert!(!report.network_used);

    let skipped = AiTagSuggestionReport {
        file_id: 42,
        status: AiTagSuggestionReportStatus::Skipped,
        suggestions: Vec::new(),
        route: None,
        model_name: None,
        generated_at: None,
        used_context: Vec::new(),
        skipped_reason: Some(AiTagSuggestionSkipReason::PrivacyRule),
        privacy_rule_id: Some("rule:private-folder".to_owned()),
        call_log_id: Some(8),
        requires_user_confirmation: true,
        confidence_threshold: 0.8,
        contents_read: false,
        ai_used: false,
        network_used: false,
    };
    assert_eq!(
        skipped.skipped_reason,
        Some(AiTagSuggestionSkipReason::PrivacyRule)
    );

    let apply_report = AiTagSuggestionApplyReport {
        file_id: 42,
        requested_count: 1,
        applied_count: 1,
        skipped_count: 0,
        failed_count: 0,
        item_results: vec![AiTagSuggestionApplyItemResult {
            suggestion_id: "ai-tag:finance".to_owned(),
            slug: "finance".to_owned(),
            status: AiTagSuggestionApplyStatus::Applied,
            error: None,
        }],
        tag_set: tag_set(),
        undo_token: Some("undo:ai-tags:42".to_owned()),
        call_log_id: Some(7),
        refresh_targets: vec![
            "tags".to_owned(),
            "change_log".to_owned(),
            "undo_actions".to_owned(),
            "ai_call_log".to_owned(),
        ],
    };
    assert_eq!(apply_report.applied_count, 1);
    assert_eq!(
        apply_report.item_results[0].status,
        AiTagSuggestionApplyStatus::Applied
    );

    let documented_errors = [
        CoreError::config("invalid AI tag suggestion request"),
        CoreError::file_not_found("missing file id"),
        CoreError::db("AI tag metadata failed"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn ai_tags_suggestion_contract_rejects_invalid_inputs_without_fake_success() {
    assert!(matches!(
        suggest_tags_with_ai(String::new(), request()),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_file = request();
    invalid_file.file_id = 0;
    assert!(matches!(
        suggest_tags_with_ai("/tmp/repo".to_owned(), invalid_file),
        Err(CoreError::FileNotFound { .. })
    ));

    let mut raw_secret = request();
    raw_secret.privacy_policy_ref = Some("sk-secret-key-material".to_owned());
    assert!(matches!(
        suggest_tags_with_ai("/tmp/repo".to_owned(), raw_secret),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_candidate = request();
    invalid_candidate.candidate_tags = vec!["bad/tag".to_owned()];
    assert!(matches!(
        suggest_tags_with_ai("/tmp/repo".to_owned(), invalid_candidate),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        suggest_tags_with_ai("/tmp/repo".to_owned(), request()),
        Err(CoreError::Db { .. })
    ));

    let mut missing_confirmation = apply_request();
    missing_confirmation.confirmed = false;
    assert!(matches!(
        apply_ai_tag_suggestions("/tmp/repo".to_owned(), missing_confirmation),
        Err(CoreError::Config { .. })
    ));

    let mut empty_suggestions = apply_request();
    empty_suggestions.suggestions.clear();
    assert!(matches!(
        apply_ai_tag_suggestions("/tmp/repo".to_owned(), empty_suggestions),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_slug = apply_request();
    invalid_slug.suggestions[0].slug = "bad/tag".to_owned();
    assert!(matches!(
        apply_ai_tag_suggestions("/tmp/repo".to_owned(), invalid_slug),
        Err(CoreError::Config { .. })
    ));

    let mut duplicate_slug = apply_request();
    duplicate_slug.suggestions.push(ApplyAiTagSuggestionItem {
        suggestion_id: "ai-tag:finance-copy".to_owned(),
        ..apply_item()
    });
    assert!(matches!(
        apply_ai_tag_suggestions("/tmp/repo".to_owned(), duplicate_slug),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        apply_ai_tag_suggestions("/tmp/repo".to_owned(), apply_request()),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn ai_tags_suggestion_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-2/task-31: C3-07 contract-api",
        "为 C3-07 ai-tags-suggestion 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C3-07 ai-tags-suggestion",
        "- S3-07 ai-tags-suggestion",
        "计划新增：`suggest_tags_with_ai`、`apply_ai_tag_suggestions`",
        "file_id、候选标签、privacy policy。",
        "标签建议、confidence、reason。",
        "用户采纳后写 `tags`、change log 和 AI call log。",
        "- `Config`",
        "- `FileNotFound`",
        "- `Db`",
        "建议不自动写入标签。",
        "用户可以编辑、删除、采纳部分建议。",
        "隐私规则命中时不调用 provider。",
        "团队标签词库不在 Stage 3。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-07 | ai-tags-suggestion | C3-07, C3-09 | suggest/apply tags | tags after confirm, ai_call_log |",
        "AI 默认关闭，本地优先。",
        "AI 结果在用户确认前都是草稿，不直接写分类、标签、摘要。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "AiTagSuggestionReport suggest_tags_with_ai(",
        "string repo_path, AiTagSuggestionRequest request",
        "AiTagSuggestionApplyReport apply_ai_tag_suggestions(",
        "string repo_path, ApplyAiTagSuggestionsRequest request",
        "dictionary AiTagSuggestionRequest",
        "sequence<string> candidate_tags;",
        "dictionary AiTagSuggestion",
        "f32 confidence;",
        "AiTagSuggestionCandidateStatus status;",
        "AiTagSuggestionMergeAction merge_action;",
        "dictionary AiTagSuggestionReport",
        "AiTagSuggestionReportStatus status;",
        "sequence<AiTagSuggestionInputField> used_context;",
        "AiTagSuggestionSkipReason? skipped_reason;",
        "boolean requires_user_confirmation;",
        "dictionary ApplyAiTagSuggestionsRequest",
        "boolean confirmed;",
        "dictionary AiTagSuggestionApplyReport",
        "TagSet tag_set;",
        "enum AiTagSuggestionReportStatus",
        "\"Suggested\"",
        "\"Skipped\"",
        "\"Unavailable\"",
        "enum AiTagSuggestionApplyStatus { \"Applied\", \"AlreadyAdded\", \"Failed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `suggest_tags_with_ai(repo, request)` | ai | √ | Config / FileNotFound / Db |",
        "| `apply_ai_tag_suggestions(repo, request)` | ai | √ | Config / FileNotFound / Db |",
        "### `suggest_tags_with_ai(repoPath: String, request: AiTagSuggestionRequest) throws -> AiTagSuggestionReport`",
        "### `apply_ai_tag_suggestions(repoPath: String, request: ApplyAiTagSuggestionsRequest) throws -> AiTagSuggestionApplyReport`",
        "C3-07 的 AI 标签建议入口",
        "`S3-07 ai-tags-suggestion`",
        "本 API 只生成建议草稿",
        "不得调用 provider",
        "requires_user_confirmation",
        "本合同不新增 control map 之外的页面能力",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Config", "FileNotFound", "Db"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}

#[test]
fn ai_tags_suggestion_contract_documents_consumers_and_scope_boundaries() {
    for fragment in [
        "AI 自动标签默认是建议状态，用户采纳前不写入文件标签集合。",
        "显示 AI 建议标签 chips。",
        "显示每个标签的置信度或理由。",
        "支持采纳单个/全部高置信度标签。",
        "支持编辑标签名。",
        "支持合并到已有标签。",
        "支持拒绝建议。",
        "支持查看 AI 调用日志。",
        "Review before adding tags. AI suggestions are not applied until you accept them.",
        "Skipped by privacy rule",
        "生成建议前必须校验 AI 总开关、`Auto tags` 功能开关、provider 状态、远程显式启用、usage scope、隐私规则和调用日志写入能力。",
        "点击 `Accept selected` 时，single mode 立即写入选中标签；batch mode 先显示批量影响确认 sheet",
    ] {
        assert_contains(AI_TAGS_PAGE, fragment);
    }

    for fragment in [
        "C3-07 AI tag suggestion contract types and entry points",
        "pub enum AiTagSuggestionRoute",
        "pub enum AiTagSuggestionInputField",
        "pub enum AiTagSuggestionReportStatus",
        "pub enum AiTagSuggestionSkipReason",
        "pub enum AiTagSuggestionCandidateStatus",
        "pub enum AiTagSuggestionMergeAction",
        "pub struct AiTagSuggestionRequest",
        "pub struct AiTagSuggestion",
        "pub struct AiTagSuggestionReport",
        "pub struct ApplyAiTagSuggestionItem",
        "pub struct ApplyAiTagSuggestionsRequest",
        "pub struct AiTagSuggestionApplyReport",
        "pub(crate) fn suggest_tags_with_ai(",
        "pub(crate) fn apply_ai_tag_suggestions(",
        "validate_candidate_tags",
        "looks_sensitive",
    ] {
        assert_contains(AI_TAGS_RS, fragment);
    }

    for fragment in [
        "Generates C3-07 AI tag suggestions without applying them.",
        "Applies reviewed C3-07 AI tag suggestions after explicit confirmation.",
        "must not create or attach tags",
        "must never apply unselected suggestions",
        "ai_tags_suggestion::suggest_tags_with_ai",
        "ai_tags_suggestion::apply_ai_tag_suggestions",
    ] {
        assert_contains(API_RS, fragment);
    }

    for forbidden in [
        "execute_remote",
        "enable_remote_ai_provider(",
        "update_ai_config(",
        "save_classifier_rule",
        "import_file(",
        "delete_file(",
        "move_to_category(",
    ] {
        assert!(
            !AI_TAGS_RS.contains(forbidden),
            "C3-07 contract must not implement adjacent capability `{forbidden}`"
        );
    }
}
