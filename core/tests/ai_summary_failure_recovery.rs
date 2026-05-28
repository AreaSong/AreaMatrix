#[path = "support/ai_summary_common.rs"]
mod common;

use area_matrix_core::{
    clear_ai_summary, generate_ai_summary, save_ai_summary, AiSummaryClearRequest,
    AiSummaryContextPolicy, AiSummaryDraftStatus, AiSummaryGenerationRequest, AiSummaryInputField,
    AiSummaryProviderScope, AiSummaryRoute, AiSummarySaveRequest, CoreError,
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

fn clear_request(file_id: i64) -> AiSummaryClearRequest {
    AiSummaryClearRequest {
        file_id,
        confirmed: true,
    }
}

fn save_request(file_id: i64, summary_text: String) -> AiSummarySaveRequest {
    AiSummarySaveRequest {
        file_id,
        summary_text,
        draft_id: None,
        route: Some(AiSummaryRoute::Local),
        model_name: Some("areamatrix-local-summary".to_owned()),
        generated_at: Some(1_800_000_000),
        used_context: vec![
            AiSummaryInputField::FileName,
            AiSummaryInputField::RepoRelativePath,
        ],
        privacy_rule_id: None,
        call_log_id: None,
        edited_by_user: true,
    }
}

#[test]
fn default_ai_off_returns_skipped_without_runtime_or_summary_write() {
    let repo = initialized_repo();
    let file_id = import_fixture(repo.path(), "default-off.txt", "AI is off by default.");
    let repo_path = path_string(repo.path());

    let draft = generate_ai_summary(repo_path, generation_request(file_id)).expect("skip draft");

    assert_eq!(draft.status, AiSummaryDraftStatus::Skipped);
    assert!(draft.summary_text.is_none());
    assert!(draft.draft_id.is_none());
    assert!(draft.requires_user_save);
    assert!(ai_summary_row(repo.path(), file_id).is_none());
    assert_eq!(ai_call_log_count(repo.path()), 1);
}

#[test]
fn missing_file_id_maps_to_file_not_found_without_summary_side_effects() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    enable_local_summaries(repo.path());

    let generate = generate_ai_summary(repo_path.clone(), generation_request(9_999));
    let clear = clear_ai_summary(repo_path, clear_request(9_999));

    assert!(matches!(generate, Err(CoreError::FileNotFound { .. })));
    assert!(matches!(clear, Err(CoreError::FileNotFound { .. })));
    assert!(!table_exists(repo.path(), "ai_summaries"));
    assert!(!table_exists(repo.path(), "ai_call_log"));
}

#[test]
fn missing_repo_owned_context_file_maps_to_file_not_found() {
    let repo = initialized_repo();
    let file_id = import_fixture(repo.path(), "missing-context.txt", "Text to remove.");
    let stored_path = active_file_path(repo.path(), file_id);
    std::fs::remove_file(repo.path().join(stored_path)).expect("remove stored file");
    enable_local_summaries(repo.path());

    let result = generate_ai_summary(path_string(repo.path()), generation_request(file_id));

    assert!(matches!(result, Err(CoreError::FileNotFound { .. })));
    assert!(ai_summary_row(repo.path(), file_id).is_none());
}

#[test]
fn permission_denied_on_summary_metadata_does_not_write_partial_rows() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(
        repo.path(),
        "readonly-summary.txt",
        "Readonly metadata input.",
    );
    let db_path = repo.path().join(".areamatrix/index.db");
    let _guard = ReadOnlyGuard::new(&db_path);

    let result = save_ai_summary(
        repo_path,
        save_request(file_id, "Should not persist.".to_owned()),
    );

    assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
    assert!(ai_summary_row(repo.path(), file_id).is_none());
    assert!(change_log_kinds(repo.path())
        .into_iter()
        .all(|kind| kind != "ai_summary_saved"));
}

#[test]
fn failed_clear_rolls_back_existing_summary_and_change_log() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "clear-failure.txt", "Clear rollback input.");
    save_ai_summary(
        repo_path.clone(),
        save_request(file_id, "Existing summary.".to_owned()),
    )
    .expect("seed summary");
    install_abort_trigger(
        repo.path(),
        "fail_ai_summary_clear",
        "BEFORE DELETE ON ai_summaries",
    );

    let result = clear_ai_summary(repo_path, clear_request(file_id));

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        ai_summary_row(repo.path(), file_id).as_deref(),
        Some("Existing summary.")
    );
    assert!(change_log_kinds(repo.path())
        .into_iter()
        .all(|kind| kind != "ai_summary_cleared"));
}

#[test]
fn runtime_failure_records_sanitized_error_code_without_saving_summary() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "runtime-failure.txt", "Runtime failure input.");
    enable_local_summaries(repo.path());
    let _runtime = AiSummaryRuntime::failing_local();

    let draft =
        generate_ai_summary(repo_path, generation_request(file_id)).expect("unavailable draft");
    let row = call_log_row(repo.path(), draft.call_log_id.expect("call log id"));

    assert_eq!(draft.status, AiSummaryDraftStatus::Unavailable);
    assert_eq!(row.status, "failed");
    assert_eq!(row.error_code.as_deref(), Some("RuntimeFailed"));
    assert_eq!(
        row.result_summary,
        "AI summary local runtime is unavailable"
    );
    assert!(ai_summary_row(repo.path(), file_id).is_none());
}

#[test]
fn remote_summary_logs_never_include_secret_key_material() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "remote-log.txt", "Remote log input.");
    enable_remote_summaries(repo.path(), "https://provider.example.test/summary");
    let _runtime = AiSummaryRuntime::remote("Remote summary without secrets.");
    let mut request = generation_request(file_id);
    request.provider_scope = AiSummaryProviderScope::RemoteAllowed;

    let draft = generate_ai_summary(repo_path, request).expect("remote draft");
    let row = call_log_row(repo.path(), draft.call_log_id.expect("call log id"));
    let combined = format!(
        "{} {:?} {:?} {:?}",
        row.result_summary, row.provider, row.model, row.error_code
    );

    assert!(!combined.contains("summary-provider-secret"));
    assert!(!combined.contains("AREAMATRIX_AI_SUMMARY_TEST_KEY"));
    assert!(ai_summary_row(repo.path(), file_id).is_none());
}

struct CallLogRow {
    status: String,
    provider: Option<String>,
    model: Option<String>,
    result_summary: String,
    error_code: Option<String>,
}

fn call_log_row(repo: &std::path::Path, id: i64) -> CallLogRow {
    let connection = open_db(repo);
    connection
        .query_row(
            "SELECT status, provider, model, result_summary, error_code
             FROM ai_call_log WHERE id = ?1",
            params![id],
            |row| {
                Ok(CallLogRow {
                    status: row.get(0)?,
                    provider: row.get(1)?,
                    model: row.get(2)?,
                    result_summary: row.get(3)?,
                    error_code: row.get(4)?,
                })
            },
        )
        .expect("read AI call log row")
}

fn active_file_path(repo: &std::path::Path, file_id: i64) -> String {
    let connection = open_db(repo);
    connection
        .query_row(
            "SELECT path FROM files WHERE id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .expect("read active file path")
}

fn table_exists(repo: &std::path::Path, table: &str) -> bool {
    let connection = open_db(repo);
    connection
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            params![table],
            |_| Ok(true),
        )
        .unwrap_or(false)
}

fn install_abort_trigger(repo: &std::path::Path, name: &str, timing: &str) {
    let connection = open_db(repo);
    connection
        .execute_batch(&format!(
            "CREATE TRIGGER {name}
             {timing}
             BEGIN
               SELECT RAISE(ABORT, 'forced AI summary failure');
             END;"
        ))
        .expect("install abort trigger");
}

fn open_db(repo: &std::path::Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

#[cfg(unix)]
struct ReadOnlyGuard {
    path: std::path::PathBuf,
    original_mode: u32,
}

#[cfg(unix)]
impl ReadOnlyGuard {
    fn new(path: &std::path::Path) -> Self {
        use std::os::unix::fs::PermissionsExt;

        let metadata = std::fs::metadata(path).expect("read DB metadata");
        let original_mode = metadata.permissions().mode();
        let mut permissions = metadata.permissions();
        permissions.set_mode(0o444);
        std::fs::set_permissions(path, permissions).expect("make DB readonly");
        Self {
            path: path.to_path_buf(),
            original_mode,
        }
    }
}

#[cfg(unix)]
impl Drop for ReadOnlyGuard {
    fn drop(&mut self) {
        use std::os::unix::fs::PermissionsExt;

        let mut permissions = std::fs::metadata(&self.path)
            .expect("read DB metadata")
            .permissions();
        permissions.set_mode(self.original_mode);
        std::fs::set_permissions(&self.path, permissions).expect("restore DB permissions");
    }
}

#[cfg(not(unix))]
struct ReadOnlyGuard;

#[cfg(not(unix))]
impl ReadOnlyGuard {
    fn new(_path: &std::path::Path) -> Self {
        Self
    }
}
