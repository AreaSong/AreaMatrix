use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_changes, rename_file, ChangeFilter, CoreError, DuplicateStrategy,
    ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde_json::Value;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const DB_CHANGE_LOG_RS: &str = include_str!("../src/db/change_log.rs");
const S1_13_DETAIL_LOG: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md");
const S1_21_IMPORT_RESULT: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md");
const S1_32_ERROR_RECOVERY: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document or source to contain `{needle}`"
    );
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

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn copied_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("finance/2026".to_owned()),
        override_category: None,
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn default_filter() -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn count_change_logs(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows")
}

fn count_active_files(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active file rows")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn insert_file(repo: &Path, path: &str, category: &str, imported_at: i64) -> i64 {
    let current_name = path.rsplit('/').next().expect("test path has a filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 1,
                ?4, 'copied', 'imported', NULL,
                ?5, ?5, 'active'
             )",
            params![
                path,
                current_name,
                category,
                format!("{imported_at:064x}"),
                imported_at,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

fn insert_change(repo: &Path, file_id: i64, action: &str, detail: &str, occurred_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![file_id, action, detail, occurred_at],
        )
        .expect("insert change-log row");
}

fn actions(changes: &[area_matrix_core::ChangeLogEntry]) -> Vec<&str> {
    changes
        .iter()
        .map(|change| change.action.as_str())
        .collect()
}

fn assert_detail_json_objects(changes: &[area_matrix_core::ChangeLogEntry]) {
    for change in changes {
        let detail = serde_json::from_str::<Value>(&change.detail_json).expect("parse detail_json");
        assert!(
            detail.is_object(),
            "detail_json for action `{}` must be an object",
            change.action
        );
    }
}

#[test]
fn list_change_log_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    assert_c1_13_capability_spec();
    assert_core_api_and_udl_contract();
    assert_stage_one_consumers();
    assert_rust_entry_points();
}

fn assert_c1_13_capability_spec() {
    for fragment in [
        "C1-13 list-change-log",
        "- S1-13 detail-log",
        "- S1-21 import-result",
        "- S1-32 error-recovery",
        "- `list_changes(repo_path, filter) -> sequence<ChangeLogEntry>`",
        "- `ChangeFilter`",
        "- 按 `occurred_at DESC` 排序的 change log。",
        "- 无写入。",
        "- 支持按 file_id、category、action、时间范围和分页过滤。",
        "- `detail_json` 保持可解析 JSON。",
        "- Undo 历史和批量撤销属于 Stage 2。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
}

fn assert_core_api_and_udl_contract() {
    for fragment in [
        "sequence<ChangeLogEntry> list_changes(string repo_path, ChangeFilter filter);",
        "dictionary ChangeFilter",
        "i64? file_id;",
        "string? category;",
        "string? action;",
        "i64? since;",
        "i64? until;",
        "i64 limit;",
        "i64 offset;",
        "dictionary ChangeLogEntry",
        "string detail_json;",
        "i64 occurred_at;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

fn assert_stage_one_consumers() {
    for fragment in [
        "| S1-13 | detail-log | C1-13, C1-17, C1-18, C1-19 | `list_changes`, `sync_external_changes`",
        "| S1-21 | import-result | C1-06, C1-13 | `import_file`, `list_changes`",
        "| S1-32 | error-recovery | C1-16, C1-21 | `recover_on_startup`, error mapping",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Core `list_changes`。", "最新记录在最上方。", "detail_json"] {
        assert_contains(S1_13_DETAIL_LOG, fragment);
    }
    for fragment in [
        "导入结果",
        "成功、跳过、失败数量",
        "Export Details 不包含用户文件内容。",
    ] {
        assert_contains(S1_21_IMPORT_RESULT, fragment);
    }
    for fragment in [
        "CoreError 映射表。",
        "Collect Diagnostics 不包含用户文件内容",
    ] {
        assert_contains(S1_32_ERROR_RECOVERY, fragment);
    }
}

fn assert_rust_entry_points() {
    for fragment in [
        "C1-13 defines this as the read-only change-log query",
        "detail_json`] value must",
        "remain parseable JSON",
        "This API has no write side effects",
        "Undo history",
        "belong to Stage 2",
    ] {
        assert_contains(API_RS, fragment);
    }
    for fragment in [
        "ORDER BY cl.occurred_at DESC, cl.id DESC",
        "ensure_detail_json_object",
        "limit.min(1000)",
    ] {
        assert_contains(DB_CHANGE_LOG_RS, fragment);
    }
}

#[test]
fn list_change_log_integration_verify_real_query_supports_detail_and_import_result_contexts() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"invoice bytes");
    let source_before = fs::read(&source).expect("read source before import");

    let imported = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("import file for change-log integration");
    let renamed = rename_file(
        path_string(repo.path()),
        imported.id,
        "invoice-final.pdf".to_owned(),
    )
    .expect("rename file for change-log integration");
    let before_logs = count_change_logs(repo.path());
    let before_active = count_active_files(repo.path());
    let before_staging = staging_entries(repo.path());

    let mut filter = default_filter();
    filter.file_id = Some(imported.id);
    let changes = list_changes(path_string(repo.path()), filter).expect("list file changes");

    assert_eq!(actions(&changes), vec!["renamed", "imported"]);
    assert_eq!(changes[0].filename, "invoice-final.pdf");
    assert_eq!(changes[0].category, "finance");
    assert_detail_json_objects(&changes);
    assert_eq!(
        fs::read(&source).expect("read source after list_changes"),
        source_before
    );
    assert_eq!(
        fs::read(repo.path().join(&renamed.path)).expect("read repo file after list_changes"),
        source_before
    );
    assert_eq!(count_change_logs(repo.path()), before_logs);
    assert_eq!(count_active_files(repo.path()), before_active);
    assert_eq!(staging_entries(repo.path()), before_staging);
}

#[test]
fn list_change_log_integration_verify_filters_all_c1_13_actions_and_errors() {
    let repo = initialized_repo();
    let file_id = insert_file(repo.path(), "finance/report.pdf", "finance", 10);
    for (action, occurred_at) in [
        ("imported", 10),
        ("renamed", 20),
        ("moved", 30),
        ("edited_note", 40),
        ("external_modified", 50),
    ] {
        insert_change(
            repo.path(),
            file_id,
            action,
            r#"{"by":"integration"}"#,
            occurred_at,
        );
    }

    let mut filter = default_filter();
    filter.category = Some("finance".to_owned());
    filter.limit = 3;
    let changes = list_changes(path_string(repo.path()), filter).expect("list action kinds");
    assert_eq!(
        actions(&changes),
        vec!["external_modified", "edited_note", "moved"]
    );
    assert_detail_json_objects(&changes);

    let uninitialized_repo = tempfile::tempdir().expect("create uninitialized repository");
    assert_eq!(
        list_changes(path_string(uninitialized_repo.path()), default_filter()),
        Err(CoreError::RepoNotInitialized)
    );
    insert_change(repo.path(), file_id, "imported", "not-json", 60);
    assert_eq!(
        list_changes(path_string(repo.path()), default_filter()),
        Err(CoreError::Db)
    );
}
