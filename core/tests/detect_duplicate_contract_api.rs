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

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

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

fn copied_options(strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: None,
        duplicate_strategy: strategy,
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

fn count_file_rows(repo: &Path, status: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = ?1",
            [status],
            |row| row.get(0),
        )
        .expect("count file rows by status")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

#[test]
fn detect_duplicate_contract_api_docs_udl_and_rust_error_carry_existing_path() {
    let error = CoreError::DuplicateFile {
        existing_path: "finance/existing.pdf".to_owned(),
    };
    match error {
        CoreError::DuplicateFile { existing_path } => {
            assert_eq!(existing_path, "finance/existing.pdf");
        }
        other => panic!("unexpected duplicate error shape: {other:?}"),
    }

    for fragment in [
        "C1-09 detect-duplicate",
        "`import_file(repo_path, source_path, options)` 内部 hash 检测。",
        "`DuplicateFile { existing_path }`",
        "`DuplicateStrategy`",
        "读取 `files.hash_sha256`。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-22 | conflict-duplicate | C1-09 | `import_file`",
        "| S1-24 | replace-confirm | C1-09, C1-10 | `import_file`, `delete_file`",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "[Error]",
        "interface CoreError",
        "DuplicateFile(string existing_path);",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "`DuplicateFile { existing_path }`",
        "用户决策",
        "跳过 / 覆盖 / 保留两份",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "C1-09 owns duplicate detection",
        "`CoreError::DuplicateFile { existing_path }`",
        "`KeepBoth` allows a",
    ] {
        assert_contains(API_RS, fragment);
    }
}

#[test]
fn detect_duplicate_skip_returns_existing_path_and_preserves_state() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(DuplicateStrategy::Skip),
    )
    .expect("import first copied file");
    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options(DuplicateStrategy::Skip),
    );

    let reported_path = match result {
        Err(CoreError::DuplicateFile { existing_path }) => existing_path,
        other => panic!("expected duplicate error with existing path, got {other:?}"),
    };
    assert_eq!(reported_path, first.path);
    assert_eq!(
        fs::read(&source_b).expect("read duplicate source after rejected import"),
        b"same bytes"
    );
    assert!(!repo.path().join("finance/second.pdf").exists());
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn detect_duplicate_keep_both_allows_second_active_row_when_paths_differ() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(DuplicateStrategy::Skip),
    )
    .expect("import first copied file");
    let second = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options(DuplicateStrategy::KeepBoth),
    )
    .expect("keep both duplicate file");

    assert_eq!(first.hash_sha256, second.hash_sha256);
    assert_eq!(first.path, "finance/first.pdf");
    assert_eq!(second.path, "finance/second.pdf");
    assert_eq!(count_file_rows(repo.path(), "active"), 2);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), 2);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let mut paths = list_files(path_string(repo.path()), empty_filter())
        .expect("list active duplicate files")
        .into_iter()
        .map(|entry| entry.path)
        .collect::<Vec<_>>();
    paths.sort();
    assert_eq!(paths, vec!["finance/first.pdf", "finance/second.pdf"]);
}
