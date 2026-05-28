#[path = "support/ai_classification_suggestion_common.rs"]
mod ai_common;

use std::path::Path;

use ai_common::AiRuntime;
use area_matrix_core::{
    clear_ai_call_log, import_file, init_repo, list_ai_calls, list_files, suggest_category_with_ai,
    update_ai_config, AiCallLogClearRequest, AiCallLogClearScope, AiCallLogFeature,
    AiCallLogFilter, AiCallLogPagination, AiCallLogRoute, AiCallLogSentField, AiCallLogStatus,
    AiCategorySuggestionContextPolicy, AiCategorySuggestionRequest, AiConfig, AiFeatureConfig,
    AiFeatureKind, AiProviderPreference, CoreError, DuplicateStrategy, FileFilter,
    ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

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
    let source_dir = repo.join("fixtures");
    std::fs::create_dir_all(&source_dir).expect("create fixture source directory");
    let source = source_dir.join(name);
    std::fs::write(&source, b"fixture").expect("write fixture source");
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

fn default_filter() -> AiCallLogFilter {
    AiCallLogFilter {
        feature: None,
        route: None,
        status: None,
        occurred_after: None,
        occurred_before: None,
        search_query: None,
    }
}

fn page(limit: i64, offset: i64) -> AiCallLogPagination {
    AiCallLogPagination { limit, offset }
}

fn insert_provider_test_log(
    repo: &Path,
    status: &str,
    occurred_at: i64,
    result_summary: &str,
) -> i64 {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .execute(
            "INSERT INTO ai_call_log (
                feature, file_id, scope, route, provider, model, status, duration_ms,
                sent_fields_json, privacy_rules_checked, result_summary, error_code, occurred_at
             ) VALUES (
                'provider_test', NULL, 'Provider verification', 'remote',
                'Remote provider', 'gpt-4.1-mini', ?1, 1200,
                '[]', 0, ?2, 'ProviderUnavailable', ?3
             )",
            params![status, result_summary, occurred_at],
        )
        .expect("insert provider test log row");
    connection.last_insert_rowid()
}

fn insert_sensitive_provider_test_log(repo: &Path) -> i64 {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .execute(
            "INSERT INTO ai_call_log (
                feature, file_id, scope, route, provider, model, status, duration_ms,
                sent_fields_json, privacy_rules_checked, result_summary, error_code, occurred_at
             ) VALUES (
                'provider_test', NULL, 'Provider verification', 'remote',
                'keychain:raw-provider', 'secure-storage:env:SECRET', 'failed', 1200,
                '[]', 0, 'api_key=sk-secret token=hidden', 'sk-secret', 1900000000
             )",
            [],
        )
        .expect("insert sensitive provider test log row");
    connection.last_insert_rowid()
}

fn ai_call_log_count(repo: &Path) -> i64 {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .query_row("SELECT COUNT(*) FROM ai_call_log", [], |row| row.get(0))
        .expect("count AI call log rows")
}

fn remove_metadata_directory(repo: &Path) {
    std::fs::remove_dir_all(repo.join(".areamatrix")).expect("remove metadata directory fixture");
}

fn repo_config_count(repo: &Path) -> i64 {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .query_row("SELECT COUNT(*) FROM repo_config", [], |row| row.get(0))
        .expect("count repo config rows")
}

#[test]
fn ai_call_log_implementation_lists_redacted_records_with_filters_and_pagination() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone())).expect("enable AI");
    let runtime = AiRuntime::local("finance", 0.89, "local model matched invoice");
    let suggestion =
        suggest_category_with_ai(repo_path.clone(), request(file_id)).expect("suggest category");
    let payload = runtime.captured_payload();
    assert!(payload.contains("invoice-2026.pdf"));
    let provider_log_id = insert_provider_test_log(
        repo.path(),
        "failed",
        1_800_000_000,
        "Connection failed without exposing secrets",
    );

    let all = list_ai_calls(repo_path.clone(), default_filter(), page(1, 0)).expect("list logs");
    assert_eq!(all.total_count, 2);
    assert_eq!(all.limit, 1);
    assert_eq!(all.offset, 0);
    assert!(all.has_more);
    assert_eq!(all.retention_days, 90);
    assert!(all.redaction_policy.contains("No API keys"));
    assert_eq!(all.records[0].id, provider_log_id);
    assert_eq!(all.records[0].feature, AiCallLogFeature::ProviderTest);
    assert_eq!(all.records[0].route, Some(AiCallLogRoute::Remote));
    assert_eq!(all.records[0].status, AiCallLogStatus::Failed);
    assert!(all.records[0].sent_fields.is_empty());

    let sensitive_id = insert_sensitive_provider_test_log(repo.path());
    let sensitive =
        list_ai_calls(repo_path.clone(), default_filter(), page(1, 0)).expect("list sensitive log");
    let sensitive_record = sensitive.records.first().expect("sensitive log record");
    assert_eq!(sensitive_record.id, sensitive_id);
    for value in [
        sensitive_record.provider_name.as_deref(),
        sensitive_record.model_name.as_deref(),
        Some(sensitive_record.result_summary.as_str()),
        sensitive_record.error_code.as_deref(),
    ]
    .into_iter()
    .flatten()
    {
        assert!(!value.contains("sk-secret"));
        assert!(!value.contains("keychain:"));
        assert!(!value.contains("secure-storage:"));
        assert!(!value.contains("token=hidden"));
    }

    let filtered = list_ai_calls(
        repo_path,
        AiCallLogFilter {
            feature: Some(AiCallLogFeature::Classification),
            route: Some(AiCallLogRoute::Local),
            status: Some(AiCallLogStatus::Success),
            occurred_after: None,
            occurred_before: None,
            search_query: Some("invoice".to_owned()),
        },
        page(50, 0),
    )
    .expect("filter classification logs");

    assert_eq!(filtered.total_count, 1);
    let record = filtered.records.first().expect("one filtered log record");
    assert_eq!(record.id, suggestion.call_log_id.expect("call log id"));
    assert_eq!(record.feature, AiCallLogFeature::Classification);
    assert_eq!(record.file_id, Some(file_id));
    assert_eq!(
        record.file_display_name.as_deref(),
        Some("invoice-2026.pdf")
    );
    assert_eq!(record.scope.as_deref(), Some("Classification"));
    assert_eq!(record.route, Some(AiCallLogRoute::Local));
    assert_eq!(record.provider_name.as_deref(), Some("local_model"));
    for field in [
        AiCallLogSentField::FileName,
        AiCallLogSentField::RepoRelativePath,
        AiCallLogSentField::Extension,
    ] {
        assert!(record.sent_fields.contains(&field));
    }
    assert_eq!(record.sent_fields.len(), 3);
    assert!(record.result_summary.contains("finance"));
}

#[test]
fn ai_call_log_implementation_clears_only_requested_audit_rows() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "receipt.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone())).expect("enable AI");
    let _runtime = AiRuntime::local("finance", 0.82, "local model matched receipt");
    let suggestion =
        suggest_category_with_ai(repo_path.clone(), request(file_id)).expect("suggest category");
    let old_provider_id = insert_provider_test_log(repo.path(), "failed", 100, "old provider log");
    let new_provider_id =
        insert_provider_test_log(repo.path(), "failed", 1_800_000_000, "new provider log");
    let user_file = repo.path().join("inbox/receipt.pdf");
    let config_rows_before = repo_config_count(repo.path());

    let selected = clear_ai_call_log(
        repo_path.clone(),
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::SelectedEntries,
            entry_ids: vec![suggestion.call_log_id.expect("call log id")],
            older_than: None,
        },
    )
    .expect("clear selected log");
    assert_eq!(selected.deleted_count, 1);
    assert_eq!(selected.remaining_count, 2);
    assert!(user_file.exists());
    assert_eq!(repo_config_count(repo.path()), config_rows_before);

    let older_than = clear_ai_call_log(
        repo_path.clone(),
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::OlderThan,
            entry_ids: Vec::new(),
            older_than: Some(1_000),
        },
    )
    .expect("clear old logs");
    assert_eq!(older_than.deleted_count, 1);
    assert_eq!(older_than.remaining_count, 1);

    let remaining = list_ai_calls(repo_path.clone(), default_filter(), page(50, 0))
        .expect("list remaining logs");
    assert_eq!(remaining.records.len(), 1);
    assert_eq!(remaining.records[0].id, new_provider_id);
    assert_ne!(remaining.records[0].id, old_provider_id);

    let all = clear_ai_call_log(
        repo_path.clone(),
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::All,
            entry_ids: Vec::new(),
            older_than: None,
        },
    )
    .expect("clear all logs");
    assert_eq!(all.deleted_count, 1);
    assert_eq!(all.remaining_count, 0);
    assert_eq!(ai_call_log_count(repo.path()), 0);
    assert!(user_file.exists());

    let files = list_files(
        repo_path,
        FileFilter {
            category: None,
            include_deleted: None,
            imported_after: None,
            imported_before: None,
            limit: 50,
            offset: 0,
        },
    )
    .expect("list files after clearing logs");
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].id, file_id);
}

#[test]
fn ai_call_log_clear_maps_missing_metadata_to_db_without_touching_user_files() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let user_file = repo.path().join("kept-user-file.txt");
    std::fs::write(&user_file, b"user owned").expect("write user file fixture");
    remove_metadata_directory(repo.path());

    let result = clear_ai_call_log(
        repo_path,
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::All,
            entry_ids: Vec::new(),
            older_than: None,
        },
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        std::fs::read(&user_file).expect("read user file after failed clear"),
        b"user owned"
    );
}
