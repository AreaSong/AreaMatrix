use std::fs;

use area_matrix_core::{
    apply_tag_suggestions, map_core_error, suggest_tags_for_file, ApplyTagSuggestionItem,
    ApplyTagSuggestionsRequest, ErrorKind, ErrorMappingInput, ErrorRecoverability,
    TagSuggestionApplyStatus, TagSuggestionContext, TagSuggestionRequest, TagSuggestionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::params;

#[path = "support/tag_suggestions_failure.rs"]
mod tag_suggestions_failure;

use tag_suggestions_failure::{
    apply, apply_request, assert_conflict, assert_db_error, assert_file_not_found,
    assert_validation, change_log_rows, initialized_repo, insert_file, insert_tag,
    install_tag_suggestion_change_log_failure, install_undo_failure, open_db, path_string,
    relative_directory_entries, request, snapshot, suggest, tag_rows, undo_action_rows,
    user_visible_paths,
};

#[test]
fn tag_suggestions_failure_recovery_empty_state_is_explicit_and_read_only() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/untagged.pdf", "active", None);
    let before = snapshot(repo.path());

    let report = suggest(repo.path(), request(file_id))
        .expect("empty tag registry still returns deterministic suggestions");

    assert_eq!(report.file_id, file_id);
    assert!(!report.suggestions.is_empty());
    assert!(report.tag_set.file_tags.is_empty());
    assert!(report.tag_set.available_tags.is_empty());
    assert!(report.tag_set.recent_tags.is_empty());
    assert!(!report.contents_read);
    assert!(!report.ai_used);
    assert!(!report.network_used);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn tag_suggestions_failure_recovery_invalid_suggest_inputs_do_not_mutate() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/tagged.pdf", "active", None);
    insert_tag(repo.path(), file_id, "baseline", 100);
    let before = snapshot(repo.path());

    assert_db_error(suggest_tags_for_file(String::new(), request(file_id)));
    assert_db_error(suggest_tags_for_file(
        path_string(&repo.path().join(".areamatrix")),
        request(file_id),
    ));
    assert_file_not_found(suggest(repo.path(), request(0)));
    assert_validation(suggest(
        repo.path(),
        TagSuggestionRequest {
            limit: 0,
            ..request(file_id)
        },
    ));
    assert_validation(suggest(
        repo.path(),
        TagSuggestionRequest {
            context: Some(TagSuggestionContext {
                source_folder: Some("https://remote.example".to_owned()),
                source_keywords: Vec::new(),
            }),
            ..request(file_id)
        },
    ));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn tag_suggestions_failure_recovery_invalid_apply_inputs_do_not_mutate() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/tagged.pdf", "active", None);
    insert_tag(repo.path(), file_id, "baseline", 100);
    let before = snapshot(repo.path());

    assert_db_error(apply_tag_suggestions(
        String::new(),
        apply_request(file_id, "urgent"),
    ));
    assert_db_error(apply_tag_suggestions(
        path_string(&repo.path().join(".areamatrix")),
        apply_request(file_id, "urgent"),
    ));
    assert_file_not_found(apply(repo.path(), apply_request(0, "urgent")));
    assert_validation(apply(
        repo.path(),
        ApplyTagSuggestionsRequest {
            file_id,
            suggestions: Vec::new(),
        },
    ));
    assert_validation(apply(repo.path(), apply_request(file_id, "bad/tag")));
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
fn tag_suggestions_failure_recovery_missing_deleted_and_conflicting_metadata_are_explicit() {
    let repo = initialized_repo();
    let active_id = insert_file(repo.path(), "docs/active.pdf", "active", None);
    let deleted_id = insert_file(repo.path(), "docs/deleted.pdf", "deleted", None);
    let blank_id = insert_file(repo.path(), "docs/blank.pdf", "active", None);
    open_db(repo.path())
        .execute(
            "UPDATE files SET current_name = '' WHERE id = ?1",
            params![blank_id],
        )
        .expect("make active metadata nondeterministic");
    let before = snapshot(repo.path());

    assert_file_not_found(suggest(repo.path(), request(deleted_id)));
    assert_file_not_found(suggest(repo.path(), request(404)));
    assert_conflict(suggest(repo.path(), request(blank_id)));
    assert_file_not_found(apply(repo.path(), apply_request(deleted_id, "urgent")));
    assert_file_not_found(apply(repo.path(), apply_request(404, "urgent")));

    let active = suggest(repo.path(), request(active_id)).expect("active metadata remains usable");
    assert!(active
        .suggestions
        .iter()
        .all(|suggestion| suggestion.status != TagSuggestionStatus::Invalid));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn tag_suggestions_failure_recovery_item_db_failure_rolls_back_item_only() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/client-a.pdf", "active", None);
    insert_tag(repo.path(), file_id, "baseline", 100);
    install_tag_suggestion_change_log_failure(repo.path(), "blocked");
    let before_paths = user_visible_paths(repo.path());

    let report = apply(repo.path(), two_item_apply_request(file_id))
        .expect("row-level DB failure returns explicit failed item");

    assert_eq!(report.requested_count, 2);
    assert_eq!(report.applied_count, 1);
    assert_eq!(report.skipped_count, 0);
    assert_eq!(report.failed_count, 1);
    assert_eq!(
        report.item_results[0].status,
        TagSuggestionApplyStatus::Applied
    );
    assert_eq!(
        report.item_results[1].status,
        TagSuggestionApplyStatus::Failed
    );
    assert!(report.item_results[1]
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
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

fn two_item_apply_request(file_id: i64) -> ApplyTagSuggestionsRequest {
    ApplyTagSuggestionsRequest {
        file_id,
        suggestions: vec![
            ApplyTagSuggestionItem {
                suggestion_id: "suggestion:test:urgent".to_owned(),
                slug: "urgent".to_owned(),
                display_name: "Urgent".to_owned(),
            },
            ApplyTagSuggestionItem {
                suggestion_id: "suggestion:test:blocked".to_owned(),
                slug: "blocked".to_owned(),
                display_name: "Blocked".to_owned(),
            },
        ],
    }
}

#[test]
fn tag_suggestions_failure_recovery_undo_failure_rolls_back_entire_apply() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/apply.pdf", "active", None);
    insert_tag(repo.path(), file_id, "baseline", 100);
    let before = snapshot(repo.path());
    install_undo_failure(repo.path());

    assert_db_error(apply(repo.path(), apply_request(file_id, "urgent")));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn tag_suggestions_failure_recovery_missing_metadata_tables_return_db_without_partial_writes() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/source.pdf", "active", None);
    let before_paths = user_visible_paths(repo.path());
    open_db(repo.path())
        .execute_batch("DROP TABLE tags;")
        .expect("drop tags table to simulate metadata corruption");

    let suggest_error = assert_db_error(suggest(repo.path(), request(file_id)));
    assert_eq!(
        suggest_error.to_error_mapping().recoverability,
        ErrorRecoverability::Fatal
    );
    assert_eq!(user_visible_paths(repo.path()), before_paths);

    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/source.pdf", "active", None);
    let before_apply_paths = user_visible_paths(repo.path());
    open_db(repo.path())
        .execute_batch("DROP TABLE undo_actions;")
        .expect("drop undo table to simulate apply metadata corruption");

    let apply_error = assert_db_error(apply(repo.path(), apply_request(file_id, "urgent")));

    assert_eq!(
        apply_error.to_error_mapping().recoverability,
        ErrorRecoverability::Fatal
    );
    assert_eq!(tag_rows(repo.path()), Vec::<(i64, String)>::new());
    assert_eq!(
        change_log_rows(repo.path()),
        Vec::<(i64, String, String)>::new()
    );
    assert_eq!(user_visible_paths(repo.path()), before_apply_paths);
}

#[cfg(unix)]
#[test]
fn tag_suggestions_failure_recovery_permission_denied_is_db_error_and_non_mutating() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "docs/locked.pdf", "active", None);
    insert_tag(repo.path(), file_id, "baseline", 100);
    let before = snapshot(repo.path());
    let db_path = repo.path().join(".areamatrix/index.db");
    let original_permissions = fs::metadata(&db_path)
        .expect("read database permissions")
        .permissions();
    let mut denied_permissions = original_permissions.clone();
    denied_permissions.set_mode(0o000);
    fs::set_permissions(&db_path, denied_permissions).expect("remove database permissions");

    if fs::File::open(&db_path).is_ok() {
        fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");
        return;
    }

    let suggest_result = suggest(repo.path(), request(file_id));
    let apply_result = apply(repo.path(), apply_request(file_id, "blocked"));

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");

    assert_db_error(suggest_result);
    assert_db_error(apply_result);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn tag_suggestions_failure_recovery_preserves_user_files_and_avoids_remote_ai_state() {
    let repo = initialized_repo();
    let file_id = insert_file(
        repo.path(),
        "finance/local.pdf",
        "active",
        Some("/incoming/finance/local.pdf"),
    );
    let user_file = repo.path().join("finance/local.pdf");
    let before_paths = user_visible_paths(repo.path());
    let before_staging =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging"));
    let before_generated =
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated"));

    assert_local_privacy_report(file_id, repo.path());
    let apply_report = apply(repo.path(), apply_request(file_id, "finance"))
        .expect("apply one local tag suggestion");

    assert_eq!(apply_report.applied_count, 1);
    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert_eq!(
        fs::read(user_file).expect("read user file"),
        b"fixture bytes for finance/local.pdf"
    );
    assert_eq!(user_visible_paths(repo.path()), before_paths);
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging")),
        before_staging
    );
    assert_eq!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/generated")),
        before_generated
    );
}

fn assert_local_privacy_report(file_id: i64, repo: &std::path::Path) {
    let report = suggest(repo, request(file_id)).expect("suggest local tags without remote AI");
    assert!(!report.contents_read);
    assert!(!report.ai_used);
    assert!(!report.network_used);
}

#[test]
fn tag_suggestions_failure_recovery_error_mapping_covers_documented_kinds() {
    let cases = [
        (
            ErrorKind::FileNotFound,
            ErrorRecoverability::RefreshRequired,
        ),
        (
            ErrorKind::Validation,
            ErrorRecoverability::UserActionRequired,
        ),
        (ErrorKind::Conflict, ErrorRecoverability::UserActionRequired),
        (ErrorKind::Db, ErrorRecoverability::UserActionRequired),
        (
            ErrorKind::PermissionDenied,
            ErrorRecoverability::UserActionRequired,
        ),
    ];

    for (kind, recoverability) in cases {
        let mapping = map_core_error(ErrorMappingInput {
            kind: kind.clone(),
            path: Some("file:42".to_owned()),
            reason: Some("invalid tag suggestion".to_owned()),
            message: Some("tag suggestion metadata failed".to_owned()),
        });
        assert_eq!(mapping.kind, kind);
        assert_eq!(mapping.recoverability, recoverability);
        assert!(!mapping.user_message.is_empty());
        assert!(!mapping.suggested_action.is_empty());
    }
}
