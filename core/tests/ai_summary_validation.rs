#[path = "support/ai_summary_common.rs"]
mod common;

use std::{fs, path::Path};

use area_matrix_core::{
    clear_ai_summary, generate_ai_summary, read_note, save_ai_summary, write_note,
    AiSummaryClearRequest, AiSummaryContextPolicy, AiSummaryDraftStatus,
    AiSummaryGenerationRequest, AiSummaryInputField, AiSummaryProviderScope, AiSummaryRoute,
    AiSummarySaveRequest, AiSummarySkipReason, CoreError, CoreResult,
};
use common::{
    ai_summary_row, change_log_kinds, enable_local_summaries, enable_remote_summaries,
    import_fixture, initialized_repo, path_string, AiSummaryRuntime, RemoteRuntimeProbe,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-29-c3-06-validation.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-06-ai-summary.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const AI_SUMMARY_RS: &str = include_str!("../src/ai_summary.rs");
const AI_SUMMARY_IMPL_RS: &str = include_str!("../src/ai_summary/implementation.rs");
const DB_AI_SUMMARY_RS: &str = include_str!("../src/db/ai_summary.rs");

#[derive(Debug, Eq, PartialEq)]
struct SummarySafetySnapshot {
    user_readme: String,
    user_note: Option<String>,
    stored_file_body: String,
    ai_call_log_rows: i64,
}

#[derive(Debug)]
struct SummaryLogRow {
    status: String,
    route: Option<String>,
    sent_fields_json: String,
    privacy_rule_id: Option<String>,
    result_summary: String,
    error_code: Option<String>,
}

fn generation_request(file_id: i64) -> AiSummaryGenerationRequest {
    AiSummaryGenerationRequest {
        file_id,
        provider_scope: AiSummaryProviderScope::LocalPreferred,
        context_policy: AiSummaryContextPolicy::MetadataTextAndNotes,
        privacy_policy_ref: None,
        regenerate_existing: false,
    }
}

fn save_request(
    file_id: i64,
    summary_text: String,
    draft_id: Option<String>,
    call_log_id: Option<i64>,
) -> AiSummarySaveRequest {
    AiSummarySaveRequest {
        file_id,
        summary_text,
        draft_id,
        route: Some(AiSummaryRoute::Local),
        model_name: Some("areamatrix-local-summary".to_owned()),
        generated_at: Some(1_800_000_000),
        used_context: vec![
            AiSummaryInputField::FileName,
            AiSummaryInputField::RepoRelativePath,
            AiSummaryInputField::ExtractedTextExcerpt,
            AiSummaryInputField::NoteSummary,
            AiSummaryInputField::TagCategoryContext,
        ],
        privacy_rule_id: None,
        call_log_id,
        edited_by_user: true,
    }
}

fn snapshot(repo: &Path, file_id: i64) -> SummarySafetySnapshot {
    SummarySafetySnapshot {
        user_readme: fs::read_to_string(repo.join("README.md")).expect("read user README"),
        user_note: read_note(path_string(repo), file_id).expect("read user note"),
        stored_file_body: fs::read_to_string(repo.join(active_file_path(repo, file_id)))
            .expect("read stored file body"),
        ai_call_log_rows: table_count(repo, "ai_call_log"),
    }
}

fn active_file_path(repo: &Path, file_id: i64) -> String {
    open_db(repo)
        .query_row(
            "SELECT path FROM files WHERE id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .expect("read active file path")
}

fn table_count(repo: &Path, table: &str) -> i64 {
    let connection = open_db(repo);
    let exists = connection
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            params![table],
            |_| Ok(true),
        )
        .unwrap_or(false);
    if !exists {
        return 0;
    }
    connection
        .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
            row.get(0)
        })
        .expect("count table rows")
}

fn summary_log_row(repo: &Path, id: i64) -> SummaryLogRow {
    open_db(repo)
        .query_row(
            "SELECT status, route, sent_fields_json, privacy_rule_id, result_summary, error_code
             FROM ai_call_log WHERE id = ?1",
            params![id],
            |row| {
                Ok(SummaryLogRow {
                    status: row.get(0)?,
                    route: row.get(1)?,
                    sent_fields_json: row.get(2)?,
                    privacy_rule_id: row.get(3)?,
                    result_summary: row.get(4)?,
                    error_code: row.get(5)?,
                })
            },
        )
        .expect("read AI summary call log row")
}

fn secret_log_rows(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM ai_call_log
             WHERE result_summary LIKE '%summary-provider-secret%'
                OR result_summary LIKE '%sk-secret%'
                OR privacy_rule_id LIKE '%summary-provider-secret%'
                OR sent_fields_json LIKE '%original file body%'",
            [],
            |row| row.get(0),
        )
        .expect("query secret leakage rows")
}

fn install_broken_ai_call_log_schema(repo: &Path) {
    open_db(repo)
        .execute_batch("CREATE TABLE ai_call_log (id INTEGER PRIMARY KEY);")
        .expect("install broken AI call log schema");
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

#[test]
fn ai_summary_validation_proves_draft_save_clear_path_is_ui_ready() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let file_id = import_fixture(
        repo.path(),
        "summary-source.txt",
        "original file body with useful summary context",
    );
    write_note(
        repo_path.clone(),
        file_id,
        "user note must survive clear".to_owned(),
    )
    .expect("write user note");
    enable_local_summaries(repo.path());
    let before = snapshot(repo.path(), file_id);
    let runtime = AiSummaryRuntime::local("Draft summary from local validation runtime.");

    let draft = generate_ai_summary(repo_path.clone(), generation_request(file_id))
        .expect("generate draft");
    let payload = runtime.captured_payload();

    assert_eq!(draft.status, AiSummaryDraftStatus::Draft);
    assert_eq!(
        draft.summary_text.as_deref(),
        Some("Draft summary from local validation runtime.")
    );
    assert_eq!(draft.route, Some(AiSummaryRoute::Local));
    assert!(draft.requires_user_save);
    assert!(draft.call_log_id.is_some());
    assert!(draft.used_context.contains(&AiSummaryInputField::FileName));
    assert!(draft
        .used_context
        .contains(&AiSummaryInputField::NoteSummary));
    assert!(payload.contains("\"feature\":\"summary\""));
    assert!(payload.contains("user note must survive clear"));
    assert!(ai_summary_row(repo.path(), file_id).is_none());

    let saved = save_ai_summary(
        repo_path.clone(),
        save_request(
            file_id,
            "Edited validation summary.".to_owned(),
            draft.draft_id,
            draft.call_log_id,
        ),
    )
    .expect("save summary");

    assert_eq!(saved.saved_summary, "Edited validation summary.");
    assert_eq!(
        ai_summary_row(repo.path(), file_id).as_deref(),
        Some("Edited validation summary.")
    );
    assert!(change_log_kinds(repo.path()).contains(&"ai_summary_saved".to_owned()));
    assert_eq!(
        snapshot(repo.path(), file_id).user_readme,
        before.user_readme
    );
    assert_eq!(snapshot(repo.path(), file_id).user_note, before.user_note);
    assert_eq!(
        snapshot(repo.path(), file_id).stored_file_body,
        before.stored_file_body
    );

    let cleared = clear_ai_summary(
        repo_path,
        AiSummaryClearRequest {
            file_id,
            confirmed: true,
        },
    )
    .expect("clear summary");

    assert!(cleared.cleared);
    assert!(ai_summary_row(repo.path(), file_id).is_none());
    assert!(change_log_kinds(repo.path()).contains(&"ai_summary_cleared".to_owned()));
    assert_eq!(
        snapshot(repo.path(), file_id),
        before_with_one_summary_log(before)
    );
}

#[test]
fn ai_summary_validation_blocks_remote_generation_before_privacy_leakage() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let file_id = import_fixture(
        repo.path(),
        "private-remote.txt",
        "original file body with summary-provider-secret should never be sent",
    );
    enable_remote_summaries(repo.path(), "https://provider.example.test/summary");
    let remote_runtime = RemoteRuntimeProbe::new();
    let before = snapshot(repo.path(), file_id);
    let mut request = generation_request(file_id);
    request.provider_scope = AiSummaryProviderScope::RemoteAllowed;
    request.privacy_policy_ref = Some("private-folder".to_owned());

    let draft = generate_ai_summary(repo_path, request).expect("privacy skip draft");

    assert_eq!(draft.status, AiSummaryDraftStatus::Skipped);
    assert_eq!(draft.skipped_reason, Some(AiSummarySkipReason::PrivacyRule));
    assert_eq!(draft.route, None);
    assert!(draft.summary_text.is_none());
    assert!(draft.used_context.is_empty());
    assert_eq!(
        draft.privacy_rule_id.as_deref(),
        Some("rule:private-folder")
    );
    assert!(!remote_runtime.was_invoked());
    assert!(ai_summary_row(repo.path(), file_id).is_none());
    assert_eq!(
        snapshot(repo.path(), file_id).user_readme,
        before.user_readme
    );
    assert_eq!(
        snapshot(repo.path(), file_id).stored_file_body,
        before.stored_file_body
    );

    let row = summary_log_row(
        repo.path(),
        draft.call_log_id.expect("skip has call log id"),
    );
    assert_eq!(row.status, "skipped");
    assert_eq!(row.route, None);
    assert_eq!(row.sent_fields_json, "[]");
    assert_eq!(row.privacy_rule_id.as_deref(), Some("rule:private-folder"));
    assert_contains(&row.result_summary, "privacy rule");
    assert_eq!(row.error_code, None);
    assert_eq!(secret_log_rows(repo.path()), 0);
}

#[test]
fn ai_summary_validation_blocks_remote_runtime_when_call_log_gate_is_unavailable() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let file_id = import_fixture(
        repo.path(),
        "call-log-broken.txt",
        "summary input with remote-only secret",
    );
    enable_remote_summaries(repo.path(), "https://provider.example.test/summary");
    install_broken_ai_call_log_schema(repo.path());
    let remote_runtime = RemoteRuntimeProbe::new();
    let before = snapshot(repo.path(), file_id);
    let mut request = generation_request(file_id);
    request.provider_scope = AiSummaryProviderScope::RemoteAllowed;

    let result = generate_ai_summary(repo_path, request);

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert!(!remote_runtime.was_invoked());
    assert!(ai_summary_row(repo.path(), file_id).is_none());
    assert_eq!(
        snapshot(repo.path(), file_id).user_readme,
        before.user_readme
    );
    assert_eq!(
        snapshot(repo.path(), file_id).stored_file_body,
        before.stored_file_body
    );
}

#[test]
fn ai_summary_validation_locks_core_api_udl_rust_and_docs_alignment() {
    fn assert_generate(
        _: fn(String, AiSummaryGenerationRequest) -> CoreResult<area_matrix_core::AiSummaryDraft>,
    ) {
    }
    fn assert_save(
        _: fn(String, AiSummarySaveRequest) -> CoreResult<area_matrix_core::AiSummarySaveReport>,
    ) {
    }
    fn assert_clear(
        _: fn(String, AiSummaryClearRequest) -> CoreResult<area_matrix_core::AiSummaryClearReport>,
    ) {
    }
    assert_generate(generate_ai_summary);
    assert_save(save_ai_summary);
    assert_clear(clear_ai_summary);

    for fragment in [
        "# 4-2/task-29: C3-06 validation",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
    ] {
        assert_contains(TASK, fragment);
    }
    for fragment in [
        "# C3-06 ai-summary",
        "计划新增：`generate_ai_summary`、`save_ai_summary`、`clear_ai_summary`",
        "保存摘要 metadata。",
        "写 AI call log 和 change log。",
        "可写伴生 summary metadata；不得覆盖用户原文件。",
        "生成结果默认是草稿，用户保存后才持久化。",
        "Clear 只清摘要，不删文件和笔记。",
        "远程摘要必须受隐私规则控制。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
    for fragment in [
        "| S3-06 | ai-summary-editor | C3-06, C3-09 | generate/save/clear summary | summary metadata, ai_call_log |",
        "远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。",
        "AI 结果在用户确认前都是草稿，不直接写分类、标签、摘要。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
    for fragment in [
        "`core/tests/`，每个文件独立编译",
        "### 共享 fixtures",
        "tempfile::{NamedTempFile, TempDir}",
        "## 关键测试场景",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }
    for fragment in [
        "AiSummaryDraft generate_ai_summary(",
        "AiSummarySaveReport save_ai_summary(",
        "AiSummaryClearReport clear_ai_summary(",
        "dictionary AiSummaryGenerationRequest",
        "AiSummaryProviderScope provider_scope;",
        "AiSummaryContextPolicy context_policy;",
        "dictionary AiSummaryDraft",
        "AiSummaryDraftStatus status;",
        "boolean requires_user_save;",
        "dictionary AiSummarySaveRequest",
        "string summary_text;",
        "dictionary AiSummaryClearRequest",
        "boolean confirmed;",
        "enum AiSummarySkipReason",
        "\"PrivacyRule\"",
        "\"CallLogUnavailable\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
    for fragment in [
        "pub fn generate_ai_summary",
        "pub fn save_ai_summary",
        "pub fn clear_ai_summary",
        "Generates a C3-06 AI summary draft without saving it.",
        "Saves a C3-06 AI summary draft as AreaMatrix-owned metadata.",
        "Clears C3-06 AI summary metadata for one file after confirmation.",
        "must not persist a summary",
        "must not delete user notes",
    ] {
        assert_contains(API_RS, fragment);
    }
    for fragment in [
        "pub enum AiSummaryProviderScope",
        "pub enum AiSummaryContextPolicy",
        "pub enum AiSummaryInputField",
        "pub enum AiSummaryDraftStatus",
        "pub enum AiSummarySkipReason",
        "pub struct AiSummaryGenerationRequest",
        "pub struct AiSummarySaveRequest",
        "pub struct AiSummaryClearRequest",
        "validate_save_request",
        "looks_sensitive",
    ] {
        assert_contains(AI_SUMMARY_RS, fragment);
    }
    for fragment in [
        "summary_capability",
        "privacy_blocks",
        "select_route",
        "execute_summary",
        "draft_result",
        "skipped",
        "unavailable_after_runtime_error",
        "used_context_json",
    ] {
        assert_contains(AI_SUMMARY_IMPL_RS, fragment);
    }
    for fragment in [
        "CREATE TABLE IF NOT EXISTS ai_summaries",
        "summary_text TEXT NOT NULL",
        "FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE",
        "insert_summary_change_log",
    ] {
        assert_contains(DB_AI_SUMMARY_RS, fragment);
    }
}

fn before_with_one_summary_log(mut snapshot: SummarySafetySnapshot) -> SummarySafetySnapshot {
    snapshot.ai_call_log_rows += 1;
    snapshot
}
