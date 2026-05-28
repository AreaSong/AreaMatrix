use std::{fs, path::Path};

use area_matrix_core::{
    import_file, init_repo, list_ai_calls, predict_category, search_files, AiCallLogFilter,
    AiCallLogPagination, AiCallLogRoute, AiCallLogStatus, AiCategorySuggestionSkipReason,
    AiFallbackAction, AiFallbackCategory, AiFallbackKind, AiFallbackOperation,
    AiFallbackProviderErrorKind, AiFallbackStatus, AiFallbackStatusRequest, AiPrivacyDecision,
    AiPrivacySkippedReason, DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput,
    RepoInitMode, RepoInitOptions, SearchFilter, SearchPagination, SearchScope, SearchSort,
    SearchTagMatchMode, StorageMode,
};
use pretty_assertions::assert_eq;

#[derive(Debug, Eq, PartialEq)]
pub struct RepoSnapshot {
    pub user_readme: String,
    pub ai_call_log_rows: i64,
    pub user_visible_paths: Vec<String>,
}

pub fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub fn initialized_repo() -> tempfile::TempDir {
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

pub fn snapshot(repo: &Path) -> RepoSnapshot {
    RepoSnapshot {
        user_readme: fs::read_to_string(repo.join("README.md")).expect("read user README"),
        ai_call_log_rows: ai_call_log_count(repo),
        user_visible_paths: user_visible_paths(repo),
    }
}

pub fn remote_failed_request() -> AiFallbackStatusRequest {
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

pub fn privacy_skipped_request() -> AiFallbackStatusRequest {
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

pub fn ai_disabled_request() -> AiFallbackStatusRequest {
    AiFallbackStatusRequest {
        operation: AiFallbackOperation::SemanticSearch,
        route: None,
        provider_error: None,
        provider_error_code: None,
        privacy_decision: None,
        privacy_skipped_reason: None,
        category_skipped_reason: None,
        semantic_fallback_reason: Some(area_matrix_core::SemanticSearchFallbackReason::AiDisabled),
        call_log_status: Some(AiCallLogStatus::Skipped),
        call_log_id: None,
        privacy_rule_id: None,
        retry_after: None,
    }
}

pub fn local_model_not_ready_request() -> AiFallbackStatusRequest {
    AiFallbackStatusRequest {
        operation: AiFallbackOperation::EmbeddingIndexBuild,
        route: Some(AiCallLogRoute::Local),
        provider_error: Some(AiFallbackProviderErrorKind::LocalModelNotReady),
        provider_error_code: Some("LocalModelNotReady".to_owned()),
        privacy_decision: Some(AiPrivacyDecision::Allowed),
        privacy_skipped_reason: None,
        category_skipped_reason: None,
        semantic_fallback_reason: None,
        call_log_status: Some(AiCallLogStatus::Unavailable),
        call_log_id: None,
        privacy_rule_id: None,
        retry_after: None,
    }
}

pub fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

pub fn assert_secret_free(value: &str) {
    for forbidden in ["sk-", "api_key", "bearer", "secret=", "token=", "/Users/"] {
        assert!(
            !value.to_ascii_lowercase().contains(forbidden),
            "fallback validation output leaked `{forbidden}` in `{value}`"
        );
    }
}

pub fn assert_status(
    status: &AiFallbackStatus,
    kind: AiFallbackKind,
    category: AiFallbackCategory,
    primary_action: Option<AiFallbackAction>,
    secondary_action: Option<AiFallbackAction>,
    non_ai_fallback_action: AiFallbackAction,
    retryable: bool,
) {
    assert_eq!(status.kind, kind);
    assert_eq!(status.category, category);
    assert_eq!(status.primary_action, primary_action);
    assert_eq!(status.secondary_action, secondary_action);
    assert_eq!(status.non_ai_fallback_action, non_ai_fallback_action);
    assert_eq!(status.retryable, retryable);
    if retryable {
        assert!(status.retry_disabled_reason.is_none());
    } else {
        assert!(status.retry_disabled_reason.is_some());
    }
    assert!(!status.title.is_empty());
    assert!(!status.message.is_empty());
    assert!(status.call_log_id.is_some());
}

pub fn assert_non_ai_paths_still_work(repo: &Path, repo_path: String) {
    let source_dir = tempfile::tempdir().expect("create fallback import source directory");
    let source = source_dir.path().join("invoice-after-ai-fallback.txt");
    fs::write(&source, "ordinary import content").expect("write import source");

    let imported = import_file(
        repo_path.clone(),
        path_string(&source),
        import_options("inbox"),
    )
    .expect("AI fallback must not block import");
    assert_eq!(imported.current_name, "invoice-after-ai-fallback.txt");

    let search = search_files(
        repo_path.clone(),
        "invoice".to_owned(),
        default_search_filter(),
        SearchSort::Relevance,
        first_search_page(),
    )
    .expect("AI fallback must not block normal search");
    assert!(search
        .results
        .iter()
        .any(|result| result.entry.id == imported.id));

    let predicted = predict_category(repo_path, "invoice-after-ai-fallback.txt".to_owned())
        .expect("AI fallback must not block local classifier rules");
    assert_eq!(predicted.suggested_name, "invoice-after-ai-fallback.txt");
    assert!(repo.join(&imported.path).exists());
}

fn default_ai_call_filter() -> AiCallLogFilter {
    AiCallLogFilter {
        feature: None,
        route: None,
        status: None,
        occurred_after: None,
        occurred_before: None,
        search_query: None,
    }
}

fn first_ai_log_page() -> AiCallLogPagination {
    AiCallLogPagination {
        limit: 100,
        offset: 0,
    }
}

fn default_search_filter() -> SearchFilter {
    SearchFilter {
        scope: SearchScope::AllRepo,
        current_path: None,
        category: None,
        file_kind: None,
        tags: Vec::new(),
        tag_match_mode: SearchTagMatchMode::Any,
        imported_after: None,
        imported_before: None,
        modified_after: None,
        modified_before: None,
        storage_mode: None,
        include_deleted: Some(false),
    }
}

fn first_search_page() -> SearchPagination {
    SearchPagination {
        limit: 25,
        offset: 0,
    }
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

fn ai_call_log_count(repo: &Path) -> i64 {
    list_ai_calls(
        path_string(repo),
        default_ai_call_filter(),
        first_ai_log_page(),
    )
    .expect("list AI fallback validation logs")
    .total_count
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_visible_paths(root: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read validation repository directory") {
        let entry = entry.expect("read validation repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(root)
            .expect("validation path stays inside repository");
        if relative.starts_with(".areamatrix") {
            continue;
        }
        paths.push(relative.to_string_lossy().into_owned());
        if path.is_dir() {
            collect_visible_paths(root, &path, paths);
        }
    }
}
