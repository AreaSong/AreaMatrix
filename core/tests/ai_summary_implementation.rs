#[path = "support/ai_summary_common.rs"]
mod common;

use area_matrix_core::{
    clear_ai_summary, generate_ai_summary, save_ai_summary, AiSummaryClearRequest,
    AiSummaryContextPolicy, AiSummaryDraftStatus, AiSummaryGenerationRequest, AiSummaryInputField,
    AiSummaryProviderScope, AiSummaryRoute, AiSummarySaveRequest,
};
use common::{
    ai_call_log_count, ai_summary_row, change_log_kinds, enable_local_summaries,
    enable_remote_summaries, import_fixture, initialized_repo, path_string, AiSummaryRuntime,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

fn generation_request(file_id: i64) -> AiSummaryGenerationRequest {
    AiSummaryGenerationRequest {
        file_id,
        provider_scope: AiSummaryProviderScope::LocalPreferred,
        context_policy: AiSummaryContextPolicy::MetadataAndExtractedText,
        privacy_policy_ref: None,
        regenerate_existing: false,
    }
}

fn save_request(
    file_id: i64,
    summary_text: String,
    draft_id: Option<String>,
    call_log_id: Option<i64>,
) -> AiSummarySaveRequest {
    AiSummarySaveRequest {
        file_id,
        summary_text,
        draft_id,
        route: Some(AiSummaryRoute::Local),
        model_name: Some("areamatrix-local-summary".to_owned()),
        generated_at: Some(1_800_000_000),
        used_context: vec![
            AiSummaryInputField::FileName,
            AiSummaryInputField::RepoRelativePath,
            AiSummaryInputField::ExtractedTextExcerpt,
        ],
        privacy_rule_id: None,
        call_log_id,
        edited_by_user: true,
    }
}

#[test]
fn ai_summary_implementation_generates_draft_without_persisting_summary() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(
        repo.path(),
        "research-note.txt",
        "Research note with project context and no secret token=hidden.",
    );
    enable_local_summaries(repo.path());
    let runtime = AiSummaryRuntime::local("Short AI summary from local runtime.");

    let draft =
        generate_ai_summary(repo_path, generation_request(file_id)).expect("generate summary");
    let payload = runtime.captured_payload();

    assert_eq!(draft.status, AiSummaryDraftStatus::Draft);
    assert_eq!(
        draft.summary_text.as_deref(),
        Some("Short AI summary from local runtime.")
    );
    assert_eq!(draft.route, Some(AiSummaryRoute::Local));
    assert_eq!(
        draft.model_name.as_deref(),
        Some("areamatrix-local-summary")
    );
    assert!(draft.requires_user_save);
    assert_eq!(draft.character_count, 36);
    assert!(draft
        .draft_id
        .as_deref()
        .unwrap_or_default()
        .starts_with("draft:summary:"));
    assert!(draft.call_log_id.is_some());
    assert!(draft.used_context.contains(&AiSummaryInputField::FileName));
    assert!(draft
        .used_context
        .contains(&AiSummaryInputField::RepoRelativePath));
    assert!(draft
        .used_context
        .contains(&AiSummaryInputField::ExtractedTextExcerpt));
    assert!(payload.contains("\"feature\":\"summary\""));
    assert!(payload.contains("\"route\":\"local\""));
    assert!(payload.contains("Research note with project context"));
    assert!(!payload.contains("token=hidden"));
    assert!(ai_summary_row(repo.path(), file_id).is_none());
    assert_eq!(ai_call_log_count(repo.path()), 1);
}

#[test]
fn ai_summary_implementation_saves_and_clears_only_summary_metadata() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let readme = repo.path().join("README.md");
    std::fs::write(&readme, "user readme\n").expect("write user README");
    let file_id = import_fixture(repo.path(), "brief.txt", "Brief input for summary.");
    enable_local_summaries(repo.path());
    let _runtime = AiSummaryRuntime::local("Initial generated summary.");
    let draft = generate_ai_summary(repo_path.clone(), generation_request(file_id)).expect("draft");

    let report = save_ai_summary(
        repo_path.clone(),
        save_request(
            file_id,
            "Edited and saved summary.".to_owned(),
            draft.draft_id,
            draft.call_log_id,
        ),
    )
    .expect("save summary");

    assert_eq!(report.saved_summary, "Edited and saved summary.");
    assert_eq!(report.character_count, 25);
    assert_eq!(
        ai_summary_row(repo.path(), file_id).as_deref(),
        Some("Edited and saved summary.")
    );
    assert_eq!(
        std::fs::read_to_string(&readme).expect("read user README"),
        "user readme\n"
    );
    assert!(change_log_kinds(repo.path()).contains(&"ai_summary_saved".to_owned()));

    let clear = clear_ai_summary(
        repo_path,
        AiSummaryClearRequest {
            file_id,
            confirmed: true,
        },
    )
    .expect("clear summary");

    assert!(clear.cleared);
    assert!(ai_summary_row(repo.path(), file_id).is_none());
    assert_eq!(
        std::fs::read_to_string(&readme).expect("read user README after clear"),
        "user readme\n"
    );
    assert!(change_log_kinds(repo.path()).contains(&"ai_summary_cleared".to_owned()));
}

#[test]
fn ai_summary_implementation_executes_remote_route_after_provider_gates() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "remote.txt", "Remote summary eligible input.");
    enable_remote_summaries(repo.path(), "https://provider.example.test/summary");
    let runtime = AiSummaryRuntime::remote("Remote provider summary.");
    let mut request = generation_request(file_id);
    request.provider_scope = AiSummaryProviderScope::RemoteAllowed;

    let draft = generate_ai_summary(repo_path, request).expect("remote summary draft");
    let payload = runtime.captured_payload();

    assert_eq!(draft.status, AiSummaryDraftStatus::Draft);
    assert_eq!(draft.route, Some(AiSummaryRoute::Remote));
    assert_eq!(draft.model_name.as_deref(), Some("gpt-4.1-mini"));
    assert!(payload.contains("\"route\":\"remote\""));
    assert!(payload.contains("\"provider\":\"Other\""));
    assert!(payload.contains("\"key_reference\""));
    assert!(!payload.contains("summary-provider-secret"));
    assert!(ai_summary_row(repo.path(), file_id).is_none());
}

#[test]
fn ai_summary_implementation_replaces_existing_metadata_transactionally() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "replace.txt", "Replace summary input.");
    enable_local_summaries(repo.path());
    save_ai_summary(
        repo_path.clone(),
        save_request(file_id, "Original summary.".to_owned(), None, None),
    )
    .expect("seed summary");

    let connection =
        Connection::open(repo.path().join(".areamatrix/index.db")).expect("open database");
    connection
        .execute_batch(
            "CREATE TRIGGER fail_summary_replace
             BEFORE UPDATE ON ai_summaries
             BEGIN
               SELECT RAISE(ABORT, 'forced summary replacement failure');
             END;",
        )
        .expect("install summary failure trigger");
    drop(connection);

    let result = save_ai_summary(
        repo_path,
        save_request(file_id, "Replacement summary.".to_owned(), None, None),
    );

    assert!(result.is_err());
    assert_eq!(
        ai_summary_row(repo.path(), file_id).as_deref(),
        Some("Original summary.")
    );
}

#[test]
fn ai_summary_implementation_clearing_missing_summary_is_idempotent() {
    let repo = initialized_repo();
    let file_id = import_fixture(repo.path(), "clear-empty.txt", "No saved summary yet.");

    let report = clear_ai_summary(
        path_string(repo.path()),
        AiSummaryClearRequest {
            file_id,
            confirmed: true,
        },
    )
    .expect("clear absent summary");

    assert!(!report.cleared);
    assert!(ai_summary_row(repo.path(), file_id).is_none());
    assert!(change_log_kinds(repo.path())
        .into_iter()
        .all(|kind| kind != "ai_summary_cleared"));
}

#[test]
fn ai_summary_implementation_logs_runtime_failure_without_changing_summary() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "runtime.txt", "Runtime failure input.");
    enable_local_summaries(repo.path());
    let runtime = AiSummaryRuntime::failing_local();

    let draft =
        generate_ai_summary(repo_path, generation_request(file_id)).expect("fallback draft");
    let payload = runtime.captured_payload();

    assert_eq!(draft.status, AiSummaryDraftStatus::Unavailable);
    assert_eq!(draft.route, Some(AiSummaryRoute::Local));
    assert!(payload.contains("\"route\":\"local\""));
    assert!(ai_summary_row(repo.path(), file_id).is_none());

    let connection =
        Connection::open(repo.path().join(".areamatrix/index.db")).expect("open database");
    let status: String = connection
        .query_row(
            "SELECT status FROM ai_call_log WHERE id = ?1",
            params![draft.call_log_id.expect("failure has call log id")],
            |row| row.get(0),
        )
        .expect("read failure log");
    assert_eq!(status, "failed");
}
