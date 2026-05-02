use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, CoreError, DuplicateStrategy, FileFilter, FileOrigin,
    ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const S1_17_IMPORT_SINGLE: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md");
const S1_20_IMPORT_PROGRESS: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md");
const S1_21_IMPORT_RESULT: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md");
const S1_27_SETTINGS_REPOSITORY: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md");
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

fn indexed_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Indexed,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some("2026Q1_invoice.pdf".to_owned()),
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

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
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
            .expect("count table rows by status"),
        None => connection
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .expect("count table rows"),
    }
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn import_index_file_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    for fragment in [
        "`import_file(repo_path, source_path, ImportOptions { mode: Indexed, ... }) -> FileEntry`",
        "指向外部或资料库内现有文件的 `FileEntry`。",
        "- `files.storage_mode = Indexed`。",
        "- `files.source_path` 必须保留。",
        "- 写入 `change_log.imported`。",
        "- 不复制、不移动源文件。",
        "- 可读取源文件 metadata 和 hash。",
        "删除源文件后详情或列表能通过 `FileNotFound` 显示可恢复错误。",
        "Indexed 模式不得写入最终资料库文件副本。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "FileEntry import_file(",
        "string repo_path, string source_path, ImportOptions options",
        "dictionary ImportOptions",
        "StorageMode mode;",
        "dictionary FileEntry",
        "StorageMode storage_mode;",
        "string? source_path;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "FileNotFound();",
        "ICloudPlaceholder();",
        "PermissionDenied();",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| S1-17 | import-single-sheet | C1-05, C1-06, C1-07, C1-08 | `predict_category`, `import_file`",
        "| S1-20 | import-progress | C1-06, C1-07, C1-08 | `import_file`",
        "| S1-21 | import-result | C1-06, C1-13 | `import_file`, `list_changes`",
        "| S1-27 | settings-repository | C1-04, C1-08, C1-20 | `load_config`, `update_config`",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    assert_contains(
        S1_17_IMPORT_SINGLE,
        "Index-only：说明不复制，只记录引用路径；源文件移动后会缺失。",
    );
    assert_contains(S1_17_IMPORT_SINGLE, "Import 进入 `S1-20 import-progress`");
    assert_contains(S1_20_IMPORT_PROGRESS, "Writing index");
    assert_contains(S1_20_IMPORT_PROGRESS, "失败项不影响成功项。");
    assert_contains(S1_21_IMPORT_RESULT, "成功项已经出现在列表中。");
    assert_contains(S1_21_IMPORT_RESULT, "Retry Failed 不重复导入成功项。");
    assert_contains(S1_27_SETTINGS_REPOSITORY, "Files indexed: 1,248");
    assert_contains(
        S1_27_SETTINGS_REPOSITORY,
        "Change repository...`，只用于打开另一个资料库或选择新资料库位置。",
    );
    assert_contains(API_RS, "C1-08 owns index-only semantics");
}

#[test]
fn import_index_file_integration_verify_real_index_supports_consuming_context() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"invoice bytes");
    let source_before = fs::read(&source).expect("read source before indexed import");
    let source_path = path_string(&source);

    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        indexed_options(),
    )
    .expect("index external file");

    assert_eq!(
        fs::read(&source).expect("read source after indexed import"),
        source_before
    );
    assert_eq!(entry.path, source_path);
    assert_eq!(entry.original_name, "invoice.pdf");
    assert_eq!(entry.current_name, "2026Q1_invoice.pdf");
    assert_eq!(entry.category, "finance");
    assert_eq!(entry.storage_mode, StorageMode::Indexed);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(entry.source_path.as_deref(), Some(source_path.as_str()));
    assert!(!repo.path().join("finance").exists());
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list indexed files");
    assert_eq!(files, vec![entry.clone()]);
    assert_file_row_matches_indexed_import(repo.path(), entry.id, &source_path);
    assert_change_log_matches_indexed_import(repo.path(), entry.id, &source_path);
}

#[test]
fn import_index_file_integration_verify_missing_external_source_keeps_metadata() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("missing-later.pdf", b"indexed bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    )
    .expect("index external file");

    fs::remove_file(&source).expect("remove indexed source fixture");

    let files = list_files(path_string(repo.path()), empty_filter())
        .expect("list indexed metadata after source removal");

    assert_eq!(files, vec![entry.clone()]);
    assert_eq!(entry.storage_mode, StorageMode::Indexed);
    assert_eq!(count_rows(repo.path(), "files", Some("active")), 1);
    assert_eq!(count_rows(repo.path(), "change_log", None), 1);
    assert!(!repo.path().join("finance").exists());
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_index_file_integration_verify_db_failure_does_not_touch_source_or_final_repo() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"index rollback");
    install_import_change_log_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        indexed_options(),
    );

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(
        fs::read(&source).expect("read source after DB failure"),
        b"index rollback"
    );
    assert!(!repo.path().join("finance").exists());
    assert_eq!(count_rows(repo.path(), "files", Some("active")), 0);
    assert_eq!(count_rows(repo.path(), "files", Some("staging")), 0);
    assert_eq!(count_rows(repo.path(), "change_log", None), 0);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

fn assert_file_row_matches_indexed_import(repo: &Path, file_id: i64, source_path: &str) {
    let connection = open_db(repo);
    let (path, status, storage_mode, origin, source_path_db): (
        String,
        String,
        String,
        String,
        Option<String>,
    ) = connection
        .query_row(
            "SELECT path, status, storage_mode, origin, source_path FROM files WHERE id = ?1",
            [file_id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .expect("read indexed file row");

    assert_eq!(path, source_path);
    assert_eq!(status, "active");
    assert_eq!(storage_mode, "indexed");
    assert_eq!(origin, "imported");
    assert_eq!(source_path_db.as_deref(), Some(source_path));
}

fn assert_change_log_matches_indexed_import(repo: &Path, file_id: i64, source_path: &str) {
    let connection = open_db(repo);
    let (action, detail_json): (String, String) = connection
        .query_row(
            "SELECT action, detail_json FROM change_log WHERE file_id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read indexed import change log row");
    let detail: Value = serde_json::from_str(&detail_json).expect("parse import detail json");

    assert_eq!(action, "imported");
    assert_eq!(detail["source"], source_path);
    assert_eq!(detail["mode"], "indexed");
    assert_eq!(detail["category"], "finance");
    assert_eq!(detail["destination"], "auto_classify");
    assert_eq!(detail["renamed_from_original"], true);
}

fn install_import_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_import_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced import change log failure');
             END;",
        )
        .expect("install import change-log failure trigger");
}
