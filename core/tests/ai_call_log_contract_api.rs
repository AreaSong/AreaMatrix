use area_matrix_core::{
    clear_ai_call_log, list_ai_calls, AiCallLogClearReport, AiCallLogClearRequest,
    AiCallLogClearScope, AiCallLogFeature, AiCallLogFilter, AiCallLogPage, AiCallLogPagination,
    AiCallLogRecord, AiCallLogRoute, AiCallLogSentField, AiCallLogStatus, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-21-c3-05-contract-api.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-05-ai-call-log.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const AI_CALL_LOG_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-05-ai-call-log.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const DATA_MODEL: &str = include_str!("../../docs/architecture/data-model.md");
const API_RS: &str = include_str!("../src/api.rs");
const AI_CALL_LOG_RS: &str = include_str!("../src/ai_call_log.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn filter() -> AiCallLogFilter {
    AiCallLogFilter {
        feature: Some(AiCallLogFeature::Classification),
        route: Some(AiCallLogRoute::Remote),
        status: Some(AiCallLogStatus::Skipped),
        occurred_after: Some(1_777_000_000),
        occurred_before: Some(1_777_400_000),
        search_query: Some("ProviderUnavailable".to_owned()),
    }
}

fn pagination() -> AiCallLogPagination {
    AiCallLogPagination {
        limit: 50,
        offset: 0,
    }
}

fn clear_all_request() -> AiCallLogClearRequest {
    AiCallLogClearRequest {
        scope: AiCallLogClearScope::All,
        entry_ids: Vec::new(),
        older_than: None,
    }
}

#[test]
fn ai_call_log_contract_exposes_signature_input_output_and_errors() {
    fn assert_list(
        _: fn(String, AiCallLogFilter, AiCallLogPagination) -> CoreResult<AiCallLogPage>,
    ) {
    }
    fn assert_clear(_: fn(String, AiCallLogClearRequest) -> CoreResult<AiCallLogClearReport>) {}

    assert_list(list_ai_calls);
    assert_clear(clear_ai_call_log);

    let record = AiCallLogRecord {
        id: 7,
        occurred_at: 1_777_300_800,
        feature: AiCallLogFeature::ProviderTest,
        file_id: None,
        file_display_name: None,
        batch_id: None,
        scope: Some("Provider verification".to_owned()),
        route: Some(AiCallLogRoute::Remote),
        provider_name: Some("Remote provider".to_owned()),
        model_name: Some("gpt-4.1-mini".to_owned()),
        status: AiCallLogStatus::Failed,
        duration_ms: Some(1200),
        sent_fields: Vec::new(),
        privacy_rules_checked: false,
        privacy_rule_id: None,
        privacy_rule_name: None,
        matched_field_type: None,
        result_summary: "Connection failed".to_owned(),
        error_code: Some("ProviderUnavailable".to_owned()),
    };
    assert_eq!(record.feature, AiCallLogFeature::ProviderTest);
    assert_eq!(record.status, AiCallLogStatus::Failed);
    assert!(record.sent_fields.is_empty());

    let skipped = AiCallLogRecord {
        id: 8,
        occurred_at: 1_777_300_900,
        feature: AiCallLogFeature::Classification,
        file_id: Some(42),
        file_display_name: Some("invoice.pdf".to_owned()),
        batch_id: None,
        scope: Some("Classification".to_owned()),
        route: None,
        provider_name: None,
        model_name: None,
        status: AiCallLogStatus::Skipped,
        duration_ms: None,
        sent_fields: Vec::new(),
        privacy_rules_checked: true,
        privacy_rule_id: Some("rule:private-folder".to_owned()),
        privacy_rule_name: Some("Private folder".to_owned()),
        matched_field_type: Some(AiCallLogSentField::NoteSummary),
        result_summary: "No AI call was made".to_owned(),
        error_code: None,
    };
    assert_eq!(skipped.status, AiCallLogStatus::Skipped);
    assert_eq!(
        skipped.matched_field_type,
        Some(AiCallLogSentField::NoteSummary)
    );

    let page = AiCallLogPage {
        total_count: 2,
        records: vec![record, skipped],
        limit: 50,
        offset: 0,
        has_more: false,
        retention_days: 90,
        redaction_policy: "No API keys, full prompts, outputs, notes, or file contents".to_owned(),
    };
    assert_eq!(page.records.len(), 2);
    assert_eq!(page.retention_days, 90);

    let report = AiCallLogClearReport {
        deleted_count: 2,
        remaining_count: 0,
        cleared_at: 1_777_300_901,
    };
    assert_eq!(report.remaining_count, 0);

    let documented_errors = [
        CoreError::db("AI call log query failed"),
        CoreError::permission_denied("AI call log metadata unavailable"),
    ];
    assert_eq!(documented_errors.len(), 2);
}

#[test]
fn ai_call_log_contract_rejects_invalid_inputs_without_fake_success() {
    assert!(matches!(
        list_ai_calls(String::new(), filter(), pagination()),
        Err(CoreError::Db { .. })
    ));

    let mut invalid_range = filter();
    invalid_range.occurred_after = Some(20);
    invalid_range.occurred_before = Some(10);
    assert!(matches!(
        list_ai_calls("/tmp/repo".to_owned(), invalid_range, pagination()),
        Err(CoreError::Db { .. })
    ));

    let mut invalid_query = filter();
    invalid_query.search_query = Some("bad\0query".to_owned());
    assert!(matches!(
        list_ai_calls("/tmp/repo".to_owned(), invalid_query, pagination()),
        Err(CoreError::Db { .. })
    ));

    let invalid_page = AiCallLogPagination {
        limit: 0,
        offset: 0,
    };
    assert!(matches!(
        list_ai_calls("/tmp/repo".to_owned(), filter(), invalid_page),
        Err(CoreError::Db { .. })
    ));

    let mut selected_without_ids = clear_all_request();
    selected_without_ids.scope = AiCallLogClearScope::SelectedEntries;
    assert!(matches!(
        clear_ai_call_log("/tmp/repo".to_owned(), selected_without_ids),
        Err(CoreError::Db { .. })
    ));

    let mut invalid_selected = clear_all_request();
    invalid_selected.scope = AiCallLogClearScope::SelectedEntries;
    invalid_selected.entry_ids = vec![1, 0];
    assert!(matches!(
        clear_ai_call_log("/tmp/repo".to_owned(), invalid_selected),
        Err(CoreError::Db { .. })
    ));

    let mut invalid_older_than = clear_all_request();
    invalid_older_than.scope = AiCallLogClearScope::OlderThan;
    invalid_older_than.older_than = Some(-1);
    assert!(matches!(
        clear_ai_call_log("/tmp/repo".to_owned(), invalid_older_than),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn ai_call_log_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-2/task-21: C3-05 contract-api",
        "为 C3-05 ai-call-log 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C3-05 ai-call-log",
        "- S3-05 ai-call-log",
        "计划新增：`list_ai_calls`、`clear_ai_call_log`",
        "filter、pagination、clear scope。",
        "AI 调用记录，不包含密钥和完整文件内容。",
        "读写 `ai_call_log` 或等价审计表。",
        "- `Db`",
        "- `PermissionDenied`",
        "本地/远程调用可区分。",
        "可清除日志，但不影响用户文件。",
        "日志不包含 API key 或未脱敏隐私内容。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-05 | ai-call-log | C3-05 | list/clear AI log | ai_call_log |",
        "远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "AiCallLogPage list_ai_calls(",
        "string repo_path, AiCallLogFilter filter, AiCallLogPagination pagination",
        "AiCallLogClearReport clear_ai_call_log(",
        "string repo_path, AiCallLogClearRequest request",
        "dictionary AiCallLogFilter",
        "AiCallLogFeature? feature;",
        "AiCallLogRoute? route;",
        "AiCallLogStatus? status;",
        "dictionary AiCallLogRecord",
        "AiCallLogFeature feature;",
        "string? scope;",
        "AiCallLogRoute? route;",
        "sequence<AiCallLogSentField> sent_fields;",
        "boolean privacy_rules_checked;",
        "string? privacy_rule_id;",
        "AiCallLogSentField? matched_field_type;",
        "dictionary AiCallLogPage",
        "i64 retention_days;",
        "string redaction_policy;",
        "dictionary AiCallLogClearRequest",
        "AiCallLogClearScope scope;",
        "dictionary AiCallLogClearReport",
        "i64 deleted_count;",
        "enum AiCallLogFeature",
        "\"ProviderTest\"",
        "enum AiCallLogStatus",
        "\"Skipped\"",
        "enum AiCallLogSentField",
        "\"NoteSummary\"",
        "enum AiCallLogClearScope",
        "\"SelectedEntries\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `list_ai_calls(repo, filter, pagination)` | ai | √ | Db / PermissionDenied |",
        "| `clear_ai_call_log(repo, request)` | ai | √ | Db / PermissionDenied |",
        "### `list_ai_calls(repoPath: String, filter: AiCallLogFilter, pagination: AiCallLogPagination) throws -> AiCallLogPage`",
        "C3-05 的 AI 调用日志读取入口",
        "`S3-05 ai-call-log`",
        "不返回 API key、key 片段、Keychain 引用值",
        "完整文件正文、完整 prompt、完整模型输出",
        "隐私规则命中记录必须能表达 `Skipped`、sent fields none",
        "### `clear_ai_call_log(repoPath: String, request: AiCallLogClearRequest) throws -> AiCallLogClearReport`",
        "只删除 `ai_call_log` 或等价审计表中的本地日志行。",
        "不删除、移动、重命名、Trash、覆盖或重新分类用户文件。",
        "本合同不实现 redacted export、保存面板、Reveal file",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Db", "PermissionDenied"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in [
        "CREATE TABLE IF NOT EXISTS ai_call_log",
        "idx_ai_call_log_time",
        "idx_ai_call_log_feature_time",
        "files ||--o{ ai_call_log",
    ] {
        assert_contains(DATA_MODEL, fragment);
    }
}

#[test]
fn ai_call_log_contract_documents_consumers_and_privacy_boundaries() {
    for fragment in [
        "用户能看到 AI 调用时间、功能、provider、状态和是否远程。",
        "远程调用和隐私跳过记录可区分。",
        "Provider Test` feature 展示",
        "sent fields 为 `none`",
        "Provider Test 记录和导出日志不包含 API key、key 片段、用户文件名、路径、摘要、提取文本、标签、Note、prompt 或 provider 原始响应体。",
        "详情只显示发送字段类型，不默认展示敏感全文。",
        "清除日志需要确认，且不影响文件、AI 结果、标签、摘要、Note、AI 设置或 API key。",
        "删除选中日志需要确认，且不影响文件、AI 结果、标签、摘要、Note 或设置。",
        "默认保留策略显示为 90 天，可手动清除。",
    ] {
        assert_contains(AI_CALL_LOG_PAGE, fragment);
    }

    for fragment in [
        "pub enum AiCallLogFeature",
        "pub enum AiCallLogRoute",
        "pub enum AiCallLogStatus",
        "pub enum AiCallLogSentField",
        "pub enum AiCallLogClearScope",
        "pub struct AiCallLogFilter",
        "pub struct AiCallLogPagination",
        "pub struct AiCallLogRecord",
        "pub struct AiCallLogPage",
        "pub struct AiCallLogClearRequest",
        "pub struct AiCallLogClearReport",
        "pub(crate) fn list_ai_calls(",
        "pub(crate) fn clear_ai_call_log(",
        "db::list_ai_call_log_rows",
        "db::clear_ai_call_log_rows",
    ] {
        assert_contains(AI_CALL_LOG_RS, fragment);
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
            !AI_CALL_LOG_RS.contains(forbidden),
            "C3-05 contract must not implement adjacent capability `{forbidden}`"
        );
    }
}
