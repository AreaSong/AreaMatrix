use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, rename_file, CoreError, CoreResult, DuplicateStrategy,
    FileEntry, FileFilter, FileOrigin, ImportDestination, ImportOptions, OverviewOutput,
    RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

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
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn copied_options(filename: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn empty_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

fn count_rows(repo: &Path, table: &str, status: Option<&str>) -> i64 {
    let connection = open_db(repo);
    match status {
        Some(status) => connection
            .query_row(
                &format!("SELECT COUNT(*) FROM {table} WHERE status = ?1"),
                [status],
                |row| row.get(0),
            )
            .expect("count rows by status"),
        None => connection
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .expect("count rows"),
    }
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, status FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read file row")
}

fn change_detail(repo: &Path, file_id: i64, action: &str) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log WHERE file_id = ?1 AND action = ?2",
            (file_id, action),
            |row| row.get(0),
        )
        .expect("read change detail");
    serde_json::from_str(&detail_json).expect("parse change detail")
}

fn install_rename_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_rename_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'renamed'
             BEGIN
               SELECT RAISE(ABORT, 'forced rename change log failure');
             END;",
        )
        .expect("install rename change-log failure trigger");
}

#[test]
fn resolve_name_conflict_contract_exports_callable_signatures() {
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}
    fn assert_rename(_: fn(String, i64, String) -> CoreResult<FileEntry>) {}

    assert_import(import_file);
    assert_rename(rename_file);
}

#[test]
fn resolve_name_conflict_contract_exposes_documented_inputs() {
    let import_options = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some("report.pdf".to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    };
    let manual_new_name = "report_1.pdf".to_owned();

    assert_eq!(
        import_options.override_filename.as_deref(),
        Some("report.pdf")
    );
    assert_eq!(import_options.destination, ImportDestination::AutoClassify);
    assert_eq!(manual_new_name, "report_1.pdf");
}

#[test]
fn resolve_name_conflict_contract_exposes_documented_outputs() {
    let entry = FileEntry {
        id: 10,
        path: "finance/report_1.pdf".to_owned(),
        original_name: "report.pdf".to_owned(),
        current_name: "report_1.pdf".to_owned(),
        category: "finance".to_owned(),
        size_bytes: 1024,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some("/tmp/source/report.pdf".to_owned()),
        imported_at: 100,
        updated_at: 100,
    };

    assert_eq!(entry.path, "finance/report_1.pdf");
    assert_eq!(entry.current_name, "report_1.pdf");
    assert_eq!(entry.original_name, "report.pdf");
}

#[test]
fn resolve_name_conflict_import_auto_numbers_same_name_different_content() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"first content");
    let (_source_root_b, source_b) = source_file("second.pdf", b"second content");
    let options = copied_options("same.pdf");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        options.clone(),
    )
    .expect("import first file");
    let second = import_file(path_string(repo.path()), path_string(&source_b), options)
        .expect("import second file with safe numbered name");

    assert_eq!(first.path, "finance/same.pdf");
    assert_eq!(first.current_name, "same.pdf");
    assert_eq!(second.path, "finance/same_1.pdf");
    assert_eq!(second.current_name, "same_1.pdf");
    assert_eq!(
        fs::read(repo.path().join(&first.path)).expect("read first final file"),
        b"first content"
    );
    assert_eq!(
        fs::read(repo.path().join(&second.path)).expect("read second final file"),
        b"second content"
    );
    assert_eq!(
        fs::read(&source_b).expect("read copied source"),
        b"second content"
    );

    let listed = list_files(path_string(repo.path()), empty_filter()).expect("list files");
    assert_eq!(listed.len(), 2);
    assert_eq!(file_row(repo.path(), second.id), {
        (
            "finance/same_1.pdf".to_owned(),
            "same_1.pdf".to_owned(),
            "active".to_owned(),
        )
    });
    let detail = change_detail(repo.path(), second.id, "imported");
    assert_eq!(detail["requested_name"], "same.pdf");
    assert_eq!(detail["final_name"], "same_1.pdf");
    assert_eq!(detail["final_path"], "finance/same_1.pdf");
    assert_eq!(detail["name_conflict_resolved"], true);
    assert_eq!(count_rows(repo.path(), "files", Some("active")), 2);
    assert_eq!(count_rows(repo.path(), "change_log", None), 2);
}

#[test]
fn resolve_name_conflict_rename_auto_numbers_and_logs_manual_resolution() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"first content");
    let (_source_root_b, source_b) = source_file("second.pdf", b"second content");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options("same.pdf"),
    )
    .expect("import first file");
    let second = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options("draft.pdf"),
    )
    .expect("import second file");

    let renamed = rename_file(path_string(repo.path()), second.id, "same.pdf".to_owned())
        .expect("rename to safe numbered file");

    assert_eq!(first.path, "finance/same.pdf");
    assert_eq!(renamed.path, "finance/same_1.pdf");
    assert_eq!(renamed.current_name, "same_1.pdf");
    assert!(repo.path().join("finance/same.pdf").exists());
    assert!(repo.path().join("finance/same_1.pdf").exists());
    assert!(!repo.path().join("finance/draft.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join(&renamed.path)).expect("read renamed file"),
        b"second content"
    );
    assert_eq!(file_row(repo.path(), second.id), {
        (
            "finance/same_1.pdf".to_owned(),
            "same_1.pdf".to_owned(),
            "active".to_owned(),
        )
    });

    let detail = change_detail(repo.path(), second.id, "renamed");
    assert_eq!(detail["from_path"], "finance/draft.pdf");
    assert_eq!(detail["to_path"], "finance/same_1.pdf");
    assert_eq!(detail["from_name"], "draft.pdf");
    assert_eq!(detail["requested_name"], "same.pdf");
    assert_eq!(detail["final_name"], "same_1.pdf");
    assert_eq!(detail["name_conflict_resolved"], true);
    assert_eq!(count_rows(repo.path(), "files", Some("active")), 2);
    assert_eq!(count_rows(repo.path(), "change_log", None), 3);
}

#[test]
fn resolve_name_conflict_rename_db_failure_restores_filesystem_and_metadata() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("source.pdf", b"source content");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("draft.pdf"),
    )
    .expect("import file before failed rename");
    install_rename_change_log_failure(repo.path());

    let result = rename_file(path_string(repo.path()), entry.id, "final.pdf".to_owned());

    assert!(matches!(result, Err(CoreError::Db { .. })));

    assert!(repo.path().join("finance/draft.pdf").exists());
    assert!(!repo.path().join("finance/final.pdf").exists());
    assert_eq!(file_row(repo.path(), entry.id), {
        (
            "finance/draft.pdf".to_owned(),
            "draft.pdf".to_owned(),
            "active".to_owned(),
        )
    });
    assert_eq!(count_rows(repo.path(), "files", Some("active")), 1);
    assert_eq!(count_rows(repo.path(), "change_log", None), 1);
}

#[test]
fn resolve_name_conflict_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "C1-10 resolve-name-conflict",
        "- S1-23 conflict-name",
        "- S1-24 replace-confirm",
        "- `import_file(repo_path, source_path, options)`",
        "- `rename_file(repo_path, file_id, new_name)`",
        "无冲突的最终文件名",
        "同名不同内容默认追加后缀，例如 `name_1.ext`。",
        "Replace 路径必须经过 S1-24",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "FileEntry import_file(",
        "string repo_path, string source_path, ImportOptions options",
        "FileEntry rename_file(string repo_path, i64 file_id, string new_name);",
        "dictionary ImportOptions",
        "string? override_filename;",
        "DuplicateStrategy duplicate_strategy;",
        "dictionary FileEntry",
        "string path;",
        "string current_name;",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
        "Conflict(string path);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "可能抛：`Io` / `Db` / `DuplicateFile` / `Conflict` / `InvalidPath`",
        "仅改文件名，不改分类。",
        "文件名包含禁用字符",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "| S1-23 | conflict-name | C1-10 | `import_file`, `rename_file`",
        "| S1-24 | replace-confirm | C1-09, C1-10 | `import_file`, `delete_file`",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }
}

#[test]
fn resolve_name_conflict_contract_documents_error_codes_and_side_effects() {
    let errors = [
        CoreError::conflict("path conflict"),
        CoreError::invalid_path("invalid path"),
        CoreError::permission_denied("permission denied"),
        CoreError::io("io error"),
        CoreError::db("database error"),
    ];

    assert_eq!(errors.len(), 5);

    for error_name in ["Conflict", "InvalidPath", "PermissionDenied", "Io", "Db"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in [
        "`files.path` 和 `files.current_name` 写入最终无冲突结果。",
        "`change_log` 记录自动改名或手动改名。",
        "不覆盖已有用户文件",
        "Replace 路径必须经过 S1-24",
        "自定义命名模板和批量重命名属于 Stage 2。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "C1-10 owns same-name conflict handling",
        "final conflict-free name",
        "must not overwrite an existing user file by default",
        "CoreError::Conflict { path }",
        "Renames a file entry to a conflict-free filename",
        "remain guarded by S1-24",
    ] {
        assert_contains(API_RS, fragment);
    }
}

#[test]
fn resolve_name_conflict_contract_keeps_adjacent_scope_out() {
    assert_ne!(DuplicateStrategy::Skip, DuplicateStrategy::Overwrite);
    assert_ne!(DuplicateStrategy::Skip, DuplicateStrategy::KeepBoth);

    assert_contains(CAPABILITY_SPEC, "自定义命名模板和批量重命名属于 Stage 2。");
    assert_contains(API_RS, "C1-09 owns duplicate detection");
    assert_contains(API_RS, "C1-10 owns same-name conflict handling");
}
