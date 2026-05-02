use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, CoreError, DuplicateStrategy, FileFilter,
    ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const S1_17_IMPORT_SINGLE: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md");
const S1_20_IMPORT_PROGRESS: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md");
const S1_21_IMPORT_RESULT: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md");
const S1_26_SETTINGS_GENERAL: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-26-settings-general.md");
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

fn moved_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Moved,
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
fn import_move_file_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    for fragment in [
        "`import_file(repo_path, source_path, ImportOptions { mode: Moved, ... }) -> FileEntry`",
        "- 原路径被安全移入资料库最终位置。",
        "- `files.storage_mode = Moved`。",
        "- `files.source_path` 记录原始来源。",
        "- `change_log.action = imported`。",
        "源文件移动到 staging，再原子 rename 到最终目录。",
        "移动失败必须保留源文件或可恢复 staging，不丢数据。",
        "与 Copy 模式共享重复检测和同名冲突处理。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "FileEntry import_file(",
        "string repo_path, string source_path, ImportOptions options",
        "dictionary ImportOptions",
        "StorageMode mode;",
        "ImportDestination destination;",
        "DuplicateStrategy duplicate_strategy;",
        "dictionary FileEntry",
        "StorageMode storage_mode;",
        "FileOrigin origin;",
        "string? source_path;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| S1-17 | import-single-sheet | C1-05, C1-06, C1-07, C1-08 | `predict_category`, `import_file`",
        "| S1-20 | import-progress | C1-06, C1-07, C1-08 | `import_file`",
        "| S1-21 | import-result | C1-06, C1-13 | `import_file`, `list_changes`",
        "| S1-26 | settings-general | C1-04, C1-07 | `load_config`, `update_config`",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    assert_contains(S1_17_IMPORT_SINGLE, "Move：说明源文件会从原位置移走。");
    assert_contains(S1_17_IMPORT_SINGLE, "Import 进入 `S1-20 import-progress`");
    assert_contains(
        S1_20_IMPORT_PROGRESS,
        "Core 正在 staging、hash、分类、复制/移动、写 DB",
    );
    assert_contains(
        S1_20_IMPORT_PROGRESS,
        "停止剩余导入不会留下 staging 悬挂记录。",
    );
    assert_contains(S1_21_IMPORT_RESULT, "成功项已经出现在列表中。");
    assert_contains(S1_26_SETTINGS_GENERAL, "设置 Move 为默认：弹确认");
    assert_contains(API_RS, "C1-07 defines the moved-file contract");
}

#[test]
fn import_move_file_integration_verify_real_move_supports_consuming_context() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"invoice bytes");
    let source_before = fs::read(&source).expect("read source before import");
    let source_path = path_string(&source);

    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        moved_options(),
    )
    .expect("import moved file");

    assert!(!source.exists(), "moved import should consume source");
    assert_eq!(entry.path, "finance/2026Q1_invoice.pdf");
    assert_eq!(entry.original_name, "invoice.pdf");
    assert_eq!(entry.current_name, "2026Q1_invoice.pdf");
    assert_eq!(entry.category, "finance");
    assert_eq!(entry.storage_mode, StorageMode::Moved);
    assert_eq!(entry.source_path.as_deref(), Some(source_path.as_str()));
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read final moved file"),
        source_before
    );

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list active files");
    assert_eq!(files, vec![entry.clone()]);

    assert_file_row_matches_move(repo.path(), entry.id, &entry.path, &source);
    assert_change_log_matches_move(repo.path(), entry.id, &source);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_move_file_integration_verify_failure_restores_source_and_final_state() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("invoice.pdf", b"invoice bytes");
    install_import_change_log_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        moved_options(),
    );

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(
        fs::read(&source).expect("read source after failed move"),
        b"invoice bytes"
    );
    assert!(!repo.path().join("finance/2026Q1_invoice.pdf").exists());
    assert!(!repo.path().join("finance").exists());
    assert_eq!(count_rows(repo.path(), "files", Some("active")), 0);
    assert_eq!(count_rows(repo.path(), "files", Some("staging")), 0);
    assert_eq!(count_rows(repo.path(), "change_log", None), 0);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn import_move_file_integration_verify_indexed_mode_does_not_move_source() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("index-later.pdf", b"source bytes");
    let source_path = path_string(&source);
    let mut options = moved_options();
    options.mode = StorageMode::Indexed;

    let entry =
        import_file(path_string(repo.path()), source_path.clone(), options).expect("index file");

    assert_eq!(fs::read(&source).expect("read source"), b"source bytes");
    assert_eq!(entry.path, source_path);
    assert_eq!(entry.storage_mode, StorageMode::Indexed);
    assert_eq!(entry.source_path.as_deref(), Some(source_path.as_str()));
    assert!(!repo.path().join("finance/2026Q1_invoice.pdf").exists());
    assert_eq!(count_rows(repo.path(), "files", Some("active")), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
    assert_contains(API_RS, "C1-08 owns index-only semantics");
}

fn assert_file_row_matches_move(repo: &Path, file_id: i64, entry_path: &str, source: &Path) {
    let connection = open_db(repo);
    let (path, status, storage_mode, source_path): (String, String, String, Option<String>) =
        connection
            .query_row(
                "SELECT path, status, storage_mode, source_path FROM files WHERE id = ?1",
                [file_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read moved file row");

    assert_eq!(path, entry_path);
    assert_eq!(status, "active");
    assert_eq!(storage_mode, "moved");
    assert_eq!(source_path.as_deref(), Some(path_string(source).as_str()));
}

fn assert_change_log_matches_move(repo: &Path, file_id: i64, source: &Path) {
    let connection = open_db(repo);
    let (action, detail_json): (String, String) = connection
        .query_row(
            "SELECT action, detail_json FROM change_log WHERE file_id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read moved import change log row");
    let detail: Value = serde_json::from_str(&detail_json).expect("parse import detail json");

    assert_eq!(action, "imported");
    assert_eq!(detail["source"], path_string(source));
    assert_eq!(detail["mode"], "moved");
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
