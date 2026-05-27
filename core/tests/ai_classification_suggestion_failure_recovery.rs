use std::{fs, path::Path};

use area_matrix_core::{
    import_file, init_repo, list_files, map_core_error, suggest_category_with_ai, update_ai_config,
    AiCategorySuggestionContextPolicy, AiCategorySuggestionRequest, AiConfig, AiFeatureConfig,
    AiFeatureKind, AiProviderPreference, CoreError, DuplicateStrategy, ErrorKind,
    ErrorMappingInput, ErrorRecoverability, ErrorSeverity, FileFilter, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
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
    fs::write(&source, b"fixture").expect("write fixture source");
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
                enabled: true,
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

fn active_category(repo: &Path, file_id: i64) -> String {
    list_files(
        path_string(repo),
        FileFilter {
            category: None,
            include_deleted: None,
            imported_after: None,
            imported_before: None,
            limit: 100,
            offset: 0,
        },
    )
    .expect("list active files")
    .into_iter()
    .find(|file| file.id == file_id)
    .expect("find imported file")
    .category
}

fn ai_call_log_count(repo: &Path) -> i64 {
    let connection = Connection::open(repo.join(".areamatrix/index.db")).expect("open database");
    connection
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master
             WHERE type = 'table' AND name = 'ai_call_log'",
            [],
            |row| row.get::<_, i64>(0),
        )
        .expect("query ai_call_log table presence")
}

fn ai_call_log_secret_rows(repo: &Path) -> i64 {
    let connection = Connection::open(repo.join(".areamatrix/index.db")).expect("open database");
    connection
        .query_row(
            "SELECT COUNT(*) FROM ai_call_log
             WHERE result_summary LIKE '%sk-secret%' OR privacy_rule_id LIKE '%sk-secret%'",
            [],
            |row| row.get(0),
        )
        .expect("query secret fragments in call log")
}

fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    let connection = Connection::open(repo.join(".areamatrix/index.db")).expect("open database");
    connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .optional()
        .expect("query repo_config value")
}

fn assert_sanitized(error: &CoreError, kind: ErrorKind) {
    assert_eq!(error.kind(), kind);
    assert_eq!(error.to_error_mapping().kind, kind);
    assert_no_secret_material(&error.to_string());
    assert_no_secret_material(error.raw_context());
    assert_no_secret_material(&error.to_error_mapping().raw_context);
}

fn assert_no_secret_material(value: &str) {
    for fragment in ["sk-secret", "Bearer", "api_key", "token="] {
        assert!(
            !value.contains(fragment),
            "unexpected secret fragment `{fragment}` in `{value}`"
        );
    }
}

#[test]
fn ai_classification_suggestion_failure_empty_state_and_invalid_inputs_are_config_errors() {
    let empty_repo = tempfile::tempdir().expect("create temporary repository directory");
    let readme = empty_repo.path().join("README.md");
    fs::write(&readme, "user readme\n").expect("write user README");

    let empty_error = suggest_category_with_ai(path_string(empty_repo.path()), request(1))
        .expect_err("missing metadata must be explicit config error");

    assert_sanitized(&empty_error, ErrorKind::Config);
    assert_eq!(
        fs::read_to_string(&readme).expect("read user README"),
        "user readme\n"
    );
    assert!(!empty_repo.path().join(".areamatrix").exists());

    let initialized = initialized_repo();
    let repo_path = path_string(initialized.path());
    let file_id = import_fixture(initialized.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone())).expect("enable AI");

    let missing_error = suggest_category_with_ai(repo_path.clone(), request(file_id + 10_000))
        .expect_err("missing active file id must fail");
    assert_sanitized(&missing_error, ErrorKind::Config);

    let mut secret_request = request(file_id);
    secret_request.privacy_policy_ref = Some("sk-secret-provider-key".to_owned());
    let secret_error = suggest_category_with_ai(repo_path, secret_request)
        .expect_err("secret-shaped privacy reference must fail");
    assert_sanitized(&secret_error, ErrorKind::Config);

    assert_eq!(active_category(initialized.path(), file_id), "inbox");
    assert_eq!(ai_call_log_count(initialized.path()), 0);
}

#[test]
fn ai_classification_suggestion_failure_permission_denied_is_structured_and_non_mutating() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone())).expect("enable AI");
    let readme = repo.path().join("README.md");
    fs::write(&readme, "user readme\n").expect("write user README");

    let db_path = repo.path().join(".areamatrix/index.db");
    let original_permissions = fs::metadata(&db_path)
        .expect("read database permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o200);
    fs::set_permissions(&db_path, blocked_permissions).expect("make database unreadable");

    let error = suggest_category_with_ai(repo_path, request(file_id))
        .expect_err("unreadable metadata must fail");

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");

    assert_sanitized(&error, ErrorKind::PermissionDenied);
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(active_category(repo.path(), file_id), "inbox");
    assert_eq!(
        fs::read_to_string(readme).expect("read user README"),
        "user readme\n"
    );
}

#[test]
fn ai_classification_suggestion_failure_rule_config_error_does_not_silently_fallback() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone())).expect("enable AI");
    fs::write(
        repo.path().join(".areamatrix/classifier.yaml"),
        "version: 1\ndefault: missing\ncategories: []\n",
    )
    .expect("write invalid classifier config");

    let error = suggest_category_with_ai(repo_path, request(file_id))
        .expect_err("invalid classifier config must fail");

    assert_sanitized(&error, ErrorKind::Config);
    assert_eq!(
        error.raw_context(),
        "AI classification rule configuration is invalid"
    );
    assert_eq!(active_category(repo.path(), file_id), "inbox");
}

#[test]
fn ai_classification_suggestion_failure_call_log_db_abort_preserves_file_state() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone())).expect("enable AI");
    let config_before =
        repo_config_value(repo.path(), "ai_config").expect("AI config should be persisted");
    let connection = Connection::open(repo.path().join(".areamatrix/index.db"))
        .expect("open repository database");
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS ai_call_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                feature TEXT NOT NULL,
                file_id INTEGER,
                route TEXT,
                provider TEXT,
                model TEXT,
                status TEXT NOT NULL CHECK (status IN ('success','failed','skipped','unavailable')),
                sent_fields_json TEXT NOT NULL,
                privacy_rule_id TEXT,
                result_summary TEXT NOT NULL,
                error_code TEXT,
                occurred_at INTEGER NOT NULL
             );
             CREATE TRIGGER fail_ai_call_log_insert
             BEFORE INSERT ON ai_call_log
             BEGIN
               SELECT RAISE(ABORT, 'forced AI call log write failure');
             END;",
        )
        .expect("install failing call-log trigger");

    let error = suggest_category_with_ai(repo_path, request(file_id))
        .expect_err("late call log write failure must fail");

    assert_sanitized(&error, ErrorKind::Internal);
    assert_eq!(error.raw_context(), "AI call log persistence failed");
    assert_eq!(active_category(repo.path(), file_id), "inbox");
    assert_eq!(
        repo_config_value(repo.path(), "ai_config").as_deref(),
        Some(config_before.as_str())
    );
}

#[test]
fn ai_classification_suggestion_failure_error_mapping_matches_documented_codes() {
    for (kind, severity, recoverability) in [
        (
            ErrorKind::Config,
            ErrorSeverity::Medium,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::PermissionDenied,
            ErrorSeverity::High,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorKind::Internal,
            ErrorSeverity::Critical,
            ErrorRecoverability::Fatal,
        ),
    ] {
        let mapping = map_core_error(ErrorMappingInput {
            kind: kind.clone(),
            path: Some("metadata".to_owned()),
            reason: Some("AI classification failure edge".to_owned()),
            message: Some("AI classification internal failure".to_owned()),
        });
        assert_eq!(mapping.kind, kind);
        assert_eq!(mapping.severity, severity);
        assert_eq!(mapping.recoverability, recoverability);
    }
}

#[test]
fn ai_classification_suggestion_failure_privacy_secret_is_rejected_before_log_write() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "invoice-2026.pdf", "inbox");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone())).expect("enable AI");
    let mut secret_request = request(file_id);
    secret_request.privacy_policy_ref = Some("api_key:sk-secret".to_owned());

    let error = suggest_category_with_ai(repo_path, secret_request)
        .expect_err("secret-like privacy ref must be rejected");

    assert_sanitized(&error, ErrorKind::Config);
    assert_eq!(ai_call_log_count(repo.path()), 0);

    let mut blocked_request = request(file_id);
    blocked_request.privacy_policy_ref = Some("private-folder".to_owned());
    let skipped = suggest_category_with_ai(path_string(repo.path()), blocked_request)
        .expect("privacy skip is structured");
    assert!(skipped.call_log_id.is_some());
    assert_eq!(ai_call_log_secret_rows(repo.path()), 0);
}
