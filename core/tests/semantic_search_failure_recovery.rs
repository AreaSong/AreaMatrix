use std::fs;

use area_matrix_core::{
    build_embedding_index, map_core_error, semantic_search, AiProviderPreference, CoreError,
    ErrorKind, ErrorMappingInput, ErrorRecoverability, ErrorSeverity, SearchPagination,
    SemanticIndexStatus, SemanticSearchFallbackReason, SemanticSearchRoute,
};
use pretty_assertions::assert_eq;

#[path = "support/semantic_search_failure.rs"]
mod failure;
#[path = "support/semantic_search_common.rs"]
mod semantic_search_common;
use failure::{
    active_file_path, ai_config, assert_no_secret_material, combined_log_text,
    ensure_ai_call_log_table, install_abort_trigger, table_count, table_exists, update_ai_config,
    user_visible_paths, ReadOnlyGuard,
};
use semantic_search_common::{
    ai_log_row, default_filter, enable_local_semantic_search, first_page, initialized_repo,
    insert_file, insert_file_with_body, insert_tag, path_string, repo_config_value,
    save_privacy_rules, semantic_scope,
};

#[test]
fn semantic_search_failure_empty_repo_and_default_ai_off_return_explicit_fallback() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let before_paths = user_visible_paths(repo.path());

    let page = semantic_search(
        path_string(repo.path()),
        "invoice".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("default-off fallback page");

    assert_eq!(
        page.fallback_reason,
        Some(SemanticSearchFallbackReason::AiDisabled)
    );
    assert_eq!(page.semantic_total_count, 0);
    assert_eq!(page.normal_total_count, 0);
    assert!(page.semantic_matches.is_empty());
    assert!(page.normal_matches.is_empty());
    assert_eq!(page.index_status, SemanticIndexStatus::NotReady);
    assert_eq!(user_visible_paths(repo.path()), before_paths);
    assert!(!table_exists(repo.path(), "semantic_index_entries"));
    assert_eq!(table_count(repo.path(), "ai_call_log"), 1);
}

#[test]
fn semantic_search_failure_invalid_inputs_are_config_errors_without_writes() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    let before_paths = user_visible_paths(repo.path());

    let mut current_node_without_path = default_filter();
    current_node_without_path.scope = area_matrix_core::SearchScope::CurrentNode;
    let mut secret_tag = default_filter();
    secret_tag.tags = vec!["token=sk-secret".to_owned()];
    let mut invalid_range = default_filter();
    invalid_range.imported_after = Some(20);
    invalid_range.imported_before = Some(10);

    for (query, filter, pagination) in [
        (" ".to_owned(), default_filter(), first_page()),
        ("contains\0nul".to_owned(), default_filter(), first_page()),
        (
            "invoice".to_owned(),
            current_node_without_path,
            first_page(),
        ),
        ("invoice".to_owned(), secret_tag, first_page()),
        ("invoice".to_owned(), invalid_range, first_page()),
        (
            "invoice".to_owned(),
            default_filter(),
            SearchPagination {
                limit: 0,
                offset: 0,
            },
        ),
    ] {
        let error = semantic_search(path_string(repo.path()), query, filter, pagination)
            .expect_err("invalid semantic search input must fail");
        assert!(matches!(error, CoreError::Config { .. }));
    }

    let mut unconfirmed = semantic_scope();
    unconfirmed.confirmed = false;
    assert!(matches!(
        build_embedding_index(path_string(repo.path()), unconfirmed),
        Err(CoreError::Config { .. })
    ));

    let mut secret_ref = semantic_scope();
    secret_ref.privacy_policy_ref = Some("sk-secret-key".to_owned());
    assert!(matches!(
        build_embedding_index(path_string(repo.path()), secret_ref),
        Err(CoreError::Config { .. })
    ));

    assert_eq!(user_visible_paths(repo.path()), before_paths);
    assert!(!table_exists(repo.path(), "semantic_index_entries"));
    assert!(!table_exists(repo.path(), "ai_call_log"));
}

#[test]
fn semantic_search_failure_permission_denied_on_content_read_is_structured_and_non_mutating() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = insert_file_with_body(
        repo.path(),
        "secure/private.txt",
        "secure",
        None,
        "private semantic body",
    );
    let file_path = repo.path().join("secure/private.txt");
    enable_local_semantic_search(repo.path());
    let before_paths = user_visible_paths(repo.path());
    let _guard = ReadOnlyGuard::new(&file_path);

    let error = build_embedding_index(repo_path, semantic_scope())
        .expect_err("unreadable content must fail explicitly");

    assert!(matches!(error, CoreError::PermissionDenied { .. }));
    assert_eq!(user_visible_paths(repo.path()), before_paths);
    assert_eq!(
        repo_config_value(repo.path(), "semantic_index_metadata"),
        None
    );
    assert!(!table_exists(repo.path(), "semantic_index_entries"));
    assert_eq!(table_count(repo.path(), "ai_call_log"), 0);
    assert_eq!(active_file_path(repo.path(), file_id), "secure/private.txt");
}

#[test]
fn semantic_search_failure_missing_content_is_counted_without_silent_success() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = insert_file(repo.path(), "docs/missing-body.txt", "docs", None);
    insert_tag(repo.path(), file_id, "needs-review");
    fs::remove_file(repo.path().join("docs/missing-body.txt")).expect("remove indexed body");
    enable_local_semantic_search(repo.path());

    let report = build_embedding_index(repo_path, semantic_scope())
        .expect("missing content produces failed-count report");

    assert_eq!(report.status, SemanticIndexStatus::Failed);
    assert_eq!(report.total_count, 1);
    assert_eq!(report.processed_count, 0);
    assert_eq!(report.failed_count, 1);
    assert_eq!(report.fallback_reason, None);
    assert!(report
        .message
        .as_deref()
        .expect("build message")
        .contains("1 file(s) failed"));
    let row = ai_log_row(repo.path(), report.call_log_id.expect("call log id"));
    assert_eq!(row.0, "failed");
    assert_eq!(row.3.as_deref(), Some("SemanticIndexBuildFailed"));
}

#[test]
fn semantic_search_failure_call_log_abort_rolls_back_index_metadata() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    insert_file(
        repo.path(),
        "finance/invoice.txt",
        "finance",
        Some("invoice"),
    );
    enable_local_semantic_search(repo.path());
    ensure_ai_call_log_table(repo.path());
    install_abort_trigger(
        repo.path(),
        "fail_semantic_call_log_insert",
        "BEFORE INSERT ON ai_call_log",
    );

    let error = build_embedding_index(repo_path, semantic_scope())
        .expect_err("call-log insert failure must roll back index build");

    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(
        repo_config_value(repo.path(), "semantic_index_metadata"),
        None
    );
    assert!(!table_exists(repo.path(), "semantic_index_entries"));
    assert_eq!(table_count(repo.path(), "ai_call_log"), 0);
}

#[test]
fn semantic_search_failure_privacy_skip_and_remote_gate_do_not_leak_key_material() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    insert_file_with_body(
        repo.path(),
        "finance/private-invoice.txt",
        "finance",
        Some("invoice"),
        "private invoice body",
    );
    save_privacy_rules(
        repo.path(),
        r#"{"rules":[{"id":"rule:keyword:private-invoice","type":"Keyword","pattern":"private-invoice","applies_to":"Local and remote AI","enabled":true}]}"#,
    );
    enable_local_semantic_search(repo.path());

    let report = build_embedding_index(repo_path.clone(), semantic_scope())
        .expect("privacy skip build report");
    let page = semantic_search(
        repo_path,
        "invoice".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("privacy fallback page");

    assert_eq!(
        report.fallback_reason,
        Some(SemanticSearchFallbackReason::PrivacyRule)
    );
    assert_eq!(
        page.fallback_reason,
        Some(SemanticSearchFallbackReason::PrivacyRule)
    );
    assert_eq!(
        page.privacy_rule_id.as_deref(),
        Some("rule:keyword:private-invoice")
    );
    assert_no_secret_material(&combined_log_text(repo.path()));

    let remote_repo = initialized_repo();
    let remote_path = path_string(remote_repo.path());
    update_ai_config(
        remote_repo.path(),
        ai_config(
            remote_path.clone(),
            true,
            false,
            true,
            AiProviderPreference::RemoteFirst,
            true,
            true,
        ),
    );
    let mut remote_scope = semantic_scope();
    remote_scope.route = Some(SemanticSearchRoute::Remote);

    let remote_report =
        build_embedding_index(remote_path.clone(), remote_scope).expect("remote disabled report");
    let remote_page = semantic_search(
        remote_path,
        "invoice".to_owned(),
        default_filter(),
        first_page(),
    )
    .expect("remote provider unavailable page");

    assert_eq!(
        remote_report.fallback_reason,
        Some(SemanticSearchFallbackReason::ProviderUnavailable)
    );
    assert_eq!(
        remote_page.fallback_reason,
        Some(SemanticSearchFallbackReason::ProviderUnavailable)
    );
    assert_no_secret_material(&combined_log_text(remote_repo.path()));
}

#[test]
fn semantic_search_failure_error_mapping_matches_documented_recoverability() {
    let config = map_core_error(ErrorMappingInput {
        kind: ErrorKind::Config,
        path: None,
        reason: Some("semantic search query is invalid".to_owned()),
        message: None,
    });
    assert_eq!(config.severity, ErrorSeverity::Medium);
    assert_eq!(
        config.recoverability,
        ErrorRecoverability::UserActionRequired
    );

    let permission = map_core_error(ErrorMappingInput {
        kind: ErrorKind::PermissionDenied,
        path: Some("repo/secure/private.txt".to_owned()),
        reason: None,
        message: None,
    });
    assert_eq!(permission.severity, ErrorSeverity::High);
    assert_eq!(
        permission.recoverability,
        ErrorRecoverability::UserActionRequired
    );

    let locked = map_core_error(ErrorMappingInput {
        kind: ErrorKind::Db,
        path: None,
        reason: None,
        message: Some("database is locked".to_owned()),
    });
    assert_eq!(locked.recoverability, ErrorRecoverability::Retryable);

    let corrupted = map_core_error(ErrorMappingInput {
        kind: ErrorKind::Db,
        path: None,
        reason: None,
        message: Some("no such table: semantic_index_entries".to_owned()),
    });
    assert_eq!(corrupted.severity, ErrorSeverity::Critical);
    assert_eq!(corrupted.recoverability, ErrorRecoverability::Fatal);

    let internal = map_core_error(ErrorMappingInput {
        kind: ErrorKind::Internal,
        path: None,
        reason: None,
        message: Some("semantic runtime unavailable".to_owned()),
    });
    assert_eq!(internal.severity, ErrorSeverity::Critical);
    assert_eq!(internal.recoverability, ErrorRecoverability::Fatal);
}
