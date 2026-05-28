#[path = "support/ai_tags_suggestion_common.rs"]
mod common;

use std::{fs, path::Path};

use area_matrix_core::{
    add_tag, apply_ai_tag_suggestions, import_file, init_repo, suggest_tags_with_ai,
    update_ai_config, AiConfig, AiFeatureConfig, AiFeatureKind, AiProviderPreference,
    AiTagSuggestionApplyStatus, AiTagSuggestionCandidateStatus, AiTagSuggestionMergeAction,
    AiTagSuggestionReportStatus, AiTagSuggestionRequest, AiTagSuggestionRoute,
    AiTagSuggestionSkipReason, ApplyAiTagSuggestionItem, ApplyAiTagSuggestionsRequest,
    DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use common::{AiTagsRuntime, RuntimeSuggestion};
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

fn import_fixture(repo: &Path, name: &str, content: &str) -> i64 {
    let source_dir = repo.join("fixtures");
    fs::create_dir_all(&source_dir).expect("create fixture source directory");
    let source = source_dir.join(name);
    fs::write(&source, content).expect("write fixture source");
    import_file(path_string(repo), path_string(&source), import_options())
        .expect("import fixture file")
        .id
}

fn import_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("docs".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn enable_local_tags(repo: &Path) {
    let repo_path = path_string(repo);
    update_ai_config(repo_path.clone(), ai_config(repo_path)).expect("enable local AI tags");
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
                enabled: false,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::AutoSummaries,
                enabled: false,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::AutoTags,
                enabled: true,
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

fn request(file_id: i64) -> AiTagSuggestionRequest {
    AiTagSuggestionRequest {
        file_id,
        candidate_tags: vec!["finance".to_owned(), "invoice".to_owned()],
        privacy_policy_ref: None,
    }
}

#[derive(Debug)]
struct AiLogRow {
    status: String,
    route: Option<String>,
    sent_fields_json: String,
    privacy_rule_id: Option<String>,
    result_summary: String,
    error_code: Option<String>,
}

fn ai_log_row(repo: &Path, id: i64) -> AiLogRow {
    let connection = open_db(repo);
    connection
        .query_row(
            "SELECT status, route, sent_fields_json, privacy_rule_id, result_summary, error_code
               FROM ai_call_log
              WHERE id = ?1",
            params![id],
            |row| {
                Ok(AiLogRow {
                    status: row.get(0)?,
                    route: row.get(1)?,
                    sent_fields_json: row.get(2)?,
                    privacy_rule_id: row.get(3)?,
                    result_summary: row.get(4)?,
                    error_code: row.get(5)?,
                })
            },
        )
        .expect("read AI call log row")
}

fn ai_call_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM ai_call_log", [], |row| row.get(0))
        .expect("count AI call logs")
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn tag_rows(repo: &Path, file_id: i64) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT tag FROM tags WHERE file_id = ?1 ORDER BY tag")
        .expect("prepare tag query");
    statement
        .query_map(params![file_id], |row| row.get::<_, String>(0))
        .expect("query tag rows")
        .map(|row| row.expect("read tag row"))
        .collect()
}

fn change_details(repo: &Path) -> Vec<serde_json::Value> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT detail_json FROM change_log ORDER BY id")
        .expect("prepare change query");
    statement
        .query_map([], |row| {
            let detail: String = row.get(0)?;
            Ok(serde_json::from_str(&detail).expect("valid change detail"))
        })
        .expect("query changes")
        .map(|row| row.expect("read change row"))
        .collect()
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("path is inside repository")
            .to_string_lossy()
            .into_owned();
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

#[test]
fn ai_tags_suggestion_generates_local_review_rows_without_writing_tags() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let target_id = import_fixture(repo.path(), "invoice-2026.txt", "invoice content");
    let other_id = import_fixture(repo.path(), "finance-record.txt", "registry seed");
    add_tag(repo_path.clone(), other_id, "finance".to_owned()).expect("seed existing tag");
    enable_local_tags(repo.path());
    let runtime = AiTagsRuntime::local(vec![
        RuntimeSuggestion::new("finance", "Finance", 0.91, "matched invoice token=hidden"),
        RuntimeSuggestion::new("invoice", "Invoice", 0.62, "weak candidate match"),
    ]);
    let before_tags = tag_rows(repo.path(), target_id);

    let report = suggest_tags_with_ai(repo_path, request(target_id)).expect("suggest AI tags");
    let payload = runtime.captured_payload();

    assert_eq!(report.status, AiTagSuggestionReportStatus::Suggested);
    assert_eq!(report.route, Some(AiTagSuggestionRoute::Local));
    assert!(report.requires_user_confirmation);
    assert!(report.ai_used);
    assert!(!report.network_used);
    assert!(!report.contents_read);
    assert_eq!(tag_rows(repo.path(), target_id), before_tags);
    assert!(payload.contains("\"feature\":\"tags\""));
    assert!(payload.contains("\"filename\":\"invoice-2026.txt\""));
    assert!(payload.contains("\"tag_registry\""));

    let finance = report
        .suggestions
        .iter()
        .find(|suggestion| suggestion.slug == "finance")
        .expect("finance suggestion");
    assert_eq!(finance.status, AiTagSuggestionCandidateStatus::Suggested);
    assert_eq!(
        finance.merge_action,
        AiTagSuggestionMergeAction::UseExistingTag
    );
    assert_eq!(finance.matched_existing_slug.as_deref(), Some("finance"));
    assert!(finance.selected_by_default);
    assert!(!finance.reason.contains("token=hidden"));

    let invoice = report
        .suggestions
        .iter()
        .find(|suggestion| suggestion.slug == "invoice")
        .expect("invoice suggestion");
    assert_eq!(
        invoice.status,
        AiTagSuggestionCandidateStatus::LowConfidence
    );
    assert!(!invoice.selected_by_default);

    let log = ai_log_row(repo.path(), report.call_log_id.expect("call log id"));
    assert_eq!(log.status, "success");
    assert_eq!(log.route.as_deref(), Some("local"));
    assert!(log.sent_fields_json.contains("filename"));
    assert!(log.sent_fields_json.contains("tag_registry"));
    assert!(log.result_summary.contains("Suggested 2 AI tags"));
}

#[test]
fn ai_tags_suggestion_privacy_skip_does_not_invoke_runtime() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "private-note.txt", "private content");
    enable_local_tags(repo.path());
    let runtime = AiTagsRuntime::probe();
    let mut blocked = request(file_id);
    blocked.privacy_policy_ref = Some("block-private-folder".to_owned());

    let report = suggest_tags_with_ai(repo_path, blocked).expect("privacy skip report");

    assert_eq!(report.status, AiTagSuggestionReportStatus::Skipped);
    assert_eq!(
        report.skipped_reason,
        Some(AiTagSuggestionSkipReason::PrivacyRule)
    );
    assert_eq!(
        report.privacy_rule_id.as_deref(),
        Some("rule:block-private-folder")
    );
    assert!(!report.ai_used);
    assert!(!runtime.was_invoked());

    let log = ai_log_row(repo.path(), report.call_log_id.expect("skip call log id"));
    assert_eq!(log.status, "skipped");
    assert_eq!(
        log.privacy_rule_id.as_deref(),
        Some("rule:block-private-folder")
    );
}

#[test]
fn ai_tags_suggestion_apply_writes_tags_change_log_undo_and_ai_log_only() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let target_id = import_fixture(repo.path(), "apply-tags.txt", "tag apply content");
    add_tag(repo_path.clone(), target_id, "tax".to_owned()).expect("seed current tag");
    enable_local_tags(repo.path());
    let _runtime = AiTagsRuntime::local(vec![RuntimeSuggestion::new(
        "finance",
        "Finance",
        0.93,
        "strong local tag",
    )]);
    let draft = suggest_tags_with_ai(repo_path.clone(), request(target_id)).expect("source draft");
    let before_paths = user_visible_paths(repo.path());
    let source_call_log_id = draft.call_log_id.expect("source call log id");

    let report = apply_ai_tag_suggestions(
        repo_path,
        ApplyAiTagSuggestionsRequest {
            file_id: target_id,
            suggestions: vec![
                ApplyAiTagSuggestionItem {
                    suggestion_id: "ai-tag:finance".to_owned(),
                    slug: "finance".to_owned(),
                    display_name: "Finance".to_owned(),
                    confidence: 0.93,
                    edited_by_user: false,
                    merge_target_slug: None,
                },
                ApplyAiTagSuggestionItem {
                    suggestion_id: "ai-tag:tax".to_owned(),
                    slug: "tax".to_owned(),
                    display_name: "Tax".to_owned(),
                    confidence: 0.88,
                    edited_by_user: true,
                    merge_target_slug: None,
                },
            ],
            call_log_id: Some(source_call_log_id),
            privacy_rule_id: None,
            confirmed: true,
        },
    )
    .expect("apply selected AI tag suggestions");

    assert_eq!(report.requested_count, 2);
    assert_eq!(report.applied_count, 1);
    assert_eq!(report.skipped_count, 1);
    assert_eq!(report.failed_count, 0);
    assert_eq!(
        report
            .item_results
            .iter()
            .map(|item| (item.slug.as_str(), item.status.clone()))
            .collect::<Vec<_>>(),
        vec![
            ("finance", AiTagSuggestionApplyStatus::Applied),
            ("tax", AiTagSuggestionApplyStatus::AlreadyAdded),
        ]
    );
    assert_eq!(
        report.refresh_targets,
        vec!["tags", "change_log", "undo_actions", "ai_call_log"]
    );
    assert_eq!(tag_rows(repo.path(), target_id), vec!["finance", "tax"]);
    assert!(report
        .undo_token
        .as_deref()
        .unwrap_or_default()
        .starts_with("undo:ai-tags:"));
    assert_eq!(ai_call_log_count(repo.path()), 2);

    let apply_log = ai_log_row(repo.path(), report.call_log_id.expect("apply call log id"));
    assert_eq!(apply_log.status, "success");
    assert!(apply_log
        .result_summary
        .contains(&format!("source_call_log_id={source_call_log_id}")));
    assert!(apply_log.error_code.is_none());

    let details = change_details(repo.path());
    let ai_apply = details
        .iter()
        .find(|detail| detail["kind"] == "ai_tag_suggestion_applied")
        .expect("AI tag apply change log");
    assert_eq!(ai_apply["tag"], "finance");
    assert_eq!(ai_apply["suggestion_id"], "ai-tag:finance");
    assert_eq!(ai_apply["source_call_log_id"], source_call_log_id);
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}
