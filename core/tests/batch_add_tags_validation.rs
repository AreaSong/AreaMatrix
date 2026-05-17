use std::{fs, path::Path};

use area_matrix_core::{
    batch_add_tags, init_repo, BatchMutationReport, BatchMutationStatus, CoreError, CoreResult,
    ErrorKind, ErrorRecoverability, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-06-batch-add-tags.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const TAGS_RS: &str = include_str!("../src/tags.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const DB_TAGS_RS: &str = include_str!("../src/db/tags.rs");

#[derive(Debug, Eq, PartialEq)]
struct BatchValidationSnapshot {
    tags: Vec<(i64, String)>,
    change_log: Vec<(i64, String, String)>,
    undo_actions: Vec<(String, String, String)>,
    staging_entries: Vec<String>,
    generated_entries: Vec<String>,
    user_visible_paths: Vec<String>,
}

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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn insert_active_file(repo: &Path, relative_path: &str) -> i64 {
    let file_path = repo.join(relative_path);
    fs::create_dir_all(file_path.parent().expect("fixture has parent directory"))
        .expect("create fixture directory");
    fs::write(&file_path, format!("fixture bytes for {relative_path}"))
        .expect("write fixture file");

    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture has filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'docs', 13,
                ?3, 'copied', 'imported', NULL,
                100, 100, 'active'
             )",
            params![relative_path, current_name, format!("{:064x}", relative_path.len())],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn insert_tag(repo: &Path, file_id: i64, tag: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, 100)",
            params![file_id, tag],
        )
        .expect("insert tag row");
}

fn snapshot(repo: &Path) -> BatchValidationSnapshot {
    BatchValidationSnapshot {
        tags: tag_rows(repo),
        change_log: change_log_rows(repo),
        undo_actions: undo_action_rows(repo),
        staging_entries: relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn tag_rows(repo: &Path) -> Vec<(i64, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT file_id, tag FROM tags ORDER BY file_id, tag")
        .expect("prepare tag rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query tag rows")
        .map(|row| row.expect("read tag row"))
        .collect()
}

fn change_log_rows(repo: &Path) -> Vec<(i64, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT COALESCE(file_id, 0), action, detail_json
               FROM change_log
              ORDER BY id",
        )
        .expect("prepare change-log rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query change-log rows")
        .map(|row| row.expect("read change-log row"))
        .collect()
}

fn undo_action_rows(repo: &Path) -> Vec<(String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT token, kind, status FROM undo_actions ORDER BY token")
        .expect("prepare undo action rows query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .expect("query undo action rows")
        .map(|row| row.expect("read undo action row"))
        .collect()
}

fn undo_inverse_relations(repo: &Path, token: &str) -> serde_json::Value {
    let inverse: String = open_db(repo)
        .query_row(
            "SELECT inverse_json FROM undo_actions WHERE token = ?1",
            params![token],
            |row| row.get(0),
        )
        .expect("read undo inverse json");
    serde_json::from_str(&inverse).expect("undo inverse json is valid")
}

fn relative_directory_entries(repo: &Path, root: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    collect_relative_paths(repo, root, &mut entries);
    entries.sort();
    entries
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_user_visible_paths(repo, repo, &mut paths);
    paths.sort();
    paths
}

fn collect_relative_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read metadata directory") {
        let entry = entry.expect("read metadata entry");
        let path = entry.path();
        paths.push(relative_path(repo, &path));
        if path.is_dir() {
            collect_relative_paths(repo, &path, paths);
        }
    }
}

fn collect_user_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = relative_path(repo, &path);
        if relative == ".areamatrix" || relative.starts_with(".areamatrix/") {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_user_visible_paths(repo, &path, paths);
        }
    }
}

fn relative_path(repo: &Path, path: &Path) -> String {
    path.strip_prefix(repo)
        .expect("path is inside repository")
        .to_string_lossy()
        .into_owned()
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_db_error<T: std::fmt::Debug>(result: Result<T, CoreError>) {
    let error = result.expect_err("operation should fail with Db");
    assert!(matches!(error, CoreError::Db { .. }));
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, ErrorKind::Db);
    assert_eq!(mapping.recoverability, ErrorRecoverability::UserActionRequired);
}

#[test]
fn batch_add_tags_validation_covers_success_skip_failure_and_undo_scope() {
    let repo = initialized_repo();
    let first_id = insert_active_file(repo.path(), "docs/first.pdf");
    let second_id = insert_active_file(repo.path(), "docs/second.pdf");
    insert_tag(repo.path(), first_id, "urgent");
    let before_paths = user_visible_paths(repo.path());

    let report = batch_add_tags(
        path_string(repo.path()),
        vec![first_id, second_id, first_id, 404],
        vec![
            " Urgent ".to_owned(),
            "ClientA".to_owned(),
            "urgent".to_owned(),
        ],
    )
    .expect("batch add tags returns report with partial item failure");

    assert_eq!(report.requested_file_count, 3);
    assert_eq!(report.requested_tag_count, 2);
    assert_eq!(report.added_count, 3);
    assert_eq!(report.skipped_count, 1);
    assert_eq!(report.failed_count, 2);
    assert_eq!(report.item_results.len(), 6);
    assert_item_statuses(&report, first_id, second_id);

    let token = report.undo_token.expect("added relations create undo token");
    assert_eq!(tag_rows(repo.path()).len(), 4);
    assert_eq!(change_log_rows(repo.path()).len(), 3);
    assert_eq!(undo_action_rows(repo.path()).len(), 1);
    assert_undo_inverse_excludes_preexisting_relation(repo.path(), &token, first_id);
    assert_eq!(user_visible_paths(repo.path()), before_paths);
}

#[test]
fn batch_add_tags_validation_covers_failure_paths_without_side_effects() {
    let repo = initialized_repo();
    let file_id = insert_active_file(repo.path(), "docs/source.pdf");
    insert_tag(repo.path(), file_id, "baseline");
    let before = snapshot(repo.path());

    assert_db_error(batch_add_tags(
        String::new(),
        vec![file_id],
        vec!["urgent".to_owned()],
    ));
    assert!(matches!(
        batch_add_tags(path_string(repo.path()), Vec::new(), vec!["urgent".to_owned()]),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        batch_add_tags(path_string(repo.path()), vec![file_id], vec!["bad/tag".to_owned()]),
        Err(CoreError::Db { .. })
    ));

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn batch_add_tags_validation_locks_core_api_udl_and_rust_alignment() {
    fn assert_signature(_: fn(String, Vec<i64>, Vec<String>) -> CoreResult<BatchMutationReport>) {}
    assert_signature(batch_add_tags);

    for fragment in [
        "# C2-06 batch-add-tags",
        "`batch_add_tags(repo_path, file_ids, tags) -> BatchMutationReport`",
        "成功、跳过、失败明细和 undo token。",
        "部分失败可追踪，不把失败项显示为成功。",
        "可撤销项进入 Undo toast/history。",
        "不修改文件内容或路径。",
        "批量 AI 标签建议属于 Stage 3。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-09 | batch-add-tags | C2-06, C2-07 | batch tag mutation | tags, undo_actions",
        "| S2-10 | undo-toast | C2-07 | undo action | undo_actions",
        "批量操作必须有 preview、确认、执行报告和 undo/action log。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "BatchMutationReport batch_add_tags(",
        "string repo_path, sequence<i64> file_ids, sequence<string> tags",
        "dictionary BatchMutationItemResult",
        "dictionary BatchMutationReport",
        "sequence<BatchMutationItemResult> item_results;",
        "string? undo_token;",
        "enum BatchMutationStatus { \"Added\", \"AlreadyHadTag\", \"Failed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "pub use tags::{",
        "batch_add_tags",
        "BatchMutationReport",
        "BatchMutationStatus",
    ] {
        assert_contains(LIB_RS, fragment);
    }

    for fragment in [
        "pub fn batch_add_tags(",
        "normalize_batch_file_ids(&file_ids)",
        "normalize_batch_tags(&tags)",
        "db::batch_add_tags_rows",
        "CoreError::db(\"batch tag input is invalid\")",
    ] {
        assert_contains(TAGS_RS, fragment);
    }
}

#[test]
fn batch_add_tags_validation_locks_persistence_and_testing_evidence() {
    for fragment in [
        "ensure_batch_tag_metadata_ready",
        "mutate_batch_tag_item",
        "savepoint",
        "try_mutate_batch_tag_item",
        "BatchMutationStatus::AlreadyHadTag",
        "create_batch_tag_undo_action",
        "\"kind\": \"batch_add_tags\"",
        "\"kind\": \"remove_tags\"",
    ] {
        assert_contains(DB_TAGS_RS, fragment);
    }

    for fragment in [
        "集成测试目录",
        "`core/tests/`",
        "关键测试场景",
        "DB / Migration",
        "外键约束生效",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_item_statuses(report: &BatchMutationReport, first_id: i64, second_id: i64) {
    assert_eq!(
        report
            .item_results
            .iter()
            .map(|item| (item.file_id, item.tag.as_str(), item.status.clone()))
            .collect::<Vec<_>>(),
        vec![
            (first_id, "urgent", BatchMutationStatus::AlreadyHadTag),
            (first_id, "clienta", BatchMutationStatus::Added),
            (second_id, "urgent", BatchMutationStatus::Added),
            (second_id, "clienta", BatchMutationStatus::Added),
            (404, "urgent", BatchMutationStatus::Failed),
            (404, "clienta", BatchMutationStatus::Failed),
        ]
    );
    for item in report
        .item_results
        .iter()
        .filter(|item| matches!(item.status, BatchMutationStatus::Failed))
    {
        assert!(item
            .error
            .as_deref()
            .expect("failed item has error")
            .contains("FileNotFound"));
    }
}

fn assert_undo_inverse_excludes_preexisting_relation(repo: &Path, token: &str, first_id: i64) {
    let inverse = undo_inverse_relations(repo, token);
    let relations = inverse["relations"].as_array().expect("relations array");
    assert_eq!(inverse["kind"], "remove_tags");
    assert_eq!(relations.len(), 3);
    assert!(relations
        .iter()
        .all(|relation| !(relation["file_id"] == first_id && relation["tag"] == "urgent")));
}
