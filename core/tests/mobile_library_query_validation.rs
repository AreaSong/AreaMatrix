use std::{fs, path::Path};

use area_matrix_core::{
    get_file, init_repo, list_changes, list_files, list_tree_json, ChangeFilter, ChangeLogEntry,
    CoreError, CoreResult, FileAvailabilityStatus, FileEntry, FileFilter, OverviewOutput,
    RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde_json::Value;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-14-c4-03-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-03-mobile-library-query.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CONTRACT_TEST: &str = include_str!("mobile_library_query_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("mobile_library_query_implementation.rs");
const FAILURE_TEST: &str = include_str!("mobile_library_query_failure_recovery.rs");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options())
        .expect("initialize repository for mobile query validation");
    repo
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn default_file_filter(limit: i64, offset: i64) -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit,
        offset,
    }
}

fn default_change_filter(limit: i64, offset: i64) -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: None,
        since: None,
        until: None,
        limit,
        offset,
    }
}

fn write_repo_file(repo: &Path, relative_path: &str, content: &[u8]) {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create fixture parent directory");
    }
    fs::write(path, content).expect("write fixture file");
}

fn insert_file(repo: &Path, path: &str, imported_at: i64, write_file: bool) -> i64 {
    let current_name = path.rsplit('/').next().expect("fixture path has filename");
    if write_file {
        write_repo_file(repo, path, format!("content-{imported_at}").as_bytes());
    }

    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'docs', ?3,
                ?4, 'copied', 'imported', NULL,
                ?5, ?6, 'active'
             )",
            params![
                path,
                current_name,
                100 + imported_at,
                format!("{imported_at:064x}"),
                imported_at,
                imported_at + 1,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

fn insert_change(repo: &Path, file_id: i64, action: &str, occurred_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![
                file_id,
                action,
                r#"{"source":"mobile-library-query-validation"}"#,
                occurred_at,
            ],
        )
        .expect("insert change-log row");
}

fn metadata_counts(repo: &Path) -> (i64, i64) {
    let connection = open_db(repo);
    let files = connection
        .query_row("SELECT COUNT(*) FROM files", [], |row| row.get(0))
        .expect("count files");
    let changes = connection
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count changes");
    (files, changes)
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn mobile_library_query_validation_proves_paginated_ui_ready_queries() {
    let repo = initialized_repo();
    let old_id = insert_file(repo.path(), "docs/old.pdf", 10, true);
    let middle_id = insert_file(repo.path(), "docs/middle.pdf", 20, true);
    let missing_id = insert_file(repo.path(), "docs/missing.pdf", 30, false);
    insert_change(repo.path(), old_id, "imported", 100);
    insert_change(repo.path(), middle_id, "renamed", 200);
    insert_change(repo.path(), missing_id, "external_modified", 300);
    let before_counts = metadata_counts(repo.path());

    let files =
        list_files(path_string(repo.path()), default_file_filter(2, 0)).expect("list first page");
    assert_eq!(
        files
            .iter()
            .map(|file| file.current_name.as_str())
            .collect::<Vec<_>>(),
        vec!["missing.pdf", "middle.pdf"]
    );
    assert_eq!(
        files[0].availability_status,
        FileAvailabilityStatus::Missing
    );
    assert!(!repo.path().join(&files[0].path).exists());

    let detail = get_file(path_string(repo.path()), middle_id).expect("get Core-backed detail");
    assert_eq!(detail.id, middle_id);
    assert_eq!(detail.current_name, "middle.pdf");
    assert_eq!(
        detail.availability_status,
        FileAvailabilityStatus::Available
    );

    let missing_detail =
        get_file(path_string(repo.path()), missing_id).expect("get missing row detail");
    assert_eq!(
        missing_detail.availability_status,
        FileAvailabilityStatus::Missing
    );

    let changes = list_changes(path_string(repo.path()), default_change_filter(2, 0))
        .expect("list first change page");
    assert_eq!(
        changes
            .iter()
            .map(|change| change.action.as_str())
            .collect::<Vec<_>>(),
        vec!["external_modified", "renamed"]
    );

    let tree_json =
        list_tree_json(path_string(repo.path()), "en".to_owned()).expect("list mobile tree");
    let tree = serde_json::from_str::<Value>(&tree_json).expect("parse tree JSON");
    assert_eq!(tree["file_count"], 2);
    assert_eq!(metadata_counts(repo.path()), before_counts);
}

#[test]
fn mobile_library_query_validation_rejects_failures_without_repo_side_effects() {
    let uninitialized = tempfile::tempdir().expect("create uninitialized repository");
    write_repo_file(uninitialized.path(), "README.md", b"user readme");
    let before_readme =
        fs::read(uninitialized.path().join("README.md")).expect("read README before queries");

    let errors = [
        list_files(
            path_string(uninitialized.path()),
            default_file_filter(50, 0),
        )
        .expect_err("list_files requires initialized metadata"),
        get_file(path_string(uninitialized.path()), 1)
            .expect_err("get_file requires initialized metadata"),
        list_changes(
            path_string(uninitialized.path()),
            default_change_filter(50, 0),
        )
        .expect_err("list_changes requires initialized metadata"),
        list_tree_json(path_string(uninitialized.path()), "en".to_owned())
            .expect_err("list_tree_json requires initialized metadata"),
    ];
    assert!(errors
        .iter()
        .all(|error| matches!(error, CoreError::RepoNotInitialized { .. })));
    assert_eq!(
        fs::read(uninitialized.path().join("README.md")).expect("read README after queries"),
        before_readme
    );
    assert!(!uninitialized.path().join(".areamatrix").exists());

    let repo = initialized_repo();
    insert_file(repo.path(), "docs/report.pdf", 10, true);
    let before_counts = metadata_counts(repo.path());
    let mut invalid_filter = default_file_filter(50, 0);
    invalid_filter.imported_after = Some(20);
    invalid_filter.imported_before = Some(10);

    let error = list_files(path_string(repo.path()), invalid_filter)
        .expect_err("invalid mobile list filter must fail");
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert!(repo.path().join("docs/report.pdf").exists());
}

#[test]
fn mobile_library_query_validation_locks_core_api_udl_rust_and_test_evidence() {
    fn assert_list_files(_: fn(String, FileFilter) -> CoreResult<Vec<FileEntry>>) {}
    fn assert_get_file(_: fn(String, i64) -> CoreResult<FileEntry>) {}
    fn assert_list_changes(_: fn(String, ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>>) {}
    fn assert_tree(_: fn(String, String) -> CoreResult<String>) {}

    assert_list_files(list_files);
    assert_get_file(get_file);
    assert_list_changes(list_changes);
    assert_tree(list_tree_json);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-14: C4-03 validation",
        "为 C4-03 mobile-library-query 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-14",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-03 mobile-library-query",
        "- S4-IOS-02 mobile-library",
        "- S4-IOS-05 mobile-file-detail",
        "- `list_files`",
        "- `get_file`",
        "- `list_tree_json`",
        "- `list_changes`",
        "repo path、filter、pagination。",
        "移动端可分页数据。",
        "- 无写入。",
        "- `Db`",
        "- `RepoNotInitialized`",
        "移动端不需要一次加载全库。",
        "详情数据来自 Core，而非平台侧扫描。",
        "缺失文件状态可被 UI 表达。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-02 | mobile-library | C4-03 | mobile list/tree query | 分页，不全量加载",
        "| S4-IOS-05 | mobile-file-detail | C4-07 | detail/log/note query | 缺失进入 recovery",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    for fragment in [
        "sequence<FileEntry> list_files(string repo_path, FileFilter filter);",
        "FileEntry get_file(string repo_path, i64 file_id);",
        "sequence<ChangeLogEntry> list_changes(string repo_path, ChangeFilter filter);",
        "string list_tree_json(string repo_path, string locale);",
        "dictionary FileFilter",
        "i64 limit;",
        "i64 offset;",
        "dictionary ChangeFilter",
        "dictionary FileEntry",
        "FileAvailabilityStatus availability_status;",
        "enum FileAvailabilityStatus { \"Available\", \"Missing\" };",
        "dictionary ChangeLogEntry",
        "Db(string message);",
        "RepoNotInitialized(string path);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `list_files(repoPath, filter) throws -> [FileEntry]`",
        "### `get_file(repoPath, fileId) throws -> FileEntry`",
        "`FileEntry.availability_status` 会结构化标记 backing file 是否 `Missing`",
        "active\nmetadata 行仍返回 `FileAvailabilityStatus.Missing`",
        "### `list_changes(repoPath, filter) throws -> [ChangeLogEntry]`",
        "### `list_tree_json(repoPath, locale) throws -> String`",
        "按 `imported_at DESC` 排序。`limit > 1000` 自动 clamp。",
        "- `RepoNotInitialized`：资料库 metadata 缺失。",
        "- `Db`：树构建需要读取 SQLite metadata 时失败。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "pub fn list_files(repo_path: String, filter: FileFilter) -> CoreResult<Vec<FileEntry>>",
        "pub fn get_file(repo_path: String, file_id: i64) -> CoreResult<FileEntry>",
        "pub fn list_changes(repo_path: String, filter: ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>>",
        "pub fn list_tree_json(repo_path: String, locale: String) -> CoreResult<String>",
        "C4-03 reuses this query for `S4-IOS-02` mobile-library rows.",
        "availability status",
        "must use the documented `limit` and `offset` fields",
        "missing-file recovery stays with C4-18",
        "C4-07 owns the mobile detail aggregation",
        "does not trigger filesystem rescan or sync repair",
        "C4-03 mobile-library uses this tree snapshot",
    ] {
        assert_contains(API_RS, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "mobile_library_query_contract_exports_existing_query_signatures_and_page_inputs",
        "mobile_library_query_docs_core_api_and_udl_stay_aligned",
        "mobile_library_query_documents_consumer_state_without_adjacent_capabilities",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "mobile_library_query_implementation_paginates_rows_and_opens_core_detail",
        "mobile_library_query_implementation_lazily_pages_change_log_without_writes",
        "mobile_library_query_implementation_preserves_missing_rows_for_recovery_entry",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "mobile_library_query_failure_invalid_inputs_are_explicit_and_non_mutating",
        "mobile_library_query_failure_uninitialized_repo_is_structured_and_creates_no_metadata",
        "mobile_library_query_failure_corrupted_metadata_is_fatal_without_half_products",
        "mobile_library_query_failure_error_mapping_keeps_mobile_recovery_actions_structured",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
