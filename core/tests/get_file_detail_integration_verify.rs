use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_file, import_file, init_repo, CoreError, DuplicateStrategy, FileEntry, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const S1_12_DETAIL_META: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-12-detail-meta.md");
const S1_15_DETAIL_MULTI: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-15-detail-multi.md");
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
        target_directory: Some("docs/contracts".to_owned()),
        override_category: None,
        override_filename: Some("2026Q1_contract.pdf".to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
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
        .expect("count change-log rows")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn insert_file_with_status(repo: &Path, path: &str, status: &str, imported_at: i64) -> i64 {
    let current_name = path.rsplit('/').next().expect("test path has a filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'finance', 4096,
                ?3, 'copied', 'imported', NULL,
                ?4, ?4, ?5
             )",
            params![
                path,
                current_name,
                format!("{imported_at:064x}"),
                imported_at,
                status,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

#[test]
fn get_file_detail_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    for fragment in [
        "C1-12 get-file-detail",
        "- S1-12 detail-meta",
        "- S1-15 detail-multi",
        "- `get_file(repo_path, file_id) -> FileEntry`",
        "- 单个 `FileEntry`。",
        "- 无写入。",
        "- 可选 metadata 检查，但不得修改文件。",
        "- `FileNotFound`",
        "- `RepoNotInitialized`",
        "- `Db`",
        "- 存在文件返回完整字段。",
        "- Detail UI 不需要从文件路径反推 DB 字段。",
        "- 文件预览、Quick Look 和 OCR 元数据属于 macOS/Stage 2+。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "FileEntry get_file(string repo_path, i64 file_id);",
        "dictionary FileEntry",
        "i64 id;",
        "string path;",
        "string original_name;",
        "string current_name;",
        "string category;",
        "i64 size_bytes;",
        "string hash_sha256;",
        "StorageMode storage_mode;",
        "FileOrigin origin;",
        "string? source_path;",
        "i64 imported_at;",
        "i64 updated_at;",
        "FileNotFound();",
        "RepoNotInitialized();",
        "Db();",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| S1-12 | detail-meta | C1-12 | `get_file`",
        "| S1-15 | detail-multi | C1-11, C1-12 | `list_files`, `get_file`",
        "Core 能力若未在本矩阵出现，默认不得提前进入 Stage 1 实现。",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "FileEntry metadata。",
        "Detail metadata loading/error state。",
        "加载失败：保留文件名和相对路径",
        "诊断不包含用户文件内容。",
    ] {
        assert_contains(S1_12_DETAIL_META, fragment);
    }

    for fragment in [
        "本页不单独发起加载请求；统计信息来自当前 List selection 和已加载 metadata。",
        "页面不提供任何批量写入动作。",
        "Copy Paths 不修改文件或索引。",
    ] {
        assert_contains(S1_15_DETAIL_MULTI, fragment);
    }

    for fragment in [
        "C1-12 defines this as the read-only detail query",
        "returns exactly one active [`FileEntry`]",
        "This API has no write side effects.",
        "File preview, Quick Look, OCR metadata",
        "change-log aggregation, and note aggregation belong to adjacent capabilities",
    ] {
        assert_contains(API_RS, fragment);
    }
}

#[test]
fn get_file_detail_integration_verify_real_detail_supports_detail_meta_without_side_effects() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("contract.pdf", b"contract bytes");
    let source_before = fs::read(&source).expect("read source before import");

    let imported = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("import copied file for detail");
    let change_logs_before = change_log_count(repo.path());

    let detail = get_file(path_string(repo.path()), imported.id).expect("get file detail");

    assert_detail_matches_import(&detail, &imported);
    assert_eq!(
        fs::read(&source).expect("read source after detail query"),
        source_before
    );
    assert_eq!(
        fs::read(repo.path().join(&detail.path)).expect("read final file after detail query"),
        source_before
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "staging"), 0);
    assert_eq!(change_log_count(repo.path()), change_logs_before);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn get_file_detail_integration_verify_returns_structured_errors_for_non_visible_rows() {
    let uninitialized = tempfile::tempdir().expect("create uninitialized repository");
    assert_eq!(
        get_file(path_string(uninitialized.path()), 1),
        Err(CoreError::RepoNotInitialized)
    );

    let repo = initialized_repo();
    let deleted_id = insert_file_with_status(repo.path(), "finance/deleted.pdf", "deleted", 10);
    let staging_id = insert_file_with_status(repo.path(), "finance/staging.pdf", "staging", 20);

    assert_eq!(
        get_file(path_string(repo.path()), 404),
        Err(CoreError::FileNotFound)
    );
    assert_eq!(
        get_file(path_string(repo.path()), deleted_id),
        Err(CoreError::FileNotFound)
    );
    assert_eq!(
        get_file(path_string(repo.path()), staging_id),
        Err(CoreError::FileNotFound)
    );
    assert_eq!(count_file_rows(repo.path(), "deleted"), 1);
    assert_eq!(count_file_rows(repo.path(), "staging"), 1);
    assert_eq!(change_log_count(repo.path()), 0);
}

fn assert_detail_matches_import(detail: &FileEntry, imported: &FileEntry) {
    assert_eq!(detail, imported);
    assert_eq!(detail.path, "docs/contracts/2026Q1_contract.pdf");
    assert_eq!(detail.original_name, "contract.pdf");
    assert_eq!(detail.current_name, "2026Q1_contract.pdf");
    assert_eq!(detail.category, "docs");
    assert_eq!(detail.storage_mode, StorageMode::Copied);
    assert_eq!(detail.source_path.is_some(), true);
}
