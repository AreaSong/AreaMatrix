use std::{fs, path::Path};

use area_matrix_core::{
    import_file, init_repo, list_files, suggest_category_with_ai, update_ai_config,
    AiCategorySuggestionContextField, AiCategorySuggestionContextPolicy,
    AiCategorySuggestionRequest, AiCategorySuggestionRoute, AiCategorySuggestionSkipReason,
    AiCategorySuggestionStatus, AiConfig, AiFeatureConfig, AiFeatureKind, AiProviderPreference,
    CoreError, CoreResult, DuplicateStrategy, ErrorKind, FileFilter, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-19-c3-04-validation.md");
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-3-ai/C3-04-ai-classification-suggestion.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const AI_CLASSIFICATION_RS: &str = include_str!("../src/ai_classification_suggestion.rs");
const AI_CLASSIFICATION_IMPL_RS: &str =
    include_str!("../src/ai_classification_suggestion/implementation.rs");
const AI_CALL_LOG_RS: &str = include_str!("../src/db/ai_call_log.rs");

#[derive(Debug)]
struct AiLogRow {
    status: String,
    route: Option<String>,
    sent_fields_json: String,
    privacy_rule_id: Option<String>,
    result_summary: String,
}

#[derive(Debug, Eq, PartialEq)]
struct ValidationSnapshot {
    active_category: String,
    user_readme: String,
    ai_call_log_rows: i64,
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");
    repo
}

fn import_options(category: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some(category.to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn import_fixture(repo: &Path, name: &str, category: &str) -> i64 {
    let source = repo.join(format!("source-{name}"));
    fs::write(&source, b"private invoice fixture body").expect("write fixture source");
    import_file(
        path_string(repo),
        path_string(&source),
        import_options(category),
    )
    .expect("import fixture file")
    .id
}

fn request(file_id: i64) -> AiCategorySuggestionRequest {
    AiCategorySuggestionRequest {
        file_id,
        context_policy: AiCategorySuggestionContextPolicy::FileNameAndPath,
        privacy_policy_ref: None,
    }
}

fn ai_config(repo_path: String) -> AiConfig {
    AiConfig {
        repo_path,
        ai_enabled: true,
        provider_preference: AiProviderPreference::LocalFirst,
        local_ai_enabled: true,
        remote_ai_allowed: false,
        privacy_gate_enabled: true,
        privacy_policy_ref: None,
        feature_toggles: vec![
            AiFeatureConfig {
                feature: AiFeatureKind::ClassificationSuggestions,
                enabled: true,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::AutoSummaries,
                enabled: false,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::AutoTags,
                enabled: false,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::SemanticSearch,
                enabled: false,
                allow_remote: false,
            },
        ],
    }
}

fn snapshot(repo: &Path, file_id: i64) -> ValidationSnapshot {
    ValidationSnapshot {
        active_category: active_category(repo, file_id),
        user_readme: fs::read_to_string(repo.join("README.md")).expect("read user README"),
        ai_call_log_rows: ai_call_log_count(repo),
    }
}

fn active_category(repo: &Path, file_id: i64) -> String {
    list_files(
        path_string(repo),
        FileFilter {
            category: None,
            include_deleted: None,
            imported_after: None,
            imported_before: None,
            limit: 100,
            offset: 0,
        },
    )
    .expect("list active files")
    .into_iter()
    .find(|file| file.id == file_id)
    .expect("find imported file")
    .category
}

fn ai_call_log_count(repo: &Path) -> i64 {
    let connection = Connection::open(repo.join(".areamatrix/index.db")).expect("open database");
    let table_exists = connection
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master
             WHERE type = 'table' AND name = 'ai_call_log'",
            [],
            |row| row.get::<_, i64>(0),
        )
        .expect("query AI call log table presence");
    if table_exists == 0 {
        return 0;
    }
    connection
        .query_row("SELECT COUNT(*) FROM ai_call_log", [], |row| {
            row.get::<_, i64>(0)
        })
        .expect("count AI call log rows")
}

fn ai_log_row(repo: &Path, id: i64) -> AiLogRow {
    let connection = Connection::open(repo.join(".areamatrix/index.db")).expect("open database");
    connection
        .query_row(
            "SELECT status, route, sent_fields_json, privacy_rule_id, result_summary
             FROM ai_call_log WHERE id = ?1",
            params![id],
            |row| {
                Ok(AiLogRow {
                    status: row.get(0)?,
                    route: row.get(1)?,
                    sent_fields_json: row.get(2)?,
                    privacy_rule_id: row.get(3)?,
                    result_summary: row.get(4)?,
                })
            },
        )
        .expect("read AI call log row")
}

fn secret_log_rows(repo: &Path) -> i64 {
    let connection = Connection::open(repo.join(".areamatrix/index.db")).expect("open database");
    connection
        .query_row(
            "SELECT COUNT(*) FROM ai_call_log
             WHERE result_summary LIKE '%sk-secret%'
                OR privacy_rule_id LIKE '%sk-secret%'
                OR sent_fields_json LIKE '%private invoice fixture body%'",
            [],
            |row| row.get(0),
        )
        .expect("query leaked AI call log rows")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn ai_classification_suggestion_validation_covers_ui_ready_success_path() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone()))
        .expect("enable AI classification");
    let before = snapshot(repo.path(), file_id);

    let suggestion =
        suggest_category_with_ai(repo_path, request(file_id)).expect("suggest category");

    assert_eq!(suggestion.status, AiCategorySuggestionStatus::Suggested);
    assert_eq!(suggestion.current_category.as_deref(), Some("inbox"));
    assert_eq!(suggestion.suggested_category.as_deref(), Some("finance"));
    assert_eq!(suggestion.route, Some(AiCategorySuggestionRoute::Local));
    assert!(suggestion.requires_user_confirmation);
    assert!(suggestion.confidence > 0.0);
    assert!(suggestion
        .reason
        .expect("suggestion reason")
        .contains("confirm"));
    assert_eq!(
        suggestion.used_context,
        vec![
            AiCategorySuggestionContextField::FileName,
            AiCategorySuggestionContextField::Extension,
            AiCategorySuggestionContextField::RepoRelativePath,
        ]
    );

    let after = snapshot(repo.path(), file_id);
    assert_eq!(after.active_category, before.active_category);
    assert_eq!(after.user_readme, before.user_readme);
    assert_eq!(after.ai_call_log_rows, before.ai_call_log_rows + 1);

    let log = ai_log_row(
        repo.path(),
        suggestion
            .call_log_id
            .expect("successful suggestion has call log id"),
    );
    assert_eq!(log.status, "success");
    assert_eq!(log.route.as_deref(), Some("local"));
    assert_contains(&log.sent_fields_json, "filename");
    assert_contains(&log.sent_fields_json, "extension");
    assert_contains(&log.sent_fields_json, "repo_relative_path");
    assert_contains(&log.result_summary, "finance");
    assert_eq!(secret_log_rows(repo.path()), 0);
}

#[test]
fn ai_classification_suggestion_validation_covers_failure_and_privacy_boundaries() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone()))
        .expect("enable AI classification");
    let before = snapshot(repo.path(), file_id);

    let mut secret_request = request(file_id);
    secret_request.privacy_policy_ref = Some("sk-secret-provider-key".to_owned());
    let secret_error = suggest_category_with_ai(repo_path.clone(), secret_request)
        .expect_err("secret-like privacy reference must fail");

    assert_eq!(secret_error.kind(), ErrorKind::Config);
    assert!(matches!(secret_error, CoreError::Config { .. }));
    assert!(!secret_error.to_string().contains("sk-secret"));
    assert_eq!(snapshot(repo.path(), file_id), before);

    let mut blocked_request = request(file_id);
    blocked_request.privacy_policy_ref = Some("private-folder".to_owned());
    let skipped =
        suggest_category_with_ai(repo_path, blocked_request).expect("privacy skip is structured");

    assert_eq!(skipped.status, AiCategorySuggestionStatus::Skipped);
    assert_eq!(
        skipped.skipped_reason,
        Some(AiCategorySuggestionSkipReason::PrivacyRule)
    );
    assert!(skipped.suggested_category.is_none());
    assert!(skipped.used_context.is_empty());
    assert_eq!(
        skipped.privacy_rule_id.as_deref(),
        Some("rule:private-folder")
    );
    assert!(skipped.requires_user_confirmation);
    assert_eq!(
        active_category(repo.path(), file_id),
        before.active_category
    );
    assert_eq!(
        fs::read_to_string(repo.path().join("README.md")).expect("read user README"),
        before.user_readme
    );

    let log = ai_log_row(
        repo.path(),
        skipped.call_log_id.expect("privacy skip has call log id"),
    );
    assert_eq!(log.status, "skipped");
    assert_eq!(log.route, None);
    assert_eq!(log.sent_fields_json, "[]");
    assert_eq!(log.privacy_rule_id.as_deref(), Some("rule:private-folder"));
    assert_contains(&log.result_summary, "privacy rule");
    assert_eq!(secret_log_rows(repo.path()), 0);
}

#[test]
fn ai_classification_suggestion_validation_locks_api_udl_rust_and_docs_alignment() {
    fn assert_signature(
        _: fn(
            String,
            AiCategorySuggestionRequest,
        ) -> CoreResult<area_matrix_core::AiCategorySuggestion>,
    ) {
    }
    assert_signature(suggest_category_with_ai);

    for fragment in [
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
    ] {
        assert_contains(TASK, fragment);
    }
    for fragment in [
        "计划新增：`suggest_category_with_ai(repo_path, file_id) -> AiCategorySuggestion`",
        "建议分类、confidence、reason、是否本地/远程。",
        "写 AI call log。",
        "用户采纳前不改 `files.category`。",
        "隐私规则命中时返回 skipped reason。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
    for fragment in [
        "| S3-04 | ai-classification-suggestion | C3-04, C3-09, C3-10 | AI category suggestion | ai_call_log, no write before confirm",
        "| S3-10 | ai-fallback | C3-04, C3-08, C3-10 | fallback status | ai_call_log",
        "AI 结果在用户确认前都是草稿，不直接写分类、标签、摘要。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
    for fragment in [
        "`core/tests/`，每个文件独立编译",
        "## 关键测试场景",
        "### Classify 模块",
        "无效 yaml 时保留旧规则",
        "`core/tests/` 下，全场景从 init_repo",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }
    for fragment in [
        "AiCategorySuggestion suggest_category_with_ai(",
        "string repo_path, AiCategorySuggestionRequest request",
        "dictionary AiCategorySuggestionRequest",
        "AiCategorySuggestionContextPolicy context_policy;",
        "dictionary AiCategorySuggestion",
        "AiCategorySuggestionStatus status;",
        "boolean requires_user_confirmation;",
        "enum AiCategorySuggestionSkipReason",
        "\"PrivacyRule\"",
        "\"ProviderUnavailable\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
    for fragment in [
        "pub fn suggest_category_with_ai",
        "Requests a C3-04 AI category suggestion without applying it.",
        "Returned suggestions are drafts only",
        "requires_user_confirmation",
        "must not overwrite classifier rules",
        "`files.category`, move files",
    ] {
        assert_contains(API_RS, fragment);
    }
    for fragment in [
        "pub struct AiCategorySuggestionRequest",
        "pub struct AiCategorySuggestion",
        "validate_policy_ref",
        "looks_sensitive",
        "ensure_metadata_readable",
    ] {
        assert_contains(AI_CLASSIFICATION_RS, fragment);
    }
    for fragment in [
        "classification_capability",
        "privacy_blocks",
        "rule_result_is_confident",
        "select_route",
        "insert_call_log",
        "requires_user_confirmation: true",
    ] {
        assert_contains(AI_CLASSIFICATION_IMPL_RS, fragment);
    }
    for fragment in [
        "CREATE TABLE IF NOT EXISTS ai_call_log",
        "status TEXT NOT NULL CHECK",
        "sent_fields_json TEXT NOT NULL",
        "privacy_rule_id TEXT",
    ] {
        assert_contains(AI_CALL_LOG_RS, fragment);
    }
}
