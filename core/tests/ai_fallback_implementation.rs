use std::{fs, path::Path};

use area_matrix_core::{
    get_ai_fallback_status, init_repo, list_ai_calls, AiCallLogFeature, AiCallLogFilter,
    AiCallLogPagination, AiCallLogRoute, AiCallLogStatus, AiCategorySuggestionSkipReason,
    AiFallbackAction, AiFallbackKind, AiFallbackOperation, AiFallbackProviderErrorKind,
    AiFallbackStatusRequest, AiPrivacyDecision, AiPrivacySkippedReason, CoreError, OverviewOutput,
    RepoInitMode, RepoInitOptions, SemanticSearchFallbackReason,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

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
        call_log_id: None,
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
        call_log_id: None,
        privacy_rule_id: None,
        retry_after: None,
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

fn first_page() -> AiCallLogPagination {
    AiCallLogPagination {
        limit: 50,
        offset: 0,
    }
}

fn log_count(repo: &Path) -> i64 {
    Connection::open(repo.join(".areamatrix/index.db"))
        .expect("open repository database")
        .query_row("SELECT COUNT(*) FROM ai_call_log", [], |row| row.get(0))
        .expect("count AI call logs")
}

#[test]
fn ai_fallback_implementation_records_sanitized_failure_log_without_user_file_changes() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let user_file = repo.path().join("README.md");
    fs::write(&user_file, "user readme\n").expect("write user README");

    let status =
        get_ai_fallback_status(repo_path.clone(), remote_failed_request()).expect("fallback");

    assert_eq!(status.kind, AiFallbackKind::RemoteFailed);
    assert!(status.retryable);
    assert_eq!(status.primary_action, Some(AiFallbackAction::Retry));
    assert_eq!(status.secondary_action, Some(AiFallbackAction::ViewCallLog));
    let log_id = status.call_log_id.expect("fallback log id");

    let page = list_ai_calls(
        repo_path,
        AiCallLogFilter {
            feature: Some(AiCallLogFeature::SemanticSearch),
            route: Some(AiCallLogRoute::Remote),
            status: Some(AiCallLogStatus::Failed),
            occurred_after: None,
            occurred_before: None,
            search_query: Some("ProviderUnavailable".to_owned()),
        },
        first_page(),
    )
    .expect("list fallback log");
    let record = page.records.first().expect("fallback record");
    assert_eq!(page.total_count, 1);
    assert_eq!(record.id, log_id);
    assert_eq!(record.sent_fields, Vec::new());
    assert_eq!(record.error_code.as_deref(), Some("ProviderUnavailable"));
    assert_eq!(record.provider_name.as_deref(), Some("remote_provider"));
    assert_eq!(
        record.model_name.as_deref(),
        Some("configured-remote-provider")
    );
    assert!(record
        .result_summary
        .contains("Your files were not changed"));
    assert_eq!(
        fs::read_to_string(&user_file).expect("read user README"),
        "user readme\n"
    );
}

#[test]
fn ai_fallback_implementation_records_privacy_skip_with_rule_traceability() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());

    let status =
        get_ai_fallback_status(repo_path.clone(), privacy_request()).expect("privacy fallback");

    assert_eq!(status.kind, AiFallbackKind::PrivacySkipped);
    assert!(!status.retryable);
    assert_eq!(
        status.primary_action,
        Some(AiFallbackAction::ViewPrivacyRule)
    );
    assert_eq!(status.secondary_action, Some(AiFallbackAction::ViewCallLog));

    let logs = list_ai_calls(repo_path, default_filter(), first_page()).expect("list logs");
    let record = logs.records.first().expect("privacy fallback log");
    assert_eq!(logs.total_count, 1);
    assert_eq!(record.id, status.call_log_id.expect("fallback log id"));
    assert_eq!(record.feature, AiCallLogFeature::Classification);
    assert_eq!(record.status, AiCallLogStatus::Skipped);
    assert_eq!(record.sent_fields, Vec::new());
    assert_eq!(
        record.privacy_rule_id.as_deref(),
        Some("rule:private-folder")
    );
    assert_eq!(record.error_code.as_deref(), Some("PrivacySkipped"));
}

#[test]
fn ai_fallback_implementation_keeps_existing_call_log_reference_without_duplication() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let initial_status = get_ai_fallback_status(repo_path.clone(), remote_failed_request())
        .expect("initial fallback");
    let existing_log_id = initial_status.call_log_id.expect("fallback log id");
    let before = log_count(repo.path());
    let mut request = remote_failed_request();
    request.call_log_id = Some(existing_log_id);

    let status = get_ai_fallback_status(repo_path.clone(), request).expect("fallback");

    assert_eq!(status.call_log_id, Some(existing_log_id));
    assert_eq!(status.secondary_action, Some(AiFallbackAction::ViewCallLog));
    assert_eq!(log_count(repo.path()), before);
    let logs = list_ai_calls(repo_path, default_filter(), first_page()).expect("list logs");
    assert_eq!(logs.total_count, 1);
    assert_eq!(logs.records[0].id, existing_log_id);
}

#[test]
fn ai_fallback_implementation_maps_metadata_failures_without_touching_user_files() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let user_file = repo.path().join("kept-user-file.txt");
    fs::write(&user_file, b"user owned").expect("write user file fixture");
    fs::remove_dir_all(repo.path().join(".areamatrix")).expect("remove metadata fixture");

    let error = get_ai_fallback_status(repo_path, remote_failed_request())
        .expect_err("missing metadata must fail");

    assert!(matches!(error, CoreError::Config { .. }));
    assert_eq!(
        fs::read(&user_file).expect("read user file after failed fallback"),
        b"user owned"
    );
}

#[test]
fn ai_fallback_implementation_handles_semantic_index_fallback_without_ai_execution() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());

    let status = get_ai_fallback_status(
        repo_path.clone(),
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
    .expect("semantic index fallback");

    assert_eq!(status.kind, AiFallbackKind::SemanticIndexNotReady);
    assert_eq!(
        status.primary_action,
        Some(AiFallbackAction::BuildSemanticIndex)
    );
    assert_eq!(
        status.secondary_action,
        Some(AiFallbackAction::UseNormalSearch)
    );
    let logs = list_ai_calls(repo_path, default_filter(), first_page()).expect("list logs");
    let record = logs.records.first().expect("semantic fallback log");
    assert_eq!(record.status, AiCallLogStatus::Unavailable);
    assert_eq!(record.route, Some(AiCallLogRoute::Local));
    assert_eq!(record.error_code.as_deref(), Some("SemanticIndexNotReady"));
}
