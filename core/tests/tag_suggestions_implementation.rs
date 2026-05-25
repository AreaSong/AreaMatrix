use std::{fs, path::Path};

use area_matrix_core::{
    apply_tag_suggestions, init_repo, list_changes, list_undo_actions, suggest_tags_for_file,
    ApplyTagSuggestionItem, ApplyTagSuggestionsRequest, ChangeFilter, OverviewOutput, RepoInitMode,
    RepoInitOptions, TagSuggestionApplyStatus, TagSuggestionMatch, TagSuggestionRequest,
    TagSuggestionSource, TagSuggestionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_file(repo: &Path, relative_path: &str, source_path: Option<&str>) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create fixture directory");
    fs::write(&file_path, format!("fixture bytes for {relative_path}"))
        .expect("write fixture file");

    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture has filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'docs', 13,
                ?3, 'copied', 'imported', ?4,
                100, 100, 'active'
             )",
            params![
                relative_path,
                current_name,
                format!("{:064x}", relative_path.len()),
                source_path,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

fn insert_tag(repo: &Path, file_id: i64, tag: &str, added_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, ?3)",
            params![file_id, tag, added_at],
        )
        .expect("insert tag row");
}

fn tag_rows(repo: &Path) -> Vec<(i64, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT file_id, tag FROM tags ORDER BY file_id, tag")
        .expect("prepare tags query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query tags")
        .map(|row| row.expect("read tag row"))
        .collect()
}

fn change_details(repo: &Path) -> Vec<serde_json::Value> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT detail_json
               FROM change_log
              WHERE action = 'external_modified'
              ORDER BY id",
        )
        .expect("prepare change-log query");
    statement
        .query_map([], |row| {
            let detail: String = row.get(0)?;
            Ok(serde_json::from_str(&detail).expect("change detail json is valid"))
        })
        .expect("query change-log")
        .map(|row| row.expect("read change-log row"))
        .collect()
}

fn undo_row(repo: &Path, token: &str) -> (String, serde_json::Value, serde_json::Value) {
    open_db(repo)
        .query_row(
            "SELECT kind, summary_json, inverse_json
               FROM undo_actions
              WHERE token = ?1",
            params![token],
            |row| {
                let summary: String = row.get(1)?;
                let inverse: String = row.get(2)?;
                Ok((
                    row.get(0)?,
                    serde_json::from_str(&summary).expect("summary json is valid"),
                    serde_json::from_str(&inverse).expect("inverse json is valid"),
                ))
            },
        )
        .expect("read undo row")
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

fn default_change_filter(file_id: i64) -> ChangeFilter {
    ChangeFilter {
        file_id: Some(file_id),
        category: None,
        action: Some("external_modified".to_owned()),
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

#[test]
fn tag_suggestions_implementation_generates_deterministic_non_ai_rows() {
    let repo = initialized_repo();
    let target_id = insert_file(
        repo.path(),
        "finance/client-a_tax_report.pdf",
        Some("/incoming/invoices/client-a_tax_report.pdf"),
    );
    let other_id = insert_file(repo.path(), "archive/finance-source.pdf", None);
    insert_tag(repo.path(), other_id, "finance", 100);
    insert_tag(repo.path(), other_id, "client-a", 110);
    insert_tag(repo.path(), target_id, "tax", 120);
    let before_paths = user_visible_paths(repo.path());

    let report = suggest_tags_for_file(
        path_string(repo.path()),
        TagSuggestionRequest {
            file_id: target_id,
            context: None,
            limit: 12,
        },
    )
    .expect("suggest tags for active file");

    assert_eq!(report.file_id, target_id);
    assert!(!report.contents_read);
    assert!(!report.ai_used);
    assert!(!report.network_used);
    assert_eq!(report.tag_set.file_tags[0].value, "tax");

    let finance = report
        .suggestions
        .iter()
        .find(|suggestion| suggestion.slug == "finance")
        .expect("finance suggestion from path");
    assert_eq!(finance.source, TagSuggestionSource::Path);
    assert_eq!(finance.match_strength, TagSuggestionMatch::Strong);
    assert!(finance.already_exists);
    assert!(!finance.needs_create);
    assert_eq!(finance.status, TagSuggestionStatus::NewTag);
    assert!(finance.selected_by_default);

    let client = report
        .suggestions
        .iter()
        .find(|suggestion| suggestion.slug == "client-a")
        .expect("client-a suggestion from file name");
    assert_eq!(client.source, TagSuggestionSource::FileName);
    assert_eq!(client.match_strength, TagSuggestionMatch::Strong);
    assert!(client.selected_by_default);

    let tax = report
        .suggestions
        .iter()
        .find(|suggestion| suggestion.slug == "tax")
        .expect("already-added tag remains visible but disabled");
    assert_eq!(tax.status, TagSuggestionStatus::AlreadyAdded);
    assert!(!tax.selected_by_default);
    assert_eq!(tax.disabled_reason.as_deref(), Some("Already added"));

    let report_tag = report
        .suggestions
        .iter()
        .find(|suggestion| suggestion.slug == "report")
        .expect("new weak tag from deterministic filename token");
    assert_eq!(report_tag.match_strength, TagSuggestionMatch::Weak);
    assert!(report_tag.needs_create);
    assert!(!report_tag.selected_by_default);
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[test]
fn tag_suggestions_implementation_applies_tags_and_records_undo_without_file_changes() {
    let repo = initialized_repo();
    let target_id = insert_file(repo.path(), "finance/client-a_tax_report.pdf", None);
    let other_id = insert_file(repo.path(), "archive/existing.pdf", None);
    insert_tag(repo.path(), other_id, "finance", 100);
    insert_tag(repo.path(), target_id, "tax", 110);
    let before_paths = user_visible_paths(repo.path());

    let report = apply_tag_suggestions(
        path_string(repo.path()),
        ApplyTagSuggestionsRequest {
            file_id: target_id,
            suggestions: vec![
                ApplyTagSuggestionItem {
                    suggestion_id: "suggestion:path:finance".to_owned(),
                    slug: "finance".to_owned(),
                    display_name: "Finance".to_owned(),
                },
                ApplyTagSuggestionItem {
                    suggestion_id: "suggestion:file-name:tax".to_owned(),
                    slug: "tax".to_owned(),
                    display_name: "Tax".to_owned(),
                },
            ],
        },
    )
    .expect("apply selected tag suggestions");

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
            ("finance", TagSuggestionApplyStatus::Applied),
            ("tax", TagSuggestionApplyStatus::AlreadyAdded),
        ]
    );
    assert_eq!(
        report.refresh_targets,
        vec!["tags", "change_log", "undo_actions"]
    );
    assert_eq!(
        report
            .tag_set
            .file_tags
            .iter()
            .map(|record| record.value.as_str())
            .collect::<Vec<_>>(),
        vec!["finance", "tax"]
    );

    let token = report
        .undo_token
        .as_deref()
        .expect("new relation creates undo token");
    assert!(token.starts_with("undo:tag-suggestions:"));
    let (kind, summary, inverse) = undo_row(repo.path(), token);
    assert_eq!(kind, "batch_add_tags");
    assert_eq!(summary["kind"], "tag_suggestions");
    assert_eq!(summary["added_count"], 1);
    let relations = inverse["relations"].as_array().expect("relations array");
    assert_eq!(relations.len(), 1);
    assert_eq!(relations[0]["file_id"], target_id);
    assert_eq!(relations[0]["tag"], "finance");

    assert_eq!(
        tag_rows(repo.path()),
        vec![
            (target_id, "finance".to_owned()),
            (target_id, "tax".to_owned()),
            (other_id, "finance".to_owned()),
        ]
    );
    let details = change_details(repo.path());
    assert_eq!(details.len(), 1);
    assert_eq!(details[0]["kind"], "tag_suggestion_applied");
    assert_eq!(details[0]["suggestion_id"], "suggestion:path:finance");
    assert_eq!(details[0]["tag"], "finance");

    let changes = list_changes(path_string(repo.path()), default_change_filter(target_id))
        .expect("change log remains queryable");
    assert_eq!(changes.len(), 1);
    let undo_actions =
        list_undo_actions(path_string(repo.path())).expect("undo action is readable");
    assert_eq!(undo_actions[0].action_id, token);
    assert!(undo_actions[0].can_undo);
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[test]
fn tag_suggestions_implementation_skips_already_added_without_undo() {
    let repo = initialized_repo();
    let target_id = insert_file(repo.path(), "docs/tax.pdf", None);
    insert_tag(repo.path(), target_id, "tax", 100);

    let report = apply_tag_suggestions(
        path_string(repo.path()),
        ApplyTagSuggestionsRequest {
            file_id: target_id,
            suggestions: vec![ApplyTagSuggestionItem {
                suggestion_id: "suggestion:file-name:tax".to_owned(),
                slug: "tax".to_owned(),
                display_name: "Tax".to_owned(),
            }],
        },
    )
    .expect("already-added suggestion is idempotent");

    assert_eq!(report.applied_count, 0);
    assert_eq!(report.skipped_count, 1);
    assert_eq!(report.failed_count, 0);
    assert!(report.undo_token.is_none());
    assert!(change_details(repo.path()).is_empty());
    assert!(list_undo_actions(path_string(repo.path()))
        .expect("list undo actions")
        .is_empty());
}
