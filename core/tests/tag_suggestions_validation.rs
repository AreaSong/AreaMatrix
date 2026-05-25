use std::path::Path;

use area_matrix_core::{
    apply_tag_suggestions, list_changes, list_tags, list_undo_actions, search_files,
    suggest_tags_for_file, ApplyTagSuggestionItem, ApplyTagSuggestionsRequest, ChangeFilter,
    CoreResult, SearchFilter, SearchPagination, SearchScope, SearchSort, SearchTagMatchMode,
    TagSuggestionApplyReport, TagSuggestionApplyStatus, TagSuggestionContext, TagSuggestionMatch,
    TagSuggestionReport, TagSuggestionRequest, TagSuggestionSource, TagSuggestionStatus,
};
use pretty_assertions::assert_eq;

#[allow(dead_code)]
#[path = "support/tag_suggestions_failure.rs"]
mod tag_suggestions_failure;

use tag_suggestions_failure::{
    apply, apply_request, assert_conflict, assert_db_error, assert_file_not_found,
    assert_validation, change_log_rows, initialized_repo, insert_file, insert_tag,
    install_tag_suggestion_change_log_failure, install_undo_failure, path_string, snapshot,
    suggest, tag_rows, undo_action_rows, user_visible_paths,
};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-19-tag-suggestions.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const TAGS_RS: &str = include_str!("../src/tags.rs");
const TAG_SUGGESTIONS_RS: &str = include_str!("../src/tags/suggestions.rs");
const DB_TAG_SUGGESTIONS_RS: &str = include_str!("../src/db/tags/suggestions.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_all_contains(haystack: &str, needles: &[&str]) {
    for needle in needles {
        assert_contains(haystack, needle);
    }
}

fn assert_signatures() {
    fn assert_suggest(_: fn(String, TagSuggestionRequest) -> CoreResult<TagSuggestionReport>) {}
    fn assert_apply(
        _: fn(String, ApplyTagSuggestionsRequest) -> CoreResult<TagSuggestionApplyReport>,
    ) {
    }

    assert_suggest(suggest_tags_for_file);
    assert_apply(apply_tag_suggestions);
}

fn request_with_context(file_id: i64) -> TagSuggestionRequest {
    TagSuggestionRequest {
        file_id,
        context: Some(TagSuggestionContext {
            source_folder: Some("Incoming/Finance".to_owned()),
            source_keywords: vec!["client-a".to_owned()],
        }),
        limit: 12,
    }
}

fn apply_request_for(file_id: i64, slugs: &[&str]) -> ApplyTagSuggestionsRequest {
    ApplyTagSuggestionsRequest {
        file_id,
        suggestions: slugs
            .iter()
            .map(|slug| ApplyTagSuggestionItem {
                suggestion_id: format!("validation:{slug}"),
                slug: (*slug).to_owned(),
                display_name: (*slug).to_owned(),
            })
            .collect(),
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

fn tag_search_filter(tag: &str) -> SearchFilter {
    SearchFilter {
        scope: SearchScope::AllRepo,
        current_path: None,
        category: None,
        file_kind: None,
        tags: vec![tag.to_owned()],
        tag_match_mode: SearchTagMatchMode::All,
        imported_after: None,
        imported_before: None,
        modified_after: None,
        modified_before: None,
        storage_mode: None,
        include_deleted: None,
    }
}

fn first_suggestion<'a>(
    report: &'a TagSuggestionReport,
    slug: &str,
) -> &'a area_matrix_core::TagSuggestion {
    report
        .suggestions
        .iter()
        .find(|suggestion| suggestion.slug == slug)
        .expect("expected suggestion slug to exist")
}

fn assert_c2_19_docs_api_udl_and_rust_are_aligned() {
    assert_docs_and_testing_alignment();
    assert_core_api_and_udl_alignment();
    assert_rust_surface_alignment();
}

fn assert_docs_and_testing_alignment() {
    assert_all_contains(
        CAPABILITY_SPEC,
        &[
            "# C2-19 tag-suggestions",
            "- S2-23 tag-suggestions",
            "`suggest_tags_for_file`",
            "`apply_tag_suggestions`",
            "file_id、可选来源上下文、建议数量上限。",
            "建议标签、来源理由、是否已存在、是否需新建。",
            "不读取文件正文，不调用 AI，不发生网络访问。",
            "采纳建议后能被搜索、筛选、详情页和 undo 读取。",
            "AI 标签建议属于 Stage 3 的 C3-07。",
        ],
    );
    assert_all_contains(
        CONTROL_MAP,
        &[
            "| S2-23 | tag-suggestions | C2-19, C2-05 | non-AI tag suggestion",
            "tags, file_tags after confirm",
            "`4-1/task-140`, `4-1/task-141`, `4-1/task-142`",
        ],
    );
}

fn assert_core_api_and_udl_alignment() {
    for fragment in [
        "TagSuggestionReport suggest_tags_for_file(",
        "TagSuggestionApplyReport apply_tag_suggestions(",
        "dictionary TagSuggestionContext",
        "dictionary TagSuggestionRequest",
        "dictionary TagSuggestion",
        "dictionary TagSuggestionReport",
        "dictionary ApplyTagSuggestionsRequest",
        "dictionary TagSuggestionApplyReport",
        "enum TagSuggestionSource { \"FileName\", \"Path\", \"SourceFolder\", \"ExistingTagPattern\" };",
        "enum TagSuggestionMatch { \"Strong\", \"Weak\" };",
        "enum TagSuggestionStatus { \"NewTag\", \"AlreadyAdded\", \"Invalid\", \"Blocked\" };",
        "enum TagSuggestionApplyStatus { \"Applied\", \"AlreadyAdded\", \"Failed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
    assert_all_contains(
        CORE_API,
        &[
            "| `suggest_tags_for_file(repo, request)` | tags | √ | FileNotFound / Validation / Conflict / Db |",
            "| `apply_tag_suggestions(repo, request)` | tags | √ | FileNotFound / Validation / Conflict / Db |",
        ],
    );
}

fn assert_rust_surface_alignment() {
    assert_all_contains(
        LIB_RS,
        &[
            "suggest_tags_for_file",
            "apply_tag_suggestions",
            "TagSuggestionReport",
            "TagSuggestionApplyReport",
        ],
    );
    assert_all_contains(
        API_RS,
        &[
            "pub fn suggest_tags_for_file(",
            "crate::tags::suggest_tags_for_file",
            "pub fn apply_tag_suggestions(",
            "crate::tags::apply_tag_suggestions",
            "no AI, network, or content read",
        ],
    );
    assert_all_contains(
        TAGS_RS,
        &[
            "C2-19 owns the Stage 2 tag-suggestion contract for S2-23",
            "must not read file contents",
            "call AI or remote providers",
            "access the network",
            "must never apply unselected",
        ],
    );
    assert_all_contains(
        TAG_SUGGESTIONS_RS,
        &[
            "contents_read: false",
            "ai_used: false",
            "network_used: false",
        ],
    );
    assert_all_contains(
        DB_TAG_SUGGESTIONS_RS,
        &[
            "create_tag_suggestion_undo_action",
            "\"tags\".to_owned()",
            "\"change_log\".to_owned()",
            "\"undo_actions\".to_owned()",
        ],
    );
}

fn assert_suggestion_report_is_local_and_read_only(
    repo: &Path,
    report: &TagSuggestionReport,
    file_id: i64,
    before_paths: &[String],
) {
    assert_eq!(report.file_id, file_id);
    assert!(!report.contents_read);
    assert!(!report.ai_used);
    assert!(!report.network_used);
    assert_eq!(user_visible_paths(repo), before_paths);
}

fn assert_success_suggestions(report: &TagSuggestionReport) {
    let finance = first_suggestion(report, "finance");
    assert_eq!(finance.source, TagSuggestionSource::Path);
    assert_eq!(finance.match_strength, TagSuggestionMatch::Strong);
    assert_eq!(finance.status, TagSuggestionStatus::NewTag);
    assert!(finance.already_exists);
    assert!(!finance.needs_create);
    assert!(finance.selected_by_default);

    let client = first_suggestion(report, "client-a");
    assert_eq!(client.status, TagSuggestionStatus::AlreadyAdded);
    assert!(!client.selected_by_default);
    assert_eq!(client.disabled_reason.as_deref(), Some("Already added"));
}

fn apply_success_suggestions(
    repo: &Path,
    file_id: i64,
    report: &TagSuggestionReport,
) -> TagSuggestionApplyReport {
    let finance = first_suggestion(report, "finance");
    let client = first_suggestion(report, "client-a");
    apply(
        repo,
        ApplyTagSuggestionsRequest {
            file_id,
            suggestions: vec![
                ApplyTagSuggestionItem {
                    suggestion_id: finance.suggestion_id.clone(),
                    slug: finance.slug.clone(),
                    display_name: "Finance".to_owned(),
                },
                ApplyTagSuggestionItem {
                    suggestion_id: client.suggestion_id.clone(),
                    slug: client.slug.clone(),
                    display_name: "Client A".to_owned(),
                },
            ],
        },
    )
    .expect("apply selected C2-19 suggestions")
}

fn assert_success_apply_report(report: &TagSuggestionApplyReport) -> &str {
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
            ("client-a", TagSuggestionApplyStatus::AlreadyAdded),
        ]
    );
    assert_eq!(
        report.refresh_targets,
        vec!["tags", "change_log", "undo_actions"]
    );
    let undo_token = report
        .undo_token
        .as_deref()
        .expect("new tag relation creates undo token");
    assert!(undo_token.starts_with("undo:tag-suggestions:"));
    undo_token
}

fn assert_ui_consumers_can_read_applied_tag(repo: &Path, file_id: i64, undo_token: &str) {
    let tag_set = list_tags(path_string(repo), file_id).expect("detail meta can read tags");
    assert_eq!(
        tag_set
            .file_tags
            .iter()
            .map(|record| record.value.as_str())
            .collect::<Vec<_>>(),
        vec!["client-a", "finance"]
    );

    let page = search_files(
        path_string(repo),
        String::new(),
        tag_search_filter("finance"),
        SearchSort::Relevance,
        SearchPagination {
            limit: 10,
            offset: 0,
        },
    )
    .expect("search and filter can read applied tag");
    assert!(page.results.iter().any(|result| result.entry.id == file_id));

    let changes =
        list_changes(path_string(repo), default_change_filter(file_id)).expect("list change log");
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].action, "external_modified");

    let undo_actions = list_undo_actions(path_string(repo)).expect("list undo actions");
    assert_eq!(undo_actions.len(), 1);
    assert_eq!(undo_actions[0].action_id, undo_token);
    assert!(undo_actions[0].can_undo);
}

#[test]
fn tag_suggestions_validation_locks_docs_api_udl_and_rust_surface() {
    assert_signatures();
    assert_c2_19_docs_api_udl_and_rust_are_aligned();
}

#[test]
fn tag_suggestions_validation_success_path_is_ready_for_ui_consumers() {
    let repo = initialized_repo();
    let file_id = insert_file(
        repo.path(),
        "finance/client-a_tax_report.pdf",
        "active",
        Some("/incoming/client-a_tax_report.pdf"),
    );
    let source_id = insert_file(repo.path(), "archive/client-a_invoice.pdf", "active", None);
    insert_tag(repo.path(), source_id, "finance", 100);
    insert_tag(repo.path(), source_id, "client-a", 110);
    insert_tag(repo.path(), file_id, "client-a", 120);
    let before_paths = user_visible_paths(repo.path());

    let suggestion_report =
        suggest(repo.path(), request_with_context(file_id)).expect("generate C2-19 suggestions");

    assert_suggestion_report_is_local_and_read_only(
        repo.path(),
        &suggestion_report,
        file_id,
        &before_paths,
    );
    assert_success_suggestions(&suggestion_report);

    let apply_report = apply_success_suggestions(repo.path(), file_id, &suggestion_report);
    let undo_token = assert_success_apply_report(&apply_report);
    assert_eq!(user_visible_paths(repo.path()), before_paths);

    assert_ui_consumers_can_read_applied_tag(repo.path(), file_id, undo_token);
}

#[test]
fn tag_suggestions_validation_failure_paths_do_not_leave_partial_state() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/client-a.pdf", "active", None);
    insert_tag(repo.path(), file_id, "baseline", 100);
    let before = snapshot(repo.path());

    assert_file_not_found(suggest(repo.path(), request_with_context(0)));
    assert_validation(suggest(
        repo.path(),
        TagSuggestionRequest {
            limit: 0,
            ..request_with_context(file_id)
        },
    ));
    assert_validation(suggest(
        repo.path(),
        TagSuggestionRequest {
            context: Some(TagSuggestionContext {
                source_folder: Some("https://remote.example".to_owned()),
                source_keywords: Vec::new(),
            }),
            ..request_with_context(file_id)
        },
    ));
    assert_file_not_found(apply(repo.path(), apply_request(0, "urgent")));
    assert_validation(apply(
        repo.path(),
        ApplyTagSuggestionsRequest {
            file_id,
            suggestions: Vec::new(),
        },
    ));
    assert_conflict(apply(
        repo.path(),
        ApplyTagSuggestionsRequest {
            file_id,
            suggestions: vec![
                ApplyTagSuggestionItem {
                    suggestion_id: "a".to_owned(),
                    slug: "Finance".to_owned(),
                    display_name: "Finance".to_owned(),
                },
                ApplyTagSuggestionItem {
                    suggestion_id: "b".to_owned(),
                    slug: "finance".to_owned(),
                    display_name: "Finance".to_owned(),
                },
            ],
        },
    ));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn tag_suggestions_validation_persistence_failures_are_observable_and_rollback_safe() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/apply.pdf", "active", None);
    insert_tag(repo.path(), file_id, "baseline", 100);
    install_tag_suggestion_change_log_failure(repo.path(), "blocked");

    let partial_report = apply(
        repo.path(),
        ApplyTagSuggestionsRequest {
            file_id,
            suggestions: vec![
                ApplyTagSuggestionItem {
                    suggestion_id: "validation:urgent".to_owned(),
                    slug: "urgent".to_owned(),
                    display_name: "Urgent".to_owned(),
                },
                ApplyTagSuggestionItem {
                    suggestion_id: "validation:blocked".to_owned(),
                    slug: "blocked".to_owned(),
                    display_name: "Blocked".to_owned(),
                },
            ],
        },
    )
    .expect("row-level change-log failure is returned as item failure");

    assert_eq!(partial_report.applied_count, 1);
    assert_eq!(partial_report.failed_count, 1);
    assert_eq!(
        partial_report.item_results[1].status,
        TagSuggestionApplyStatus::Failed
    );
    assert!(partial_report.item_results[1]
        .error
        .as_deref()
        .expect("failed item has error")
        .contains("Db"));
    assert_eq!(
        tag_rows(repo.path()),
        vec![
            (file_id, "baseline".to_owned()),
            (file_id, "urgent".to_owned())
        ]
    );
    assert_eq!(change_log_rows(repo.path()).len(), 1);
    assert_eq!(undo_action_rows(repo.path()).len(), 1);

    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/undo-failure.pdf", "active", None);
    insert_tag(repo.path(), file_id, "baseline", 100);
    let before = snapshot(repo.path());
    install_undo_failure(repo.path());

    assert_db_error(apply(
        repo.path(),
        apply_request_for(file_id, &["finance", "tax"]),
    ));

    assert_eq!(snapshot(repo.path()), before);
}
