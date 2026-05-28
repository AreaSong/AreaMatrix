#[path = "support/ai_call_log_validation.rs"]
mod validation_support;

use std::fs;

use area_matrix_core::{
    clear_ai_call_log, list_ai_calls, AiCallLogClearReport, AiCallLogClearRequest,
    AiCallLogClearScope, AiCallLogFeature, AiCallLogFilter, AiCallLogPage, AiCallLogPagination,
    AiCallLogRoute, AiCallLogSentField, AiCallLogStatus, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;
use validation_support::{
    assert_contains, assert_secret_free, clear_all_request, connection, default_filter,
    initialized_repo, insert_file_fixture, page, path_string, seed_ai_call_logs, snapshot,
};

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-24-c3-05-validation.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-05-ai-call-log.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const AI_CALL_LOG_RS: &str = include_str!("../src/ai_call_log.rs");
const DB_AI_CALL_LOG_RS: &str = include_str!("../src/db/ai_call_log.rs");
const DB_AI_CALL_LOG_SCHEMA_RS: &str = include_str!("../src/db/ai_call_log/schema.rs");

#[test]
fn ai_call_log_validation_lists_redacted_filtered_pages_for_ui_ready_state() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let file_id = insert_file_fixture(repo.path());
    let (success_id, remote_id, skipped_id) = seed_ai_call_logs(repo.path(), file_id);

    let all = list_ai_calls(path_string(repo.path()), default_filter(), page(2, 0))
        .expect("list redacted AI logs");

    assert_eq!(all.total_count, 3);
    assert_eq!(all.records.len(), 2);
    assert_eq!(all.records[0].id, skipped_id);
    assert_eq!(all.records[1].id, remote_id);
    assert!(all.has_more);
    assert_eq!(all.retention_days, 90);
    assert!(all.redaction_policy.contains("No API keys"));
    assert_eq!(all.records[0].status, AiCallLogStatus::Skipped);
    assert_eq!(all.records[0].route, None);
    assert_eq!(
        all.records[0].matched_field_type,
        Some(AiCallLogSentField::NoteSummary)
    );
    assert_eq!(all.records[1].feature, AiCallLogFeature::ProviderTest);
    assert_eq!(all.records[1].route, Some(AiCallLogRoute::Remote));
    assert!(all.records[1].sent_fields.is_empty());
    for value in [
        all.records[1].provider_name.as_deref(),
        all.records[1].model_name.as_deref(),
        Some(all.records[1].result_summary.as_str()),
        all.records[1].error_code.as_deref(),
    ]
    .into_iter()
    .flatten()
    {
        assert_secret_free(value);
    }

    let filtered = list_ai_calls(
        path_string(repo.path()),
        AiCallLogFilter {
            feature: Some(AiCallLogFeature::Classification),
            route: Some(AiCallLogRoute::Local),
            status: Some(AiCallLogStatus::Success),
            occurred_after: Some(1_799_999_999),
            occurred_before: Some(1_800_000_050),
            search_query: Some("invoice".to_owned()),
        },
        page(50, 0),
    )
    .expect("filter classification success log");
    let record = filtered.records.first().expect("filtered record");
    assert_eq!(filtered.total_count, 1);
    assert_eq!(record.id, success_id);
    assert_eq!(record.file_id, Some(file_id));
    assert_eq!(
        record.file_display_name.as_deref(),
        Some("invoice-2026.pdf")
    );
    assert_eq!(record.scope.as_deref(), Some("Classification"));
    assert_eq!(record.status, AiCallLogStatus::Success);
    assert_eq!(
        record.sent_fields,
        vec![
            AiCallLogSentField::FileName,
            AiCallLogSentField::RepoRelativePath,
            AiCallLogSentField::Extension,
        ]
    );
}

#[test]
fn ai_call_log_validation_clears_scopes_without_touching_user_files_or_metadata() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let file_id = insert_file_fixture(repo.path());
    let (success_id, old_remote_id, new_skipped_id) = seed_ai_call_logs(repo.path(), file_id);
    let before = snapshot(repo.path());

    let selected = clear_ai_call_log(
        path_string(repo.path()),
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::SelectedEntries,
            entry_ids: vec![success_id],
            older_than: None,
        },
    )
    .expect("clear selected AI log");
    assert_eq!(selected.deleted_count, 1);
    assert_eq!(selected.remaining_count, 2);

    let older_than = clear_ai_call_log(
        path_string(repo.path()),
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::OlderThan,
            entry_ids: Vec::new(),
            older_than: Some(1_800_000_150),
        },
    )
    .expect("clear older AI logs");
    assert_eq!(older_than.deleted_count, 1);
    assert_eq!(older_than.remaining_count, 1);

    let remaining = list_ai_calls(path_string(repo.path()), default_filter(), page(50, 0))
        .expect("list remaining AI logs");
    assert_eq!(remaining.records.len(), 1);
    assert_eq!(remaining.records[0].id, new_skipped_id);
    assert_ne!(remaining.records[0].id, old_remote_id);

    let all = clear_ai_call_log(path_string(repo.path()), clear_all_request())
        .expect("clear all remaining AI logs");
    assert_eq!(all.deleted_count, 1);
    assert_eq!(all.remaining_count, 0);

    let after = snapshot(repo.path());
    assert_eq!(after.user_readme, before.user_readme);
    assert_eq!(after.user_visible_paths, before.user_visible_paths);
    assert_eq!(after.files, before.files);
    assert_eq!(after.ai_call_log_count, 0);
}

#[test]
fn ai_call_log_validation_covers_failure_paths_rollback_and_error_codes() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let file_id = insert_file_fixture(repo.path());
    seed_ai_call_logs(repo.path(), file_id);
    let before = snapshot(repo.path());

    let invalid_list_inputs = [
        (
            repo.path()
                .join(".areamatrix")
                .to_string_lossy()
                .into_owned(),
            default_filter(),
            page(50, 0),
        ),
        (
            path_string(repo.path()),
            AiCallLogFilter {
                search_query: Some(" bad ".to_owned()),
                ..default_filter()
            },
            page(50, 0),
        ),
        (
            path_string(repo.path()),
            default_filter(),
            AiCallLogPagination {
                limit: 0,
                offset: 0,
            },
        ),
    ];
    for (repo_path, filter, pagination) in invalid_list_inputs {
        let error =
            list_ai_calls(repo_path, filter, pagination).expect_err("invalid list input must fail");
        assert!(matches!(error, CoreError::Db { .. }));
    }

    for request in [
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::All,
            entry_ids: vec![1],
            older_than: None,
        },
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::SelectedEntries,
            entry_ids: Vec::new(),
            older_than: None,
        },
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::OlderThan,
            entry_ids: Vec::new(),
            older_than: Some(-1),
        },
    ] {
        let error = clear_ai_call_log(path_string(repo.path()), request)
            .expect_err("invalid clear input must fail");
        assert!(matches!(error, CoreError::Db { .. }));
    }
    assert_eq!(snapshot(repo.path()), before);

    connection(repo.path())
        .execute_batch(
            "CREATE TRIGGER ai_call_log_validation_abort_delete
             BEFORE DELETE ON ai_call_log
             BEGIN
               SELECT RAISE(ABORT, 'forced validation delete failure');
             END;",
        )
        .expect("install delete failure trigger");
    let error = clear_ai_call_log(path_string(repo.path()), clear_all_request())
        .expect_err("forced delete failure must abort clear");
    assert!(
        matches!(error, CoreError::Db { message } if message.contains("forced validation delete failure"))
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn ai_call_log_validation_locks_core_api_udl_rust_and_docs_alignment() {
    fn assert_list(
        _: fn(String, AiCallLogFilter, AiCallLogPagination) -> CoreResult<AiCallLogPage>,
    ) {
    }
    fn assert_clear(_: fn(String, AiCallLogClearRequest) -> CoreResult<AiCallLogClearReport>) {}
    assert_list(list_ai_calls);
    assert_clear(clear_ai_call_log);

    for fragment in [
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
    ] {
        assert_contains(TASK, fragment);
    }
    for fragment in [
        "# C3-05 ai-call-log",
        "计划新增：`list_ai_calls`、`clear_ai_call_log`",
        "AI 调用记录，不包含密钥和完整文件内容。",
        "读写 `ai_call_log` 或等价审计表。",
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
        "`core/tests/`，每个文件独立编译",
        "## 关键测试场景",
        "`core/tests/` 下，全场景从 init_repo",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }
    for fragment in [
        "AiCallLogPage list_ai_calls(",
        "AiCallLogClearReport clear_ai_call_log(",
        "dictionary AiCallLogFilter",
        "dictionary AiCallLogRecord",
        "sequence<AiCallLogSentField> sent_fields;",
        "dictionary AiCallLogClearRequest",
        "enum AiCallLogFeature",
        "\"ProviderTest\"",
        "enum AiCallLogStatus",
        "\"Skipped\"",
        "enum AiCallLogClearScope",
        "\"OlderThan\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
    for fragment in [
        "pub fn list_ai_calls(",
        "pub fn clear_ai_call_log(",
        "must not execute AI calls, clear logs, export files",
        "must not delete, move, rename, trash, overwrite, or reclassify user",
        "Returns `CoreError::Db { message }`",
        "Returns `CoreError::PermissionDenied",
    ] {
        assert_contains(API_RS, fragment);
    }
    for fragment in [
        "pub use ai_call_log::{",
        "AiCallLogFilter",
        "AiCallLogPage",
        "AiCallLogClearRequest",
        "AiCallLogClearReport",
    ] {
        assert_contains(LIB_RS, fragment);
    }
    for fragment in [
        "pub(crate) fn list_ai_calls(",
        "pub(crate) fn clear_ai_call_log(",
        "validate_filter",
        "validate_pagination",
        "validate_clear_request",
        "db::list_ai_call_log_rows",
        "db::clear_ai_call_log_rows",
        "sanitize_text",
        "redact_sensitive_token",
    ] {
        assert_contains(AI_CALL_LOG_RS, fragment);
    }
    for fragment in [
        "pub(crate) fn list_ai_call_log_rows(",
        "pub(crate) fn clear_ai_call_log_rows(",
        "LEFT JOIN files ON files.id = log.file_id",
        "DELETE FROM ai_call_log",
        "tx.commit()",
    ] {
        assert_contains(DB_AI_CALL_LOG_RS, fragment);
    }
    for fragment in [
        "CREATE TABLE IF NOT EXISTS ai_call_log",
        "privacy_rules_checked INTEGER NOT NULL DEFAULT 0",
        "idx_ai_call_log_time",
        "idx_ai_call_log_feature_time",
    ] {
        assert_contains(DB_AI_CALL_LOG_SCHEMA_RS, fragment);
    }
}
