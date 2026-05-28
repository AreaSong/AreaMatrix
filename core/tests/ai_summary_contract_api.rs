use area_matrix_core::{
    clear_ai_summary, generate_ai_summary, save_ai_summary, AiSummaryClearReport,
    AiSummaryClearRequest, AiSummaryContextPolicy, AiSummaryDraft, AiSummaryDraftStatus,
    AiSummaryGenerationRequest, AiSummaryInputField, AiSummaryProviderScope, AiSummaryRoute,
    AiSummarySaveReport, AiSummarySaveRequest, AiSummarySkipReason, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-26-c3-06-contract-api.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-06-ai-summary.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const AI_SUMMARY_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-06-ai-summary-editor.md");
const FALLBACK_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-10-ai-fallback.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const AI_SUMMARY_RS: &str = include_str!("../src/ai_summary.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn generation_request() -> AiSummaryGenerationRequest {
    AiSummaryGenerationRequest {
        file_id: 42,
        provider_scope: AiSummaryProviderScope::LocalPreferred,
        context_policy: AiSummaryContextPolicy::MetadataAndExtractedText,
        privacy_policy_ref: Some("default-remote-gate".to_owned()),
        regenerate_existing: false,
    }
}

fn save_request() -> AiSummarySaveRequest {
    AiSummarySaveRequest {
        file_id: 42,
        summary_text: "Invoice summary drafted by AI and edited by the user.".to_owned(),
        draft_id: Some("draft:summary:42".to_owned()),
        route: Some(AiSummaryRoute::Local),
        model_name: Some("Local summary model v1".to_owned()),
        generated_at: Some(1_777_300_800),
        used_context: vec![
            AiSummaryInputField::FileName,
            AiSummaryInputField::ExtractedTextExcerpt,
        ],
        privacy_rule_id: None,
        call_log_id: Some(7),
        edited_by_user: true,
    }
}

fn clear_request() -> AiSummaryClearRequest {
    AiSummaryClearRequest {
        file_id: 42,
        confirmed: true,
    }
}

#[test]
fn ai_summary_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_generate(_: fn(String, AiSummaryGenerationRequest) -> CoreResult<AiSummaryDraft>) {}
    fn assert_save(_: fn(String, AiSummarySaveRequest) -> CoreResult<AiSummarySaveReport>) {}
    fn assert_clear(_: fn(String, AiSummaryClearRequest) -> CoreResult<AiSummaryClearReport>) {}

    assert_generate(generate_ai_summary);
    assert_save(save_ai_summary);
    assert_clear(clear_ai_summary);

    let draft = AiSummaryDraft {
        file_id: 42,
        draft_id: Some("draft:summary:42".to_owned()),
        status: AiSummaryDraftStatus::Draft,
        summary_text: Some("Short generated summary.".to_owned()),
        route: Some(AiSummaryRoute::Remote),
        model_name: Some("Remote provider".to_owned()),
        generated_at: Some(1_777_300_800),
        used_context: vec![
            AiSummaryInputField::FileName,
            AiSummaryInputField::ExtractedTextExcerpt,
        ],
        skipped_reason: None,
        privacy_rule_id: None,
        call_log_id: Some(8),
        requires_user_save: true,
        character_count: 24,
    };
    assert_eq!(draft.status, AiSummaryDraftStatus::Draft);
    assert!(draft.requires_user_save);
    assert_eq!(draft.route, Some(AiSummaryRoute::Remote));

    let skipped = AiSummaryDraft {
        file_id: 42,
        draft_id: None,
        status: AiSummaryDraftStatus::Skipped,
        summary_text: None,
        route: None,
        model_name: None,
        generated_at: None,
        used_context: Vec::new(),
        skipped_reason: Some(AiSummarySkipReason::PrivacyRule),
        privacy_rule_id: Some("rule:private-folder".to_owned()),
        call_log_id: Some(9),
        requires_user_save: true,
        character_count: 0,
    };
    assert_eq!(
        skipped.skipped_reason,
        Some(AiSummarySkipReason::PrivacyRule)
    );

    let saved = AiSummarySaveReport {
        file_id: 42,
        saved_summary: "Edited summary.".to_owned(),
        saved_at: 1_777_300_900,
        route: Some(AiSummaryRoute::Local),
        model_name: Some("Local summary model v1".to_owned()),
        generated_at: Some(1_777_300_800),
        used_context: vec![AiSummaryInputField::NoteSummary],
        privacy_rule_id: None,
        call_log_id: Some(8),
        edited_by_user: true,
        character_count: 15,
    };
    assert!(saved.edited_by_user);
    assert_eq!(saved.character_count, 15);

    let cleared = AiSummaryClearReport {
        file_id: 42,
        cleared: true,
        cleared_at: 1_777_301_000,
    };
    assert!(cleared.cleared);

    let documented_errors = [
        CoreError::config("invalid AI summary request"),
        CoreError::file_not_found("missing file id"),
        CoreError::permission_denied("summary metadata unavailable"),
        CoreError::db("AI summary persistence failed"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn ai_summary_contract_rejects_invalid_inputs_without_fake_success() {
    assert!(matches!(
        generate_ai_summary(String::new(), generation_request()),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_file = generation_request();
    invalid_file.file_id = 0;
    assert!(matches!(
        generate_ai_summary("/tmp/repo".to_owned(), invalid_file),
        Err(CoreError::Config { .. })
    ));

    let mut raw_secret = generation_request();
    raw_secret.privacy_policy_ref = Some("sk-secret-key-material".to_owned());
    assert!(matches!(
        generate_ai_summary("/tmp/repo".to_owned(), raw_secret),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        generate_ai_summary("/tmp/repo".to_owned(), generation_request()),
        Err(CoreError::Db { .. })
    ));

    let mut empty_summary = save_request();
    empty_summary.summary_text = " ".to_owned();
    assert!(matches!(
        save_ai_summary("/tmp/repo".to_owned(), empty_summary),
        Err(CoreError::Config { .. })
    ));

    let mut duplicate_context = save_request();
    duplicate_context
        .used_context
        .push(AiSummaryInputField::FileName);
    assert!(matches!(
        save_ai_summary("/tmp/repo".to_owned(), duplicate_context),
        Err(CoreError::Config { .. })
    ));

    let mut raw_draft_id = save_request();
    raw_draft_id.draft_id = Some("bearer-token".to_owned());
    assert!(matches!(
        save_ai_summary("/tmp/repo".to_owned(), raw_draft_id),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        save_ai_summary("/tmp/repo".to_owned(), save_request()),
        Err(CoreError::Db { .. })
    ));

    let mut missing_confirmation = clear_request();
    missing_confirmation.confirmed = false;
    assert!(matches!(
        clear_ai_summary("/tmp/repo".to_owned(), missing_confirmation),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        clear_ai_summary("/tmp/repo".to_owned(), clear_request()),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn ai_summary_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-2/task-26: C3-06 contract-api",
        "为 C3-06 ai-summary 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C3-06 ai-summary",
        "- S3-06 ai-summary-editor",
        "计划新增：`generate_ai_summary`、`save_ai_summary`、`clear_ai_summary`",
        "file_id、summary draft、provider scope。",
        "摘要草稿或保存结果。",
        "保存摘要 metadata。",
        "写 AI call log 和 change log。",
        "可写伴生 summary metadata；不得覆盖用户原文件。",
        "- `Config`",
        "- `FileNotFound`",
        "- `PermissionDenied`",
        "- `Db`",
        "生成结果默认是草稿，用户保存后才持久化。",
        "Clear 只清摘要，不删文件和笔记。",
        "远程摘要必须受隐私规则控制。",
        "多文档摘要和知识库摘要属于后续阶段。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-06 | ai-summary-editor | C3-06, C3-09 | generate/save/clear summary | summary metadata, ai_call_log |",
        "AI 默认关闭，本地优先。",
        "远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。",
        "AI 结果在用户确认前都是草稿，不直接写分类、标签、摘要。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "AiSummaryDraft generate_ai_summary(",
        "string repo_path, AiSummaryGenerationRequest request",
        "AiSummarySaveReport save_ai_summary(",
        "string repo_path, AiSummarySaveRequest request",
        "AiSummaryClearReport clear_ai_summary(",
        "string repo_path, AiSummaryClearRequest request",
        "dictionary AiSummaryGenerationRequest",
        "AiSummaryProviderScope provider_scope;",
        "AiSummaryContextPolicy context_policy;",
        "dictionary AiSummaryDraft",
        "AiSummaryDraftStatus status;",
        "string? summary_text;",
        "AiSummaryRoute? route;",
        "sequence<AiSummaryInputField> used_context;",
        "AiSummarySkipReason? skipped_reason;",
        "boolean requires_user_save;",
        "dictionary AiSummarySaveRequest",
        "string summary_text;",
        "boolean edited_by_user;",
        "dictionary AiSummarySaveReport",
        "string saved_summary;",
        "dictionary AiSummaryClearRequest",
        "boolean confirmed;",
        "dictionary AiSummaryClearReport",
        "boolean cleared;",
        "enum AiSummaryProviderScope",
        "\"RemoteAllowed\"",
        "enum AiSummaryContextPolicy",
        "\"MetadataTextAndNotes\"",
        "enum AiSummaryInputField",
        "\"ExistingAiSummary\"",
        "enum AiSummaryDraftStatus",
        "\"Skipped\"",
        "enum AiSummarySkipReason",
        "\"CallLogUnavailable\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `generate_ai_summary(repo, request)` | ai | √ | Config / FileNotFound / PermissionDenied / Db |",
        "| `save_ai_summary(repo, request)` | ai | √ | Config / FileNotFound / PermissionDenied / Db |",
        "| `clear_ai_summary(repo, request)` | ai | √ | Config / FileNotFound / PermissionDenied / Db |",
        "### `generate_ai_summary(repoPath: String, request: AiSummaryGenerationRequest) throws -> AiSummaryDraft`",
        "### `save_ai_summary(repoPath: String, request: AiSummarySaveRequest) throws -> AiSummarySaveReport`",
        "### `clear_ai_summary(repoPath: String, request: AiSummaryClearRequest) throws -> AiSummaryClearReport`",
        "用户点击 Save 前不得持久化",
        "不得覆盖用户 Note",
        "不得写入或修改用户原文件",
        "远程路线必须同时通过 C3-01 AI settings、C3-03 remote provider gate、C3-09 privacy gate",
        "S3-06 可以从合同得到 Draft、Generated locally/remotely",
        "S3-10 可以从 `status`、`skipped_reason`、`route` 和 `call_log_id`",
        "本合同不新增 control map 之外的页面能力",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Config", "FileNotFound", "PermissionDenied", "Db"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}

#[test]
fn ai_summary_contract_documents_consumers_and_boundaries() {
    for fragment in [
        "生成结果默认先进入草稿态，用户点击 `Save` 前不写入正式摘要",
        "不得覆盖用户 Note，也不得写入用户原文件。",
        "显示当前 AI 摘要。",
        "显示摘要来源：本地/远程、生成时间、模型。",
        "支持重新生成。",
        "支持清除摘要。",
        "显示隐私规则跳过状态。",
        "`Skipped by privacy rule`",
        "`View AI call`",
        "`View privacy rule`",
        "生成摘要前必须校验 AI 总开关、`Auto summaries` 功能开关、provider 状态、远程显式启用、usage scope、隐私规则和调用日志写入能力。",
        "清除摘要只删除 AI 派生摘要，不删除 Note、原文件、提取文本、标签或调用日志。",
        "保存失败时草稿不丢失；清除失败时原已保存摘要不丢失。",
        "远程摘要显示远程标记并可追溯到调用日志。",
    ] {
        assert_contains(AI_SUMMARY_PAGE, fragment);
    }

    for fragment in [
        "AI 摘要宿主：显示 `Edit summary manually`",
        "AI 失败不改变文件、分类、标签或摘要。",
        "摘要进入手动编辑",
    ] {
        assert_contains(FALLBACK_PAGE, fragment);
    }

    for fragment in [
        "C3-06 AI summary contract types and entry points",
        "pub enum AiSummaryProviderScope",
        "pub enum AiSummaryContextPolicy",
        "pub enum AiSummaryInputField",
        "pub enum AiSummaryRoute",
        "pub enum AiSummaryDraftStatus",
        "pub enum AiSummarySkipReason",
        "pub struct AiSummaryGenerationRequest",
        "pub struct AiSummaryDraft",
        "pub struct AiSummarySaveRequest",
        "pub struct AiSummarySaveReport",
        "pub struct AiSummaryClearRequest",
        "pub struct AiSummaryClearReport",
        "pub(crate) fn generate_ai_summary(",
        "pub(crate) fn save_ai_summary(",
        "pub(crate) fn clear_ai_summary(",
        "looks_sensitive",
        "AI summary privacy policy reference is invalid",
    ] {
        assert_contains(AI_SUMMARY_RS, fragment);
    }

    for fragment in [
        "Generates a C3-06 AI summary draft without saving it.",
        "S3-06 uses this contract for `Generate summary`",
        "Saves a C3-06 AI summary draft as AreaMatrix-owned metadata.",
        "Clears C3-06 AI summary metadata for one file after confirmation.",
        "must not persist a summary",
        "must not overwrite the original file",
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
            !AI_SUMMARY_RS.contains(forbidden),
            "C3-06 contract must not implement adjacent capability `{forbidden}`"
        );
    }
}
