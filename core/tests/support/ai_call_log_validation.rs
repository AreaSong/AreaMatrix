use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, AiCallLogClearRequest, AiCallLogClearScope, AiCallLogFilter, AiCallLogPagination,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use rusqlite::{params, Connection};

#[derive(Debug)]
struct LogFixture<'a> {
    feature: &'a str,
    file_id: Option<i64>,
    scope: Option<&'a str>,
    route: Option<&'a str>,
    provider: Option<&'a str>,
    model: Option<&'a str>,
    status: &'a str,
    sent_fields_json: &'a str,
    privacy_rules_checked: bool,
    privacy_rule_id: Option<&'a str>,
    privacy_rule_name: Option<&'a str>,
    matched_field_type: Option<&'a str>,
    result_summary: &'a str,
    error_code: Option<&'a str>,
    occurred_at: i64,
}

#[derive(Debug, Eq, PartialEq)]
pub struct SafetySnapshot {
    pub user_readme: String,
    pub user_visible_paths: Vec<String>,
    pub files: Vec<(i64, String, String, String)>,
    pub ai_call_log_count: i64,
}

pub fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub fn initialized_repo() -> tempfile::TempDir {
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

pub fn connection(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

pub fn insert_file_fixture(repo: &Path) -> i64 {
    let file_path = repo.join("finance/invoice-2026.pdf");
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create user file directory");
    fs::write(&file_path, b"user invoice fixture").expect("write user file fixture");

    let db = connection(repo);
    db.execute(
        "INSERT INTO files (
            path, original_name, current_name, category, size_bytes,
            hash_sha256, storage_mode, origin, source_path,
            imported_at, updated_at, status
         ) VALUES (
            'finance/invoice-2026.pdf', 'invoice-2026.pdf', 'invoice-2026.pdf', 'finance', 20,
            ?1, 'copied', 'imported', NULL,
            100, 100, 'active'
         )",
        params![format!("{:064x}", 42)],
    )
    .expect("insert file fixture row");
    db.last_insert_rowid()
}

pub fn seed_ai_call_logs(repo: &Path, file_id: i64) -> (i64, i64, i64) {
    create_ai_call_log_table(repo);
    let success_id = insert_ai_log(repo, classification_success(file_id));
    let remote_id = insert_ai_log(repo, provider_failure());
    let skipped_id = insert_ai_log(repo, privacy_skip(file_id));
    (success_id, remote_id, skipped_id)
}

pub fn default_filter() -> AiCallLogFilter {
    AiCallLogFilter {
        feature: None,
        route: None,
        status: None,
        occurred_after: None,
        occurred_before: None,
        search_query: None,
    }
}

pub fn page(limit: i64, offset: i64) -> AiCallLogPagination {
    AiCallLogPagination { limit, offset }
}

pub fn clear_all_request() -> AiCallLogClearRequest {
    AiCallLogClearRequest {
        scope: AiCallLogClearScope::All,
        entry_ids: Vec::new(),
        older_than: None,
    }
}

pub fn snapshot(repo: &Path) -> SafetySnapshot {
    SafetySnapshot {
        user_readme: fs::read_to_string(repo.join("README.md")).expect("read user README"),
        user_visible_paths: user_visible_paths(repo),
        files: file_rows(repo),
        ai_call_log_count: ai_call_log_count(repo),
    }
}

pub fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

pub fn assert_secret_free(value: &str) {
    for fragment in [
        "sk-secret",
        "api_key",
        "keychain:",
        "secure-storage:",
        "token=hidden",
        "user invoice fixture",
    ] {
        assert!(
            !value.contains(fragment),
            "unexpected secret fragment `{fragment}` in `{value}`"
        );
    }
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

fn insert_ai_log(repo: &Path, fixture: LogFixture<'_>) -> i64 {
    let db = connection(repo);
    db.execute(
        "INSERT INTO ai_call_log (
            feature, file_id, scope, route, provider, model, status, duration_ms,
            sent_fields_json, privacy_rules_checked, privacy_rule_id, privacy_rule_name,
            matched_field_type, result_summary, error_code, occurred_at
         ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, ?7, 1200,
            ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15
         )",
        params![
            fixture.feature,
            fixture.file_id,
            fixture.scope,
            fixture.route,
            fixture.provider,
            fixture.model,
            fixture.status,
            fixture.sent_fields_json,
            if fixture.privacy_rules_checked { 1 } else { 0 },
            fixture.privacy_rule_id,
            fixture.privacy_rule_name,
            fixture.matched_field_type,
            fixture.result_summary,
            fixture.error_code,
            fixture.occurred_at,
        ],
    )
    .expect("insert AI call log fixture row");
    db.last_insert_rowid()
}

fn classification_success(file_id: i64) -> LogFixture<'static> {
    LogFixture {
        feature: "classification",
        file_id: Some(file_id),
        scope: Some("Classification"),
        route: Some("local"),
        provider: Some("local_model"),
        model: Some("local-mini"),
        status: "success",
        sent_fields_json: r#"["filename","repo_relative_path","extension"]"#,
        privacy_rules_checked: false,
        privacy_rule_id: None,
        privacy_rule_name: None,
        matched_field_type: None,
        result_summary: "Suggested finance for invoice",
        error_code: None,
        occurred_at: 1_800_000_000,
    }
}

fn provider_failure() -> LogFixture<'static> {
    LogFixture {
        feature: "provider_test",
        file_id: None,
        scope: Some("Provider verification"),
        route: Some("remote"),
        provider: Some("keychain:raw-provider"),
        model: Some("secure-storage:env:SECRET"),
        status: "failed",
        sent_fields_json: "[]",
        privacy_rules_checked: false,
        privacy_rule_id: None,
        privacy_rule_name: None,
        matched_field_type: None,
        result_summary: "api_key=sk-secret token=hidden provider raw response",
        error_code: Some("api_key=sk-secret"),
        occurred_at: 1_800_000_100,
    }
}

fn privacy_skip(file_id: i64) -> LogFixture<'static> {
    LogFixture {
        feature: "classification",
        file_id: Some(file_id),
        scope: Some("Classification"),
        route: None,
        provider: None,
        model: None,
        status: "skipped",
        sent_fields_json: "[]",
        privacy_rules_checked: true,
        privacy_rule_id: Some("rule:private-folder"),
        privacy_rule_name: Some("Private folder"),
        matched_field_type: Some("note_summary"),
        result_summary: "No AI call was made due to privacy rule",
        error_code: None,
        occurred_at: 1_800_000_200,
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let db = connection(repo);
    let mut statement = db
        .prepare("SELECT id, path, category, status FROM files ORDER BY id")
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let path = entry.expect("read repository entry").path();
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

fn ai_call_log_count(repo: &Path) -> i64 {
    connection(repo)
        .query_row("SELECT COUNT(*) FROM ai_call_log", [], |row| row.get(0))
        .expect("count AI call log rows")
}
