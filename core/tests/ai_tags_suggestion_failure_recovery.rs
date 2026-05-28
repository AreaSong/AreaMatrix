#[path = "support/ai_tags_suggestion_common.rs"]
mod common;
#[path = "support/ai_tags_suggestion_failure.rs"]
mod failure;

use area_matrix_core::{
    apply_ai_tag_suggestions, map_core_error, suggest_tags_with_ai, AiTagSuggestionApplyStatus,
    AiTagSuggestionReportStatus, AiTagSuggestionRoute, AiTagSuggestionSkipReason,
    ApplyAiTagSuggestionItem, ApplyAiTagSuggestionsRequest, ErrorKind, ErrorMappingInput,
    ErrorRecoverability, ErrorSeverity,
};
use common::{AiTagsRuntime, RuntimeSuggestion};
use failure::{
    ai_call_log_count, ai_call_log_text, apply_request, assert_kind, assert_no_secret_material,
    change_log_kinds, enable_local_tags, enable_remote_tags, import_fixture, initialized_repo,
    install_ai_tag_apply_log_failure, install_ai_tag_change_log_failure,
    install_ai_tag_undo_failure, open_db, path_string, request, snapshot, tag_rows,
    undo_action_count, user_visible_paths,
};
use pretty_assertions::assert_eq;

#[test]
fn ai_tags_failure_default_off_returns_skipped_without_runtime_or_tag_write() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "default-off.txt", "AI tags off by default.");
    let runtime = AiTagsRuntime::probe();
    let before = snapshot(repo.path());

    let report = suggest_tags_with_ai(repo_path, request(file_id)).expect("default off report");

    assert_eq!(report.status, AiTagSuggestionReportStatus::Skipped);
    assert_eq!(
        report.skipped_reason,
        Some(AiTagSuggestionSkipReason::AiDisabled)
    );
    assert!(report.suggestions.is_empty());
    assert!(!report.ai_used);
    assert!(!report.network_used);
    assert!(!runtime.was_invoked());
    assert_eq!(snapshot(repo.path()), before);
    assert_eq!(ai_call_log_count(repo.path()), 1);
}

#[test]
fn ai_tags_failure_empty_runtime_result_is_explicit_no_suggestion_and_read_only() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "empty-tags.txt", "No useful label.");
    enable_local_tags(repo.path());
    let _runtime = AiTagsRuntime::local(Vec::new());
    let before = snapshot(repo.path());

    let report = suggest_tags_with_ai(repo_path, request(file_id)).expect("empty report");

    assert_eq!(report.status, AiTagSuggestionReportStatus::NoSuggestion);
    assert!(report.suggestions.is_empty());
    assert!(report.requires_user_confirmation);
    assert!(report.ai_used);
    assert!(!report.network_used);
    assert_eq!(tag_rows(repo.path()), before.tags);
    assert_eq!(
        snapshot(repo.path()).user_visible_paths,
        before.user_visible_paths
    );
}

#[test]
fn ai_tags_failure_invalid_inputs_map_to_documented_errors_without_writes() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invalid-inputs.txt", "Input checks.");
    enable_local_tags(repo.path());
    let before = snapshot(repo.path());

    let mut missing_file = request(0);
    assert_kind(
        suggest_tags_with_ai(repo_path.clone(), missing_file.clone()),
        ErrorKind::FileNotFound,
    );
    missing_file.file_id = file_id;
    missing_file.candidate_tags = vec!["bad/tag".to_owned()];
    assert_kind(
        suggest_tags_with_ai(repo_path.clone(), missing_file),
        ErrorKind::Config,
    );

    let mut secret_ref = request(file_id);
    secret_ref.privacy_policy_ref = Some("sk-secret-key".to_owned());
    assert_kind(
        suggest_tags_with_ai(repo_path.clone(), secret_ref),
        ErrorKind::Config,
    );

    let mut unconfirmed = apply_request(file_id, "finance");
    unconfirmed.confirmed = false;
    assert_kind(
        apply_ai_tag_suggestions(repo_path.clone(), unconfirmed),
        ErrorKind::Config,
    );

    let mut invalid_slug = apply_request(file_id, "bad/tag");
    invalid_slug.suggestions[0].display_name = "bad/tag".to_owned();
    assert_kind(
        apply_ai_tag_suggestions(repo_path.clone(), invalid_slug),
        ErrorKind::Config,
    );

    let mut duplicate = apply_request(file_id, "finance");
    duplicate.suggestions.push(ApplyAiTagSuggestionItem {
        suggestion_id: "ai-tag:finance-copy".to_owned(),
        ..duplicate.suggestions[0].clone()
    });
    assert_kind(
        apply_ai_tag_suggestions(repo_path, duplicate),
        ErrorKind::Config,
    );

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn ai_tags_failure_missing_file_and_db_corruption_are_explicit_and_non_mutating() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "db-errors.txt", "DB failure input.");
    enable_local_tags(repo.path());
    let before_paths = user_visible_paths(repo.path());

    assert_kind(
        suggest_tags_with_ai(repo_path.clone(), request(file_id + 9_999)),
        ErrorKind::FileNotFound,
    );
    assert_kind(
        apply_ai_tag_suggestions(repo_path.clone(), apply_request(file_id + 9_999, "finance")),
        ErrorKind::FileNotFound,
    );

    open_db(repo.path())
        .execute_batch("DROP TABLE tags;")
        .expect("drop tags table");
    let error = assert_kind(
        suggest_tags_with_ai(repo_path, request(file_id)),
        ErrorKind::Db,
    );

    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::Fatal
    );
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[cfg(unix)]
#[test]
fn ai_tags_failure_permission_denied_is_preserved_and_non_mutating() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "permission.txt", "Permission input.");
    enable_local_tags(repo.path());
    let before = snapshot(repo.path());
    let db_path = repo.path().join(".areamatrix/index.db");
    let _guard = failure::ReadOnlyGuard::new(&db_path);

    let error = apply_ai_tag_suggestions(repo_path, apply_request(file_id, "finance"))
        .expect_err("readonly metadata must fail");

    assert_eq!(error.kind(), ErrorKind::PermissionDenied);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn ai_tags_failure_privacy_skip_does_not_call_provider_or_leak_keys() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "private.txt", "Private AI tag input.");
    enable_local_tags(repo.path());
    let runtime = AiTagsRuntime::probe();
    let mut blocked = request(file_id);
    blocked.privacy_policy_ref = Some("private-folder".to_owned());
    let before = snapshot(repo.path());

    let report = suggest_tags_with_ai(repo_path, blocked).expect("privacy skip");

    assert_eq!(report.status, AiTagSuggestionReportStatus::Skipped);
    assert_eq!(
        report.skipped_reason,
        Some(AiTagSuggestionSkipReason::PrivacyRule)
    );
    assert!(!report.ai_used);
    assert!(!report.network_used);
    assert!(!runtime.was_invoked());
    assert_eq!(snapshot(repo.path()), before);
    assert_no_secret_material(&ai_call_log_text(repo.path()));
}

#[test]
fn ai_tags_failure_remote_logs_are_sanitized_and_never_persist_key_material() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "remote.txt", "Remote AI tag input.");
    enable_remote_tags(repo.path());
    let _runtime = AiTagsRuntime::remote(vec![RuntimeSuggestion::new(
        "finance",
        "Finance",
        0.92,
        "remote suggestion token=hidden",
    )]);

    let report = suggest_tags_with_ai(repo_path, request(file_id)).expect("remote suggestion");

    assert_eq!(report.route, Some(AiTagSuggestionRoute::Remote));
    assert!(report.network_used);
    assert!(report.ai_used);
    assert!(report.suggestions[0].reason.contains("remote suggestion"));
    assert_no_secret_material(&report.suggestions[0].reason);
    assert_no_secret_material(&ai_call_log_text(repo.path()));
    assert_no_secret_material(
        &serde_json::to_string(&report).expect("serialize report for secret scan"),
    );
}

#[test]
fn ai_tags_failure_item_db_failure_rolls_back_failed_item_only_and_keeps_user_files() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "partial-apply.txt", "Partial apply.");
    install_ai_tag_change_log_failure(repo.path(), "blocked");
    let before_paths = user_visible_paths(repo.path());

    let report = apply_ai_tag_suggestions(
        repo_path,
        ApplyAiTagSuggestionsRequest {
            file_id,
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
                    suggestion_id: "ai-tag:blocked".to_owned(),
                    slug: "blocked".to_owned(),
                    display_name: "Blocked".to_owned(),
                    confidence: 0.91,
                    edited_by_user: true,
                    merge_target_slug: None,
                },
            ],
            call_log_id: None,
            privacy_rule_id: None,
            confirmed: true,
        },
    )
    .expect("partial failure report");

    assert_eq!(report.requested_count, 2);
    assert_eq!(report.applied_count, 1);
    assert_eq!(report.failed_count, 1);
    assert_eq!(
        report.item_results[0].status,
        AiTagSuggestionApplyStatus::Applied
    );
    assert_eq!(
        report.item_results[1].status,
        AiTagSuggestionApplyStatus::Failed
    );
    assert!(report.item_results[1]
        .error
        .as_deref()
        .expect("failed item has error")
        .contains("Db"));
    assert_eq!(tag_rows(repo.path()), vec!["finance"]);
    assert_eq!(
        change_log_kinds(repo.path())
            .into_iter()
            .filter(|kind| kind == "ai_tag_suggestion_applied")
            .count(),
        1
    );
    assert_eq!(undo_action_count(repo.path()), 1);
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[test]
fn ai_tags_failure_undo_or_call_log_failure_rolls_back_entire_apply() {
    let undo_repo = initialized_repo();
    let undo_file_id = import_fixture(undo_repo.path(), "undo-failure.txt", "Undo failure.");
    let before_undo = snapshot(undo_repo.path());
    install_ai_tag_undo_failure(undo_repo.path());

    assert_kind(
        apply_ai_tag_suggestions(
            path_string(undo_repo.path()),
            apply_request(undo_file_id, "finance"),
        ),
        ErrorKind::Db,
    );
    assert_eq!(snapshot(undo_repo.path()), before_undo);

    let log_repo = initialized_repo();
    let log_file_id = import_fixture(log_repo.path(), "log-failure.txt", "Log failure.");
    let before_log = snapshot(log_repo.path());
    install_ai_tag_apply_log_failure(log_repo.path());

    assert_kind(
        apply_ai_tag_suggestions(
            path_string(log_repo.path()),
            apply_request(log_file_id, "audit"),
        ),
        ErrorKind::Db,
    );
    assert_eq!(snapshot(log_repo.path()), before_log);
}

#[test]
fn ai_tags_failure_error_mapping_matches_documented_failure_codes() {
    for (kind, severity, recoverability) in [
        (
            ErrorKind::Config,
            ErrorSeverity::Medium,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::FileNotFound,
            ErrorSeverity::Low,
            ErrorRecoverability::RefreshRequired,
        ),
        (
            ErrorKind::Db,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::PermissionDenied,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::Io,
            ErrorSeverity::Medium,
            ErrorRecoverability::Retryable,
        ),
    ] {
        let mapping = map_core_error(ErrorMappingInput {
            kind: kind.clone(),
            path: Some("metadata".to_owned()),
            reason: Some("AI tag suggestion failure edge".to_owned()),
            message: Some("AI tag suggestion metadata failure".to_owned()),
        });
        assert_eq!(mapping.kind, kind);
        assert_eq!(mapping.severity, severity);
        assert_eq!(mapping.recoverability, recoverability);
        assert_no_secret_material(&mapping.raw_context);
    }
}
