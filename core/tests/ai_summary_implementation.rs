#[path = "support/ai_summary_common.rs"]
mod common;

use area_matrix_core::{
    clear_ai_summary, generate_ai_summary, save_ai_summary, AiContentOwnership,
    AiSummaryClearRequest, AiSummaryContextPolicy, AiSummaryDraftStatus,
    AiSummaryGenerationRequest, AiSummaryInputField, AiSummaryProviderScope, AiSummaryRoute,
    AiSummarySaveRequest,
};
use common::{
    ai_call_log_count, ai_summary_row, change_log_kinds, enable_local_summaries,
    enable_remote_summaries, import_fixture, initialized_repo, path_string, AiSummaryRuntime,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

fn generation_request(file_id: i64) -> AiSummaryGenerationRequest {
    AiSummaryGenerationRequest {
        operation_id: uuid::Uuid::new_v4().to_string(),
        retry_of_operation_id: None,
        file_id,
        provider_scope: AiSummaryProviderScope::LocalPreferred,
        context_policy: AiSummaryContextPolicy::MetadataAndExtractedText,
        privacy_policy_ref: None,
        regenerate_existing: false,
        content_locale: area_matrix_core::ContentLocale::En,
    }
}

fn save_request(
    file_id: i64,
    summary_text: String,
    draft_id: Option<String>,
    call_log_id: Option<i64>,
    operation_id: String,
    expected_content_revision: i64,
    confirm_replace_user_owned: bool,
) -> AiSummarySaveRequest {
    AiSummarySaveRequest {
        file_id,
        expected_content_revision,
        confirm_replace_user_owned,
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
        ownership: AiContentOwnership::UserOwned,
        operation_id,
        content_locale: area_matrix_core::ContentLocale::En,
        format_contract_version: 1,
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
            draft.operation_id,
            0,
            false,
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
            expected_content_revision: report.content_revision,
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
    let _runtime = AiSummaryRuntime::local("Original generated summary.");
    let first_draft = generate_ai_summary(repo_path.clone(), generation_request(file_id))
        .expect("generate first draft");
    let first_report = save_ai_summary(
        repo_path.clone(),
        save_request(
            file_id,
            "Original summary.".to_owned(),
            first_draft.draft_id,
            first_draft.call_log_id,
            first_draft.operation_id,
            0,
            false,
        ),
    )
    .expect("seed summary");
    drop(_runtime);

    let _replacement_runtime = AiSummaryRuntime::local("Replacement generated summary.");
    let mut replacement_request = generation_request(file_id);
    replacement_request.regenerate_existing = true;
    let replacement_draft = generate_ai_summary(repo_path.clone(), replacement_request)
        .expect("generate replacement draft");

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
        save_request(
            file_id,
            "Replacement summary.".to_owned(),
            replacement_draft.draft_id,
            replacement_draft.call_log_id,
            replacement_draft.operation_id,
            first_report.content_revision,
            true,
        ),
    );

    assert!(result.is_err());
    assert_eq!(
        ai_summary_row(repo.path(), file_id).as_deref(),
        Some("Original summary.")
    );
}

#[test]
fn ai_summary_implementation_clear_absent_summary_creates_tombstone_revision() {
    let repo = initialized_repo();
    let file_id = import_fixture(repo.path(), "clear-empty.txt", "No saved summary yet.");

    let report = clear_ai_summary(
        path_string(repo.path()),
        AiSummaryClearRequest {
            file_id,
            expected_content_revision: 0,
            confirmed: true,
        },
    )
    .expect("clear absent summary");

    assert!(!report.cleared);
    assert_eq!(report.content_revision, 1);
    assert!(ai_summary_row(repo.path(), file_id).is_none());
    assert!(change_log_kinds(repo.path()).contains(&"ai_summary_cleared".to_owned()));
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

#[test]
fn ai_summary_implementation_enforces_ownership_cas_and_tombstone_history() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "ownership.txt", "Ownership transition input.");
    enable_local_summaries(repo.path());

    let first_runtime = AiSummaryRuntime::local("First generated summary.");
    let first_draft = generate_ai_summary(repo_path.clone(), generation_request(file_id))
        .expect("generate first ownership draft");
    drop(first_runtime);

    let mut generated_request = save_request(
        file_id,
        "First generated summary.".to_owned(),
        first_draft.draft_id.clone(),
        first_draft.call_log_id,
        first_draft.operation_id.clone(),
        0,
        false,
    );
    generated_request.ownership = AiContentOwnership::Generated;
    let generated = save_ai_summary(repo_path.clone(), generated_request)
        .expect("save generated-owned summary");
    assert_eq!(generated.content_revision, 1);
    assert_eq!(generated.ownership, AiContentOwnership::Generated);

    let user_owned = save_ai_summary(
        repo_path.clone(),
        save_request(
            file_id,
            "User edited summary.".to_owned(),
            first_draft.draft_id,
            first_draft.call_log_id,
            first_draft.operation_id,
            generated.content_revision,
            false,
        ),
    )
    .expect("transition generated summary to user ownership");
    assert_eq!(user_owned.content_revision, 2);
    assert_eq!(user_owned.ownership, AiContentOwnership::UserOwned);

    let replacement_runtime = AiSummaryRuntime::local("Replacement provider draft.");
    let mut replacement_generation = generation_request(file_id);
    replacement_generation.regenerate_existing = true;
    let replacement_draft = generate_ai_summary(repo_path.clone(), replacement_generation)
        .expect("generate replacement ownership draft");
    drop(replacement_runtime);
    let tombstone_operation_id = replacement_draft.operation_id.clone();

    let without_confirmation = save_ai_summary(
        repo_path.clone(),
        save_request(
            file_id,
            "Unconfirmed replacement.".to_owned(),
            replacement_draft.draft_id.clone(),
            replacement_draft.call_log_id,
            replacement_draft.operation_id.clone(),
            user_owned.content_revision,
            false,
        ),
    );
    assert!(matches!(
        without_confirmation,
        Err(area_matrix_core::CoreError::Conflict { .. })
    ));
    assert_eq!(ai_summary_revision(repo.path(), file_id), 2);
    assert_eq!(
        ai_summary_row(repo.path(), file_id).as_deref(),
        Some("User edited summary.")
    );

    let mut downgrade_request = save_request(
        file_id,
        "Generated downgrade.".to_owned(),
        replacement_draft.draft_id.clone(),
        replacement_draft.call_log_id,
        replacement_draft.operation_id.clone(),
        user_owned.content_revision,
        true,
    );
    downgrade_request.ownership = AiContentOwnership::Generated;
    let downgrade = save_ai_summary(repo_path.clone(), downgrade_request);
    assert!(matches!(
        downgrade,
        Err(area_matrix_core::CoreError::Conflict { .. })
    ));
    assert_eq!(ai_summary_revision(repo.path(), file_id), 2);

    let replaced = save_ai_summary(
        repo_path.clone(),
        save_request(
            file_id,
            "Confirmed user-owned replacement.".to_owned(),
            replacement_draft.draft_id,
            replacement_draft.call_log_id,
            replacement_draft.operation_id,
            user_owned.content_revision,
            true,
        ),
    )
    .expect("replace user-owned summary after confirmation");
    assert_eq!(replaced.content_revision, 3);

    let stale_clear = clear_ai_summary(
        repo_path.clone(),
        AiSummaryClearRequest {
            file_id,
            expected_content_revision: user_owned.content_revision,
            confirmed: true,
        },
    );
    assert!(matches!(
        stale_clear,
        Err(area_matrix_core::CoreError::RevisionConflict {
            resource,
            expected_revision: 2,
            current_revision: 3,
        }) if resource == "ai_summary_content_revision"
    ));
    assert_eq!(ai_summary_revision(repo.path(), file_id), 3);

    let cleared = clear_ai_summary(
        repo_path.clone(),
        AiSummaryClearRequest {
            file_id,
            expected_content_revision: replaced.content_revision,
            confirmed: true,
        },
    )
    .expect("clear latest user-owned summary");
    assert_eq!(cleared.content_revision, 4);
    assert!(ai_summary_row(repo.path(), file_id).is_none());

    let stale_after_tombstone = save_ai_summary(
        repo_path,
        save_request(
            file_id,
            "Stale resurrection.".to_owned(),
            None,
            None,
            tombstone_operation_id,
            0,
            false,
        ),
    );
    assert!(matches!(
        stale_after_tombstone,
        Err(area_matrix_core::CoreError::RevisionConflict {
            resource,
            expected_revision: 0,
            current_revision: 4,
        }) if resource == "ai_summary_content_revision"
    ));
    assert_eq!(ai_summary_revision(repo.path(), file_id), 4);
    assert!(ai_summary_row(repo.path(), file_id).is_none());
}

#[test]
fn ai_summary_implementation_rejects_forged_operation_provenance_without_writes() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "forged.txt", "Forged provenance input.");

    let result = save_ai_summary(
        repo_path,
        save_request(
            file_id,
            "Forged summary.".to_owned(),
            None,
            None,
            uuid::Uuid::new_v4().to_string(),
            0,
            false,
        ),
    );

    assert!(matches!(
        result,
        Err(area_matrix_core::CoreError::Conflict { .. })
    ));
    assert_eq!(ai_summary_revision(repo.path(), file_id), 0);
    assert!(ai_summary_row(repo.path(), file_id).is_none());
}

fn ai_summary_revision(repo: &std::path::Path, file_id: i64) -> i64 {
    let connection = Connection::open(repo.join(".areamatrix/index.db"))
        .expect("open database for AI summary revision");
    connection
        .query_row(
            "SELECT content_revision FROM ai_summary_revisions WHERE file_id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .unwrap_or(0)
}
