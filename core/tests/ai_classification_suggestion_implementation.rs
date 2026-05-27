use std::path::Path;

use area_matrix_core::{
    import_file, init_repo, list_files, suggest_category_with_ai, update_ai_config,
    AiCategorySuggestionContextField, AiCategorySuggestionContextPolicy,
    AiCategorySuggestionRequest, AiCategorySuggestionRoute, AiCategorySuggestionSkipReason,
    AiCategorySuggestionStatus, AiConfig, AiFeatureConfig, AiFeatureKind, AiProviderPreference,
    DuplicateStrategy, FileFilter, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
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
    let source = repo.join(format!("source-{name}"));
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

#[derive(Debug)]
struct AiLogRow {
    status: String,
    route: Option<String>,
    sent_fields_json: String,
    privacy_rule_id: Option<String>,
    result_summary: String,
}

fn ai_log_row(repo: &Path, id: i64) -> AiLogRow {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
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

#[test]
fn ai_classification_suggestion_implementation_returns_local_draft_without_changing_category() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone(), true))
        .expect("enable AI classification");

    let suggestion =
        suggest_category_with_ai(repo_path, request(file_id)).expect("suggest category");

    assert_eq!(suggestion.status, AiCategorySuggestionStatus::Suggested);
    assert_eq!(suggestion.current_category.as_deref(), Some("inbox"));
    assert_eq!(suggestion.suggested_category.as_deref(), Some("finance"));
    assert_eq!(suggestion.route, Some(AiCategorySuggestionRoute::Local));
    assert!(suggestion.requires_user_confirmation);
    assert!(suggestion.confidence > 0.0);
    assert_eq!(active_category(repo.path(), file_id), "inbox");

    let log = ai_log_row(
        repo.path(),
        suggestion.call_log_id.expect("suggestion has call log id"),
    );
    assert_eq!(log.status, "success");
    assert_eq!(log.route.as_deref(), Some("local"));
    assert!(log.sent_fields_json.contains("filename"));
    assert!(log.sent_fields_json.contains("repo_relative_path"));
    assert!(log.result_summary.contains("finance"));
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
