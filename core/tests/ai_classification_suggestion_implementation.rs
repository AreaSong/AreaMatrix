#[path = "support/ai_classification_suggestion_common.rs"]
mod ai_common;

#[path = "support/remote_provider_config_common.rs"]
mod remote_common;

use std::path::Path;

use ai_common::AiRuntime;
use area_matrix_core::{
    enable_remote_ai_provider, import_file, init_repo, list_files, suggest_category_with_ai,
    test_remote_ai_provider, update_ai_config, AiCategorySuggestionContextField,
    AiCategorySuggestionContextPolicy, AiCategorySuggestionRequest, AiCategorySuggestionRoute,
    AiCategorySuggestionSkipReason, AiCategorySuggestionStatus, AiConfig, AiFeatureConfig,
    AiFeatureKind, AiProviderPreference, DuplicateStrategy, FileFilter, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use remote_common::{enable_request_for_endpoint, test_request_for_endpoint, ProbeRuntime};
use rusqlite::{params, Connection, OptionalExtension};

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

fn ai_config(repo_path: String, feature_enabled: bool) -> AiConfig {
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
                enabled: feature_enabled,
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

fn remote_ai_config(repo_path: String) -> AiConfig {
    let mut config = ai_config(repo_path, true);
    config.provider_preference = AiProviderPreference::RemoteFirst;
    config.local_ai_enabled = false;
    config.remote_ai_allowed = true;
    for toggle in &mut config.feature_toggles {
        if toggle.feature == AiFeatureKind::ClassificationSuggestions {
            toggle.allow_remote = true;
        }
    }
    config
}

#[derive(Debug)]
struct AiLogRow {
    status: String,
    route: Option<String>,
    model: Option<String>,
    sent_fields_json: String,
    privacy_rule_id: Option<String>,
    result_summary: String,
    error_code: Option<String>,
}

fn ai_log_row(repo: &Path, id: i64) -> AiLogRow {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .query_row(
            "SELECT status, route, model, sent_fields_json, privacy_rule_id, result_summary,
                    error_code
             FROM ai_call_log WHERE id = ?1",
            params![id],
            |row| {
                Ok(AiLogRow {
                    status: row.get(0)?,
                    route: row.get(1)?,
                    model: row.get(2)?,
                    sent_fields_json: row.get(3)?,
                    privacy_rule_id: row.get(4)?,
                    result_summary: row.get(5)?,
                    error_code: row.get(6)?,
                })
            },
        )
        .expect("read AI call log row")
}

fn active_category(repo: &Path, file_id: i64) -> String {
    let filter = FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    };
    list_files(path_string(repo), filter)
        .expect("list active files")
        .into_iter()
        .find(|file| file.id == file_id)
        .expect("find imported file")
        .category
}

fn enable_remote_classification_provider(repo: &Path, endpoint_url: &str) {
    let probe = ProbeRuntime::new(200);
    let test_result =
        test_remote_ai_provider(path_string(repo), test_request_for_endpoint(endpoint_url))
            .expect("test remote provider");
    let _ = probe.captured_payload();
    let token = test_result
        .verification_token
        .expect("successful test returns verification token");
    let mut request = enable_request_for_endpoint(token, endpoint_url);
    request.feature_scope = vec![AiFeatureKind::ClassificationSuggestions];
    enable_remote_ai_provider(path_string(repo), request).expect("enable remote provider");
}

#[test]
fn ai_classification_suggestion_implementation_returns_local_draft_without_changing_category() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone(), true))
        .expect("enable AI classification");
    let runtime = AiRuntime::local(
        "finance",
        0.86,
        "local model matched invoice filename and path",
    );

    let suggestion =
        suggest_category_with_ai(repo_path, request(file_id)).expect("suggest category");
    let payload = runtime.captured_payload();

    assert_eq!(suggestion.status, AiCategorySuggestionStatus::Suggested);
    assert_eq!(suggestion.current_category.as_deref(), Some("inbox"));
    assert_eq!(suggestion.suggested_category.as_deref(), Some("finance"));
    assert_eq!(suggestion.route, Some(AiCategorySuggestionRoute::Local));
    assert!(suggestion.requires_user_confirmation);
    assert!(suggestion.confidence > 0.0);
    assert!(suggestion
        .reason
        .as_deref()
        .expect("suggestion reason")
        .contains("local model matched"));
    assert!(payload.contains("\"route\":\"local\""));
    assert!(payload.contains("\"filename\":\"invoice-2026.pdf\""));
    assert_eq!(active_category(repo.path(), file_id), "inbox");

    let log = ai_log_row(
        repo.path(),
        suggestion.call_log_id.expect("suggestion has call log id"),
    );
    assert_eq!(log.status, "success");
    assert_eq!(log.route.as_deref(), Some("local"));
    assert_eq!(log.model.as_deref(), Some("areamatrix-local-classifier"));
    assert!(log.sent_fields_json.contains("filename"));
    assert!(log.sent_fields_json.contains("repo_relative_path"));
    assert!(log.result_summary.contains("finance"));
}

#[test]
fn ai_classification_suggestion_implementation_reports_limited_text_summary_context() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "ambiguous-note.txt", "inbox");
    let imported_path = repo.path().join("inbox/ambiguous-note.txt");
    std::fs::write(
        imported_path,
        "Quarterly payment receipt for invoice 2026 without secret token=hidden",
    )
    .expect("write imported text fixture");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone(), true))
        .expect("enable AI classification");
    let runtime = AiRuntime::local("finance", 0.91, "limited summary mentions payment receipt");
    let mut limited_request = request(file_id);
    limited_request.context_policy = AiCategorySuggestionContextPolicy::LimitedTextSummary;

    let suggestion =
        suggest_category_with_ai(repo_path, limited_request).expect("suggest category");
    let payload = runtime.captured_payload();

    assert_eq!(suggestion.status, AiCategorySuggestionStatus::Suggested);
    assert_eq!(suggestion.suggested_category.as_deref(), Some("finance"));
    assert!(suggestion
        .used_context
        .contains(&AiCategorySuggestionContextField::LimitedTextSummary));
    assert!(payload.contains("\"limited_text_summary\""));
    assert!(payload.contains("Quarterly payment receipt"));
    assert!(!payload.contains("token=hidden"));

    let log = ai_log_row(
        repo.path(),
        suggestion.call_log_id.expect("suggestion has call log id"),
    );
    assert!(log.sent_fields_json.contains("limited_text_summary"));
}

#[test]
fn ai_classification_suggestion_implementation_executes_remote_route_with_provider_metadata() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), remote_ai_config(repo_path.clone()))
        .expect("enable remote AI classification setting");
    let endpoint_url = "https://provider.example.test/classify";
    enable_remote_classification_provider(repo.path(), endpoint_url);
    let runtime = AiRuntime::remote("finance", 0.88, "remote provider matched invoice context");

    let suggestion =
        suggest_category_with_ai(repo_path, request(file_id)).expect("suggest category");
    let payload = runtime.captured_payload();

    assert_eq!(suggestion.status, AiCategorySuggestionStatus::Suggested);
    assert_eq!(suggestion.route, Some(AiCategorySuggestionRoute::Remote));
    assert_eq!(suggestion.suggested_category.as_deref(), Some("finance"));
    assert!(payload.contains("\"route\":\"remote\""));
    assert!(payload.contains("\"provider\":\"Other\""));
    assert!(payload.contains("\"key_reference\""));
    assert!(!payload.contains("test-provider-secret"));
    assert_eq!(active_category(repo.path(), file_id), "inbox");

    let log = ai_log_row(
        repo.path(),
        suggestion.call_log_id.expect("suggestion has call log id"),
    );
    assert_eq!(log.status, "success");
    assert_eq!(log.route.as_deref(), Some("remote"));
    assert_eq!(log.model.as_deref(), Some("gpt-4.1-mini"));
}

#[test]
fn ai_classification_suggestion_implementation_maps_runtime_failure_to_fallback_state() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone(), true))
        .expect("enable AI classification");
    let runtime = AiRuntime::failing_local();

    let suggestion =
        suggest_category_with_ai(repo_path, request(file_id)).expect("runtime failure is fallback");
    let payload = runtime.captured_payload();

    assert_eq!(suggestion.status, AiCategorySuggestionStatus::Unavailable);
    assert_eq!(
        suggestion.skipped_reason,
        Some(AiCategorySuggestionSkipReason::ProviderUnavailable)
    );
    assert_eq!(suggestion.route, Some(AiCategorySuggestionRoute::Local));
    assert!(payload.contains("\"route\":\"local\""));
    assert_eq!(active_category(repo.path(), file_id), "inbox");

    let log = ai_log_row(
        repo.path(),
        suggestion.call_log_id.expect("failure has call log id"),
    );
    assert_eq!(log.status, "failed");
    assert_eq!(log.route.as_deref(), Some("local"));
    assert_eq!(log.error_code.as_deref(), Some("RuntimeFailed"));
}

#[test]
fn ai_classification_suggestion_implementation_skips_when_ai_is_disabled() {
    let repo = initialized_repo();
    let file_id = import_fixture(repo.path(), "unknown.binaryxyz", "inbox");

    let suggestion = suggest_category_with_ai(path_string(repo.path()), request(file_id))
        .expect("AI disabled is structured skip");

    assert_eq!(suggestion.status, AiCategorySuggestionStatus::Skipped);
    assert_eq!(
        suggestion.skipped_reason,
        Some(AiCategorySuggestionSkipReason::AiDisabled)
    );
    assert!(suggestion.suggested_category.is_none());
    assert!(suggestion.requires_user_confirmation);
    let log = ai_log_row(
        repo.path(),
        suggestion.call_log_id.expect("skip has call log id"),
    );
    assert_eq!(log.status, "skipped");
    assert_eq!(log.sent_fields_json, "[]");
}

#[test]
fn ai_classification_suggestion_implementation_skips_privacy_without_sent_fields() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone(), true))
        .expect("enable AI classification");
    let mut blocked = request(file_id);
    blocked.privacy_policy_ref = Some("private-folder".to_owned());

    let suggestion =
        suggest_category_with_ai(repo_path, blocked).expect("privacy skip is structured");

    assert_eq!(suggestion.status, AiCategorySuggestionStatus::Skipped);
    assert_eq!(
        suggestion.skipped_reason,
        Some(AiCategorySuggestionSkipReason::PrivacyRule)
    );
    assert_eq!(suggestion.used_context, Vec::new());
    assert_eq!(
        suggestion.privacy_rule_id.as_deref(),
        Some("rule:private-folder")
    );
    assert_eq!(active_category(repo.path(), file_id), "inbox");

    let log = ai_log_row(
        repo.path(),
        suggestion
            .call_log_id
            .expect("privacy skip has call log id"),
    );
    assert_eq!(log.status, "skipped");
    assert_eq!(log.sent_fields_json, "[]");
    assert_eq!(log.privacy_rule_id.as_deref(), Some("rule:private-folder"));
}

#[test]
fn ai_classification_suggestion_implementation_does_not_override_confident_rule_result() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "finance");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone(), true))
        .expect("enable AI classification");

    let suggestion = suggest_category_with_ai(repo_path, request(file_id))
        .expect("classify with confident rule");

    assert_eq!(suggestion.status, AiCategorySuggestionStatus::NoSuggestion);
    assert_eq!(
        suggestion.skipped_reason,
        Some(AiCategorySuggestionSkipReason::RuleResultConfident)
    );
    assert!(suggestion.suggested_category.is_none());
    assert_eq!(active_category(repo.path(), file_id), "finance");
}

#[test]
fn ai_classification_suggestion_implementation_returns_no_suggestion_for_unmatched_inbox() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "unmatched.binaryxyz", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone(), true))
        .expect("enable AI classification");
    let _runtime = AiRuntime::local("", 0.2, "local model found no useful category");

    let suggestion =
        suggest_category_with_ai(repo_path, request(file_id)).expect("no category suggestion");

    assert_eq!(suggestion.status, AiCategorySuggestionStatus::NoSuggestion);
    assert!(suggestion.suggested_category.is_none());
    assert_eq!(suggestion.route, Some(AiCategorySuggestionRoute::Local));
    assert!(suggestion
        .used_context
        .contains(&AiCategorySuggestionContextField::FileName));
}

#[test]
fn ai_classification_suggestion_implementation_returns_unavailable_when_route_missing() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    let mut config = ai_config(repo_path.clone(), true);
    config.local_ai_enabled = false;
    update_ai_config(repo_path.clone(), config).expect("enable AI without provider route");

    let suggestion =
        suggest_category_with_ai(repo_path, request(file_id)).expect("provider unavailable");

    assert_eq!(suggestion.status, AiCategorySuggestionStatus::Unavailable);
    assert_eq!(
        suggestion.skipped_reason,
        Some(AiCategorySuggestionSkipReason::ProviderUnavailable)
    );
    let log = ai_log_row(
        repo.path(),
        suggestion.call_log_id.expect("unavailable has call log id"),
    );
    assert_eq!(log.status, "unavailable");
}

#[test]
fn ai_classification_suggestion_implementation_leaves_existing_files_untouched() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let readme = repo.path().join("README.md");
    std::fs::write(&readme, "user readme\n").expect("write user README");
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone(), true))
        .expect("enable AI classification");
    let _runtime = AiRuntime::local(
        "finance",
        0.86,
        "local model matched invoice filename and path",
    );

    let _ = suggest_category_with_ai(repo_path, request(file_id)).expect("suggest category");

    assert_eq!(
        std::fs::read_to_string(readme).expect("read user README"),
        "user readme\n"
    );
    let connection =
        Connection::open(repo.path().join(".areamatrix/index.db")).expect("open database");
    let changed_category: Option<String> = connection
        .query_row(
            "SELECT category FROM files WHERE id = ?1 AND status = 'active'",
            params![file_id],
            |row| row.get(0),
        )
        .optional()
        .expect("query file category");
    assert_eq!(changed_category.as_deref(), Some("inbox"));
}
