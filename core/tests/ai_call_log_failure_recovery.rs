use std::{fs, path::Path};

use area_matrix_core::{
    clear_ai_call_log, init_repo, list_ai_calls, map_core_error, AiCallLogClearRequest,
    AiCallLogClearScope, AiCallLogFeature, AiCallLogFilter, AiCallLogPagination, CoreError,
    ErrorKind, ErrorMappingInput, ErrorRecoverability, ErrorSeverity, OverviewOutput, RepoInitMode,
    RepoInitOptions,
};
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

fn default_filter() -> AiCallLogFilter {
    AiCallLogFilter {
        feature: None,
        route: None,
        status: None,
        occurred_after: None,
        occurred_before: None,
        search_query: None,
    }
}

fn page() -> AiCallLogPagination {
    AiCallLogPagination {
        limit: 50,
        offset: 0,
    }
}

fn clear_all_request() -> AiCallLogClearRequest {
    AiCallLogClearRequest {
        scope: AiCallLogClearScope::All,
        entry_ids: Vec::new(),
        older_than: None,
    }
}

fn connection(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn create_ai_call_log_table(repo: &Path) {
    connection(repo)
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS ai_call_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                feature TEXT NOT NULL,
                file_id INTEGER,
                batch_id TEXT,
                scope TEXT,
                route TEXT,
                provider TEXT,
                model TEXT,
                status TEXT NOT NULL CHECK (status IN ('success','failed','skipped','unavailable')),
                duration_ms INTEGER,
                sent_fields_json TEXT NOT NULL,
                privacy_rules_checked INTEGER NOT NULL DEFAULT 0 CHECK (privacy_rules_checked IN (0, 1)),
                privacy_rule_id TEXT,
                privacy_rule_name TEXT,
                matched_field_type TEXT,
                result_summary TEXT NOT NULL,
                error_code TEXT,
                occurred_at INTEGER NOT NULL
             );",
        )
        .expect("create AI call log table");
}

fn insert_provider_log(repo: &Path, summary: &str, occurred_at: i64) -> i64 {
    let db = connection(repo);
    db.execute(
        "INSERT INTO ai_call_log (
            feature, file_id, scope, route, provider, model, status, duration_ms,
            sent_fields_json, privacy_rules_checked, result_summary, error_code, occurred_at
         ) VALUES (
            'provider_test', NULL, 'Provider verification', 'remote',
            'keychain:raw-provider', 'secure-storage:env:SECRET', 'failed', 1200,
            '[]', 0, ?1, 'api_key=sk-secret', ?2
         )",
        params![summary, occurred_at],
    )
    .expect("insert provider AI log");
    db.last_insert_rowid()
}

fn ai_call_log_count(repo: &Path) -> i64 {
    connection(repo)
        .query_row("SELECT COUNT(*) FROM ai_call_log", [], |row| row.get(0))
        .expect("count AI call log rows")
}

fn table_exists(repo: &Path, table: &str) -> bool {
    connection(repo)
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            params![table],
            |_| Ok(true),
        )
        .unwrap_or(false)
}

fn assert_no_secret_material(value: &str) {
    for fragment in [
        "sk-secret",
        "api_key",
        "keychain:",
        "secure-storage:",
        "token=",
    ] {
        assert!(
            !value.contains(fragment),
            "unexpected secret fragment `{fragment}` in `{value}`"
        );
    }
}

fn assert_user_file_unchanged(repo: &Path) {
    assert_eq!(
        fs::read_to_string(repo.join("README.md")).expect("read user README"),
        "user readme\n"
    );
}

#[test]
fn ai_call_log_failure_empty_state_returns_page_without_creating_table_or_files() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");

    let result = list_ai_calls(path_string(repo.path()), default_filter(), page())
        .expect("missing AI call log table is an empty state");

    assert_eq!(result.total_count, 0);
    assert!(result.records.is_empty());
    assert_eq!(result.retention_days, 90);
    assert!(result.redaction_policy.contains("No API keys"));
    assert!(!table_exists(repo.path(), "ai_call_log"));
    assert_user_file_unchanged(repo.path());
}

#[test]
fn ai_call_log_failure_invalid_inputs_are_explicit_db_errors_without_writes() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");

    let invalid_list_inputs = [
        (
            AiCallLogFilter {
                search_query: Some(" bad ".to_owned()),
                ..default_filter()
            },
            page(),
        ),
        (
            AiCallLogFilter {
                occurred_after: Some(10),
                occurred_before: Some(10),
                ..default_filter()
            },
            page(),
        ),
        (
            default_filter(),
            AiCallLogPagination {
                limit: 201,
                offset: 0,
            },
        ),
        (
            default_filter(),
            AiCallLogPagination {
                limit: 50,
                offset: -1,
            },
        ),
    ];

    for (filter, pagination) in invalid_list_inputs {
        let error = list_ai_calls(path_string(repo.path()), filter, pagination)
            .expect_err("invalid list input must fail");
        assert!(matches!(error, CoreError::Db { .. }));
    }

    let invalid_clear_inputs = [
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::All,
            entry_ids: vec![1],
            older_than: None,
        },
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::SelectedEntries,
            entry_ids: Vec::new(),
            older_than: None,
        },
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::SelectedEntries,
            entry_ids: vec![1, 0],
            older_than: None,
        },
        AiCallLogClearRequest {
            scope: AiCallLogClearScope::OlderThan,
            entry_ids: Vec::new(),
            older_than: Some(-1),
        },
    ];

    for request in invalid_clear_inputs {
        let error = clear_ai_call_log(path_string(repo.path()), request)
            .expect_err("invalid clear input must fail");
        assert!(matches!(error, CoreError::Db { .. }));
    }

    assert!(!table_exists(repo.path(), "ai_call_log"));
    assert_user_file_unchanged(repo.path());
}

#[test]
fn ai_call_log_failure_clear_rollback_preserves_log_rows_and_user_files() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    create_ai_call_log_table(repo.path());
    let first_id = insert_provider_log(repo.path(), "old provider failure", 100);
    let second_id = insert_provider_log(repo.path(), "new provider failure", 200);
    connection(repo.path())
        .execute_batch(
            "CREATE TRIGGER fail_ai_call_log_delete
             BEFORE DELETE ON ai_call_log
             BEGIN
               SELECT RAISE(ABORT, 'forced AI call log delete failure');
             END;",
        )
        .expect("install delete failure trigger");

    let error = clear_ai_call_log(path_string(repo.path()), clear_all_request())
        .expect_err("delete trigger must abort clear");

    assert!(
        matches!(error, CoreError::Db { message } if message.contains("forced AI call log delete failure"))
    );
    assert_eq!(ai_call_log_count(repo.path()), 2);
    let listed = list_ai_calls(path_string(repo.path()), default_filter(), page())
        .expect("list after abort");
    let ids = listed
        .records
        .iter()
        .map(|record| record.id)
        .collect::<Vec<_>>();
    assert_eq!(ids, vec![second_id, first_id]);
    assert_user_file_unchanged(repo.path());
}

#[test]
fn ai_call_log_failure_schema_corruption_and_secrets_map_to_db_without_leaks() {
    let repo = initialized_repo();
    create_ai_call_log_table(repo.path());
    let row_id = insert_provider_log(
        repo.path(),
        "api_key=sk-secret token=hidden provider raw response",
        1_800_000_000,
    );

    let listed = list_ai_calls(path_string(repo.path()), default_filter(), page())
        .expect("sensitive stored columns are sanitized on read");
    let record = listed.records.first().expect("sensitive row is listed");
    assert_eq!(record.id, row_id);
    assert_eq!(record.feature, AiCallLogFeature::ProviderTest);
    for value in [
        record.provider_name.as_deref(),
        record.model_name.as_deref(),
        Some(record.result_summary.as_str()),
        record.error_code.as_deref(),
    ]
    .into_iter()
    .flatten()
    {
        assert_no_secret_material(value);
    }

    connection(repo.path())
        .execute("DROP TABLE ai_call_log", [])
        .expect("drop valid AI call log table");
    connection(repo.path())
        .execute(
            "CREATE TABLE ai_call_log (
                id INTEGER PRIMARY KEY,
                feature TEXT NOT NULL,
                status TEXT NOT NULL,
                occurred_at INTEGER NOT NULL
             )",
            [],
        )
        .expect("create corrupted AI call log table");

    let error = list_ai_calls(path_string(repo.path()), default_filter(), page())
        .expect_err("corrupted schema must fail explicitly");

    assert!(matches!(error, CoreError::Db { .. }));
    assert_no_secret_material(&error.to_string());
    assert_no_secret_material(error.raw_context());
}

#[cfg(unix)]
#[test]
fn ai_call_log_failure_permission_denied_is_structured_and_non_mutating() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    create_ai_call_log_table(repo.path());
    insert_provider_log(repo.path(), "provider failure", 100);

    let db_path = repo.path().join(".areamatrix/index.db");
    let original_permissions = fs::metadata(&db_path)
        .expect("read database permissions")
        .permissions();
    fs::set_permissions(&db_path, fs::Permissions::from_mode(0o200))
        .expect("make database unreadable");

    let error = list_ai_calls(path_string(repo.path()), default_filter(), page())
        .expect_err("unreadable metadata must map to permission denied");

    fs::set_permissions(&db_path, original_permissions).expect("restore database permissions");

    assert!(matches!(error, CoreError::PermissionDenied { .. }));
    assert_eq!(ai_call_log_count(repo.path()), 1);
    assert_user_file_unchanged(repo.path());
}

#[test]
fn ai_call_log_failure_error_mapping_matches_documented_codes() {
    for (kind, severity, recoverability) in [
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
    ] {
        let mapping = map_core_error(ErrorMappingInput {
            kind: kind.clone(),
            path: Some("repository metadata".to_owned()),
            reason: Some("AI call log failure edge".to_owned()),
            message: Some("AI call log metadata unavailable".to_owned()),
        });
        assert_eq!(mapping.kind, kind);
        assert_eq!(mapping.severity, severity);
        assert_eq!(mapping.recoverability, recoverability);
    }

    let locked = map_core_error(ErrorMappingInput {
        kind: ErrorKind::Db,
        path: None,
        reason: None,
        message: Some("database is locked".to_owned()),
    });
    assert_eq!(locked.recoverability, ErrorRecoverability::Retryable);
}
