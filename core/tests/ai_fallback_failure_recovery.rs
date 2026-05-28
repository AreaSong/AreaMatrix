use std::{fs, path::Path};

use area_matrix_core::{
    get_ai_fallback_status, init_repo, list_ai_calls, AiCallLogFilter, AiCallLogPagination,
    AiCallLogRoute, AiCallLogStatus, AiFallbackKind, AiFallbackOperation,
    AiFallbackProviderErrorKind, AiFallbackStatusRequest, AiPrivacyDecision, CoreError,
    OverviewOutput, RepoInitMode, RepoInitOptions, SemanticSearchFallbackReason,
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

fn remote_rate_limited_request() -> AiFallbackStatusRequest {
    AiFallbackStatusRequest {
        operation: AiFallbackOperation::SemanticSearch,
        route: Some(AiCallLogRoute::Remote),
        provider_error: Some(AiFallbackProviderErrorKind::RateLimited),
        provider_error_code: Some("RateLimited".to_owned()),
        privacy_decision: Some(AiPrivacyDecision::Allowed),
        privacy_skipped_reason: None,
        category_skipped_reason: None,
        semantic_fallback_reason: None,
        call_log_status: Some(AiCallLogStatus::Failed),
        call_log_id: None,
        privacy_rule_id: None,
        retry_after: Some(4_102_444_800),
    }
}

fn log_count(repo: &Path) -> i64 {
    Connection::open(repo.join(".areamatrix/index.db"))
        .expect("open repository database")
        .query_row("SELECT COUNT(*) FROM ai_call_log", [], |row| row.get(0))
        .expect("count AI call logs")
}

fn first_page() -> AiCallLogPagination {
    AiCallLogPagination {
        limit: 50,
        offset: 0,
    }
}

fn all_logs() -> AiCallLogFilter {
    AiCallLogFilter {
        feature: None,
        route: None,
        status: None,
        occurred_after: None,
        occurred_before: None,
        search_query: None,
    }
}

#[test]
fn ai_fallback_failure_rejects_invalid_edge_inputs_before_metadata_writes() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let valid = remote_rate_limited_request();
    get_ai_fallback_status(repo_path.clone(), valid).expect("seed valid fallback log");
    let before = log_count(repo.path());

    let invalid_cases = [
        {
            let mut request = remote_rate_limited_request();
            request.provider_error = None;
            request
        },
        {
            let mut request = remote_rate_limited_request();
            request.operation = AiFallbackOperation::ClassificationSuggestion;
            request.semantic_fallback_reason = Some(SemanticSearchFallbackReason::Timeout);
            request
        },
        {
            let mut request = remote_rate_limited_request();
            request.provider_error = Some(AiFallbackProviderErrorKind::RemoteFailed);
            request.retry_after = Some(4_102_444_800);
            request
        },
        {
            let mut request = remote_rate_limited_request();
            request.privacy_rule_id = Some("sk-secret".to_owned());
            request
        },
    ];

    for request in invalid_cases {
        assert!(matches!(
            get_ai_fallback_status(repo_path.clone(), request),
            Err(CoreError::Config { .. })
        ));
    }
    assert_eq!(log_count(repo.path()), before);
}

#[test]
fn ai_fallback_failure_maps_permission_denied_and_keeps_user_files_unchanged() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let user_file = repo.path().join("contract.txt");
    fs::write(&user_file, "user-owned\n").expect("write user file fixture");
    let db_path = repo.path().join(".areamatrix/index.db");
    let original_permissions = fs::metadata(&db_path)
        .expect("read db metadata")
        .permissions();
    let mut readonly = original_permissions.clone();
    readonly.set_readonly(true);
    fs::set_permissions(&db_path, readonly).expect("make db readonly fixture");

    let result = get_ai_fallback_status(repo_path, remote_rate_limited_request());

    fs::set_permissions(&db_path, original_permissions).expect("restore db permissions");
    assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
    assert_eq!(
        fs::read_to_string(&user_file).expect("read user file after permission failure"),
        "user-owned\n"
    );
}

#[test]
fn ai_fallback_failure_maps_corrupt_db_without_leaving_half_log_or_user_file_changes() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let user_file = repo.path().join("invoice.pdf");
    fs::write(&user_file, b"user content").expect("write user file fixture");
    fs::write(repo.path().join(".areamatrix/index.db"), b"not sqlite").expect("corrupt db fixture");

    let error = get_ai_fallback_status(repo_path, remote_rate_limited_request())
        .expect_err("corrupt db must fail");

    assert!(matches!(error, CoreError::Internal { .. }));
    assert_eq!(
        fs::read(&user_file).expect("read user file after db failure"),
        b"user content"
    );
}

#[test]
fn ai_fallback_failure_rolls_back_call_log_insert_when_schema_rejects_status() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    get_ai_fallback_status(repo_path.clone(), remote_rate_limited_request())
        .expect("seed table before trigger");
    let connection =
        Connection::open(repo.path().join(".areamatrix/index.db")).expect("open repository db");
    connection
        .execute("DELETE FROM ai_call_log", [])
        .expect("clear seeded fallback log");
    connection
        .execute(
            "CREATE TRIGGER reject_ai_fallback_insert
             BEFORE INSERT ON ai_call_log
             BEGIN
               SELECT RAISE(ABORT, 'simulated ai fallback insert failure');
             END",
            [],
        )
        .expect("install rollback trigger");

    let error = get_ai_fallback_status(repo_path.clone(), remote_rate_limited_request())
        .expect_err("trigger must abort fallback logging");

    assert!(matches!(error, CoreError::Internal { .. }));
    let page = list_ai_calls(repo_path, all_logs(), first_page()).expect("list logs after abort");
    assert_eq!(page.total_count, 0);
    assert!(page.records.is_empty());
}

#[test]
fn ai_fallback_failure_never_persists_key_like_or_path_like_provider_codes() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let blocked_codes = [
        "sk-secret-key",
        "BearerToken",
        "provider/raw/path",
        "secret=value",
        "api_key",
    ];

    for code in blocked_codes {
        let mut request = remote_rate_limited_request();
        request.provider_error_code = Some(code.to_owned());
        assert!(matches!(
            get_ai_fallback_status(repo_path.clone(), request),
            Err(CoreError::Config { .. })
        ));
    }

    let page = list_ai_calls(repo_path, all_logs(), first_page()).expect("list logs");
    assert_eq!(page.total_count, 0);
}

#[test]
fn ai_fallback_failure_rate_limit_maps_to_retry_later_without_provider_failover() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());

    let status = get_ai_fallback_status(repo_path.clone(), remote_rate_limited_request())
        .expect("rate-limit fallback");

    assert_eq!(status.kind, AiFallbackKind::RateLimited);
    assert_eq!(status.route, Some(AiCallLogRoute::Remote));
    assert_eq!(status.retry_after, Some(4_102_444_800));
    let logs = list_ai_calls(repo_path, all_logs(), first_page()).expect("list logs");
    let record = logs.records.first().expect("fallback log");
    assert!(record.sent_fields.is_empty());
    assert_eq!(record.provider_name.as_deref(), Some("remote_provider"));
    assert_eq!(record.error_code.as_deref(), Some("RateLimited"));
}
