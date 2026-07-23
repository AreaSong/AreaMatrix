#[path = "support/ai_classification_suggestion_common.rs"]
mod ai_common;

use std::path::Path;

use ai_common::AiRuntime;
use area_matrix_core::{
    import_file, init_repo, list_ai_calls, suggest_category_with_ai, update_ai_config,
    AiCallLogFeature, AiCallLogFilter, AiCallLogPagination, AiCallLogStatus,
    AiCategorySuggestionContextPolicy, AiCategorySuggestionRequest, AiConfig, AiFeatureConfig,
    AiFeatureKind, AiProviderPreference, DuplicateStrategy, ImportDestination, ImportOptions,
    OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const OPTIONAL_AI_CALL_LOG_COLUMNS: [&str; 6] = [
    "batch_id",
    "scope",
    "duration_ms",
    "privacy_rules_checked",
    "privacy_rule_name",
    "matched_field_type",
];

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
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("initialize repository");
    repo
}

fn import_fixture(repo: &Path, name: &str) -> i64 {
    let source_dir = repo.join("fixtures");
    std::fs::create_dir_all(&source_dir).expect("create fixture source directory");
    let source = source_dir.join(name);
    std::fs::write(&source, b"fixture").expect("write fixture source");
    import_file(
        path_string(repo),
        path_string(&source),
        ImportOptions {
            mode: StorageMode::Copied,
            destination: ImportDestination::AutoClassify,
            target_directory: None,
            override_category: Some("inbox".to_owned()),
            override_filename: None,
            duplicate_strategy: DuplicateStrategy::Skip,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("import fixture file")
    .id
}

fn request(file_id: i64) -> AiCategorySuggestionRequest {
    AiCategorySuggestionRequest {
        file_id,
        context_policy: AiCategorySuggestionContextPolicy::FileNameAndPath,
        privacy_policy_ref: None,
        content_locale: area_matrix_core::ContentLocale::En,
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn ai_call_log_columns(repo: &Path) -> Vec<String> {
    let db = open_db(repo);
    let mut statement = db
        .prepare("PRAGMA table_info(ai_call_log)")
        .expect("prepare AI call log columns");
    statement
        .query_map([], |row| row.get::<_, String>(1))
        .expect("query AI call log columns")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect AI call log columns")
}

#[test]
fn ai_call_log_implementation_reads_legacy_base_schema_and_backfills_optional_columns() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "legacy.pdf");
    let db = open_db(repo.path());
    db.execute_batch(
        "CREATE TABLE ai_call_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            feature TEXT NOT NULL,
            file_id INTEGER,
            route TEXT,
            provider TEXT,
            model TEXT,
            status TEXT NOT NULL
              CHECK (status IN ('success', 'failed', 'skipped', 'unavailable')),
            sent_fields_json TEXT NOT NULL,
            privacy_rule_id TEXT,
            result_summary TEXT NOT NULL,
            error_code TEXT,
            occurred_at INTEGER NOT NULL,
            FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE SET NULL
        );",
    )
    .expect("create legacy AI call log table");
    db.execute(
        "INSERT INTO ai_call_log (
            feature, file_id, route, provider, model, status, sent_fields_json,
            privacy_rule_id, result_summary, error_code, occurred_at
         ) VALUES (
            'classification', ?1, NULL, NULL, NULL, 'skipped', '[]',
            'rule:legacy-private', 'No AI call was made', NULL, 100
         )",
        params![file_id],
    )
    .expect("insert legacy AI call log row");
    let legacy_rule_id = db.last_insert_rowid();
    db.execute(
        "INSERT INTO ai_call_log (
            feature, file_id, route, provider, model, status, sent_fields_json,
            privacy_rule_id, result_summary, error_code, occurred_at
         ) VALUES (
            'classification', ?1, 'local', 'local_model', 'legacy-model', 'success',
            '[\"filename\"]', NULL, 'Legacy successful call', NULL, 101
         )",
        params![file_id],
    )
    .expect("insert legacy AI call log row without privacy rule id");
    let legacy_unknown_id = db.last_insert_rowid();
    drop(db);

    let before_columns = ai_call_log_columns(repo.path());
    for column in OPTIONAL_AI_CALL_LOG_COLUMNS {
        assert!(!before_columns.iter().any(|value| value == column));
    }

    let before = list_ai_calls(repo_path.clone(), default_filter(), page())
        .expect("read legacy AI call log schema");
    let legacy = before
        .records
        .iter()
        .find(|row| row.id == legacy_rule_id)
        .expect("read legacy AI call log row");
    assert_eq!(legacy.file_id, Some(file_id));
    assert_eq!(legacy.batch_id, None);
    assert_eq!(legacy.scope, None);
    assert_eq!(legacy.duration_ms, None);
    assert!(legacy.privacy_rules_checked);
    assert_eq!(
        legacy.privacy_rule_id.as_deref(),
        Some("rule:legacy-private")
    );
    assert_eq!(legacy.privacy_rule_name, None);
    assert_eq!(legacy.matched_field_type, None);
    let legacy_unknown = before
        .records
        .iter()
        .find(|row| row.id == legacy_unknown_id)
        .expect("read legacy AI call log row without privacy rule id");
    assert!(!legacy_unknown.privacy_rules_checked);
    assert_eq!(legacy_unknown.privacy_rule_id, None);

    update_ai_config(repo_path.clone(), ai_config(repo_path.clone())).expect("enable AI");
    let _runtime = AiRuntime::local("finance", 0.91, "legacy upgrade producer");
    let suggestion = suggest_category_with_ai(repo_path.clone(), request(file_id))
        .expect("write upgraded AI call log row");
    assert!(suggestion.call_log_id.is_some());

    let after_columns = ai_call_log_columns(repo.path());
    for column in OPTIONAL_AI_CALL_LOG_COLUMNS {
        assert!(
            after_columns.iter().any(|value| value == column),
            "successful producer write should add `{column}`"
        );
    }
    let after = list_ai_calls(repo_path, default_filter(), page())
        .expect("read upgraded AI call log schema");
    assert_eq!(after.total_count, 3);
    let legacy = after
        .records
        .iter()
        .find(|row| row.id == legacy_rule_id)
        .expect("read upgraded legacy row");
    assert_eq!(legacy.file_id, Some(file_id));
    assert_eq!(
        legacy.privacy_rule_id.as_deref(),
        Some("rule:legacy-private")
    );
    assert!(legacy.privacy_rules_checked);
    let legacy_unknown = after
        .records
        .iter()
        .find(|row| row.id == legacy_unknown_id)
        .expect("read upgraded legacy row without privacy rule id");
    assert!(!legacy_unknown.privacy_rules_checked);
    assert_eq!(legacy_unknown.privacy_rule_id, None);
    let current = after
        .records
        .iter()
        .find(|row| row.id == suggestion.call_log_id.expect("current call log id"))
        .expect("read current producer row");
    assert!(current.privacy_rules_checked);
    assert_eq!(current.privacy_rule_id, None);
}

#[test]
fn ai_call_log_implementation_preserves_audit_row_when_file_row_is_deleted() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let file_id = import_fixture(repo.path(), "linked-log.pdf");
    update_ai_config(repo_path.clone(), ai_config(repo_path.clone())).expect("enable AI");
    let _runtime = AiRuntime::local("finance", 0.88, "linked audit row");
    let suggestion = suggest_category_with_ai(repo_path.clone(), request(file_id))
        .expect("write linked AI call log");
    let log_id = suggestion.call_log_id.expect("AI call log id");

    let db = open_db(repo.path());
    let relative_path: String = db
        .query_row(
            "SELECT path FROM files WHERE id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .expect("read linked file path");
    let user_path = repo.path().join(relative_path);
    let user_bytes = std::fs::read(&user_path).expect("read linked user file");
    db.execute_batch("PRAGMA foreign_keys = ON;")
        .expect("enable foreign keys");
    db.execute("DELETE FROM files WHERE id = ?1", params![file_id])
        .expect("delete linked metadata row");

    let stored_file_id: Option<i64> = db
        .query_row(
            "SELECT file_id FROM ai_call_log WHERE id = ?1",
            params![log_id],
            |row| row.get(0),
        )
        .expect("read preserved audit row");
    assert_eq!(stored_file_id, None);
    let log_count: i64 = db
        .query_row(
            "SELECT COUNT(*) FROM ai_call_log WHERE id = ?1",
            params![log_id],
            |row| row.get(0),
        )
        .expect("count preserved audit row");
    assert_eq!(log_count, 1);
    drop(db);

    let page = list_ai_calls(repo_path, default_filter(), page()).expect("list detached audit row");
    let record = page
        .records
        .iter()
        .find(|row| row.id == log_id)
        .expect("read detached audit row");
    assert_eq!(record.file_id, None);
    assert_eq!(record.file_display_name, None);
    assert_eq!(record.feature, AiCallLogFeature::Classification);
    assert_eq!(record.status, AiCallLogStatus::Success);
    assert_eq!(
        std::fs::read(&user_path).expect("read user file after metadata deletion"),
        user_bytes
    );
}
