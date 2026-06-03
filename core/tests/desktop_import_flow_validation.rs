use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, predict_category, ClassifyResult, CoreError, CoreResult,
    DuplicateStrategy, FileAvailabilityStatus, FileEntry, FileFilter, FileOrigin,
    ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-64-c4-13-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-13-desktop-import-flow.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const WINDOWS_IMPORT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-05-import-flow.md");
const LINUX_IMPORT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-LNX-05-import-flow.md");
const REPLACE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-09-replace-confirm.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CONTRACT_TEST: &str = include_str!("desktop_import_flow_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("desktop_import_flow_implementation.rs");
const FAILURE_TEST: &str = include_str!("desktop_import_flow_failure_recovery.rs");

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
    .expect("initialize repository for desktop import validation");
    repo
}

fn desktop_selection(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let picker_scope = tempfile::tempdir().expect("create desktop picker scope directory");
    let source_path = picker_scope.path().join(name);
    fs::write(&source_path, content).expect("write desktop picker fixture");
    (picker_scope, source_path)
}

fn desktop_options(mode: StorageMode, duplicate_strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("desktop/imports".to_owned()),
        override_category: None,
        override_filename: None,
        duplicate_strategy,
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

fn metadata_counts(repo: &Path) -> (i64, i64, i64) {
    let connection = open_db(repo);
    let active = connection
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active files");
    let staging = connection
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'staging'",
            [],
            |row| row.get(0),
        )
        .expect("count staging files");
    let changes = connection
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows");
    (active, staging, changes)
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn assert_no_desktop_import_side_effects(repo: &Path) {
    assert_eq!(metadata_counts(repo), (0, 0, 0));
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
    assert!(!repo.join("desktop").exists());
}

fn import_change_detail(repo: &Path, file_id: i64) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log WHERE file_id = ?1 AND action = 'imported'",
            [file_id],
            |row| row.get(0),
        )
        .expect("read desktop import change detail");
    serde_json::from_str(&detail_json).expect("parse desktop import detail JSON")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_contains_normalized(haystack: &str, needle: &str) {
    let normalized_haystack = normalize_text(haystack);
    let normalized_needle = needle.split_whitespace().collect::<Vec<_>>().join(" ");
    assert!(
        normalized_haystack.contains(&normalized_needle),
        "expected normalized text to contain `{needle}`"
    );
}

fn normalize_text(text: &str) -> String {
    text.replace("///", "").replace("//", "").split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

#[test]
fn desktop_import_flow_validation_proves_ui_ready_copy_success_path() {
    let repo = initialized_repo();
    let (_picker_scope, source) = desktop_selection("Desktop Report.pdf", b"desktop secret bytes");
    let source_before = fs::read(&source).expect("read desktop picker source before import");
    let source_path = path_string(&source);

    let preview = predict_category(path_string(repo.path()), "Desktop Report.pdf".to_owned())
        .expect("preview desktop import category");
    assert_eq!(preview.category, "docs");
    assert_eq!(preview.suggested_name, "Desktop Report.pdf");
    assert_eq!(metadata_counts(repo.path()), (0, 0, 0));

    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        desktop_options(StorageMode::Copied, DuplicateStrategy::KeepBoth),
    )
    .expect("import desktop picker source with safe copy default");

    assert_eq!(
        fs::read(&source).expect("read desktop picker source after copy import"),
        source_before
    );
    assert_imported_copy_entry(&entry, &source_path);
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read copied desktop repo file"),
        source_before
    );

    let listed =
        list_files(path_string(repo.path()), empty_filter()).expect("list desktop import result");
    assert_eq!(listed, vec![entry.clone()]);
    assert_eq!(metadata_counts(repo.path()), (1, 0, 1));
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let detail = import_change_detail(repo.path(), entry.id);
    assert_import_detail_matches_desktop_copy(&detail, &source_path, &entry);
}

fn assert_imported_copy_entry(entry: &FileEntry, source_path: &str) {
    assert_eq!(entry.path, "desktop/imports/Desktop Report.pdf");
    assert_eq!(entry.original_name, "Desktop Report.pdf");
    assert_eq!(entry.current_name, "Desktop Report.pdf");
    assert_eq!(entry.category, "desktop");
    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(entry.source_path.as_deref(), Some(source_path));
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Available);
}

fn assert_import_detail_matches_desktop_copy(
    detail: &Value,
    source_path: &str,
    entry: &FileEntry,
) {
    assert_eq!(detail["source"].as_str(), Some(source_path));
    assert_eq!(detail["mode"].as_str(), Some("copied"));
    assert_eq!(detail["category"].as_str(), Some("desktop"));
    assert_eq!(detail["destination"].as_str(), Some("selected_directory"));
    assert_eq!(
        detail["requested_name"].as_str(),
        Some("Desktop Report.pdf")
    );
    assert_eq!(detail["final_path"].as_str(), Some(entry.path.as_str()));
    assert_eq!(detail["name_conflict_resolved"].as_bool(), Some(false));
    assert!(
        !detail.to_string().contains("desktop secret bytes"),
        "change log must not contain imported file contents"
    );
}

#[test]
fn desktop_import_flow_validation_proves_move_and_index_modes() {
    let repo = initialized_repo();
    let (_move_scope, move_source) = desktop_selection("move.txt", b"move validation bytes");
    let move_source_path = path_string(&move_source);
    let (_index_scope, index_source) = desktop_selection("index.txt", b"index validation bytes");
    let index_source_path = path_string(&index_source);

    let moved = import_file(
        path_string(repo.path()),
        move_source_path.clone(),
        desktop_options(StorageMode::Moved, DuplicateStrategy::KeepBoth),
    )
    .expect("commit desktop move import after platform confirmation");
    let indexed = import_file(
        path_string(repo.path()),
        index_source_path.clone(),
        desktop_options(StorageMode::Indexed, DuplicateStrategy::KeepBoth),
    )
    .expect("commit desktop indexed import");

    assert!(!move_source.exists());
    assert_eq!(moved.path, "desktop/imports/move.txt");
    assert_eq!(moved.storage_mode, StorageMode::Moved);
    assert_eq!(moved.source_path.as_deref(), Some(move_source_path.as_str()));
    assert_eq!(
        fs::read(repo.path().join(&moved.path)).expect("read moved desktop repo file"),
        b"move validation bytes"
    );

    assert_eq!(indexed.path, index_source_path);
    assert_eq!(indexed.storage_mode, StorageMode::Indexed);
    assert_eq!(
        fs::read(&index_source).expect("read indexed desktop source"),
        b"index validation bytes"
    );
    assert!(!repo.path().join("desktop/imports/index.txt").exists());
    assert_eq!(metadata_counts(repo.path()), (2, 0, 2));
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn desktop_import_flow_validation_rejects_failures_without_success_state() {
    let repo = initialized_repo();
    let empty_source = import_file(
        path_string(repo.path()),
        String::new(),
        desktop_options(StorageMode::Copied, DuplicateStrategy::KeepBoth),
    );
    assert!(matches!(empty_source, Err(CoreError::InvalidPath { .. })));
    assert_no_desktop_import_side_effects(repo.path());

    let (_first_scope, first_source) = desktop_selection("first.pdf", b"duplicate desktop bytes");
    let first = import_file(
        path_string(repo.path()),
        path_string(&first_source),
        desktop_options(StorageMode::Copied, DuplicateStrategy::KeepBoth),
    )
    .expect("import first desktop duplicate fixture");
    let first_file = repo.path().join(&first.path);
    let first_bytes = fs::read(&first_file).expect("read first desktop import");

    let (_duplicate_scope, duplicate_source) =
        desktop_selection("duplicate.pdf", b"duplicate desktop bytes");
    let duplicate = import_file(
        path_string(repo.path()),
        path_string(&duplicate_source),
        desktop_options(StorageMode::Copied, DuplicateStrategy::Ask),
    );
    assert_duplicate_error_preserves_state(repo.path(), duplicate, &first, &first_bytes);
    assert_eq!(
        fs::read(&duplicate_source).expect("duplicate desktop source remains untouched"),
        b"duplicate desktop bytes"
    );
}

fn assert_duplicate_error_preserves_state(
    repo: &Path,
    duplicate: CoreResult<FileEntry>,
    first: &FileEntry,
    first_bytes: &[u8],
) {
    assert!(
        matches!(
            duplicate,
            Err(CoreError::DuplicateFile { existing_path }) if existing_path == first.path
        ),
        "duplicate Ask must return structured state instead of success"
    );
    assert_eq!(
        fs::read(repo.join(&first.path)).expect("read existing desktop import"),
        first_bytes
    );
    assert!(!repo.join("desktop/imports/duplicate.pdf").exists());
    assert_eq!(metadata_counts(repo), (1, 0, 1));
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

#[test]
fn desktop_import_flow_validation_locks_core_api_udl_rust_and_test_evidence() {
    fn assert_predict(_: fn(String, String) -> CoreResult<ClassifyResult>) {}
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}

    assert_predict(predict_category);
    assert_import(import_file);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-64: C4-13 validation",
        "为 C4-13 desktop-import-flow 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-64",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-13 desktop-import-flow",
        "- S4-WIN-05 import-flow",
        "- S4-LNX-05 import-flow",
        "- `predict_category`",
        "- `import_file`",
        "平台 file picker 返回路径和 ImportOptions。",
        "Copy/Move/Index 按配置执行。",
        "Replace 必须走 S4-X-09。",
        "平台 Trash 不可用时禁止 destructive 路径。",
        "导入失败不显示成功状态。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-WIN-05 | import-flow | C4-13, C4-21 | desktop import / replace",
        "| S4-LNX-05 | import-flow | C4-13, C4-21 | desktop import / replace",
        "| S4-X-09 | replace-confirm | C4-16, C4-21 | replace confirm",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    assert_desktop_page_alignment();
    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`", "关键测试场景"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_desktop_page_alignment() {
    for fragment in [
        "Windows file/folder picker。",
        "Core transactional import API。",
        "Move preflight：源文件可读、源位置可删除/移动、目标可写、staging 可用。",
        "同名不同内容默认保留两份。",
        "成功导入后文件系统和 DB 都可见。",
    ] {
        assert_contains(WINDOWS_IMPORT_PAGE, fragment);
    }

    for fragment in [
        "Linux file/folder picker 或 xdg-desktop-portal。",
        "Core transactional import API。",
        "Move preflight：源文件可读、源目录可 unlink/rename、目标可写、staging 可用、same-mount / cross-mount 判断。",
        "Move preflight：必须确认源文件可读、源目录允许 unlink/rename、目标 repo 可写、staging 可用；跨挂载时必须走 copy-to-staging 再 remove original",
        "同名冲突默认保留两份。",
        "导入失败：不留下最终目录半成品；staging recovery 状态必须可被下次启动恢复或清理。",
    ] {
        assert_contains(LINUX_IMPORT_PAGE, fragment);
    }

    for fragment in [
        "入口：`S4-WIN-05 import-flow`、`S4-LNX-05 import-flow`",
        "Replace 前必定出现二次确认。",
        "Trash/Recycle Bin Unknown：按不可用处理，禁用 Replace",
        "不可逆 Replace 在 Stage 4 不可被执行。",
    ] {
        assert_contains(REPLACE_PAGE, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    for fragment in [
        "ClassifyResult predict_category(string repo_path, string filename);",
        "FileEntry import_file(",
        "string repo_path, string source_path, ImportOptions options",
        "dictionary ImportOptions",
        "StorageMode mode;",
        "ImportDestination destination;",
        "string? target_directory;",
        "string? override_category;",
        "string? override_filename;",
        "DuplicateStrategy duplicate_strategy;",
        "dictionary FileEntry",
        "StorageMode storage_mode;",
        "FileOrigin origin;",
        "string? source_path;",
        "FileAvailabilityStatus availability_status;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
        "InvalidPath(string path);",
        "PermissionDenied(string path);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    assert_core_api_behavior_docs();
    assert_rust_api_docs();
}

fn assert_core_api_behavior_docs() {
    for fragment in [
        "### `predict_category(repoPath: String, filename: String) throws -> ClassifyResult`",
        "### `import_file(repoPath, sourcePath, options) throws -> FileEntry`",
        "无写入副作用：只读取 `.areamatrix/classifier.yaml`",
        "可能抛：`Io` / `Db` / `DuplicateFile` / `Conflict` / `InvalidPath` / `ICloudPlaceholder` / `PermissionDenied` / `Internal`。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_rust_api_docs() {
    for fragment in [
        "pub fn predict_category(repo_path: String, filename: String) -> CoreResult<ClassifyResult>",
        "pub fn import_file(",
        "C4-13 desktop-import-flow reuses this read-only preview surface",
        "Windows and Linux import dialogs",
        "Directory expansion, platform permission preflight",
        "Trash/Recycle Bin capability",
        "C4-13 desktop-import-flow reuses this same import contract",
        "folder recursion, batching, drag-and-drop",
        "`StorageMode::Copied` is the safe default",
        "`DuplicateStrategy::Overwrite` is only valid after the separate C4-21",
        "must surface an error instead of a success state",
        "storage::import_file(repo_path, source_path, options)",
    ] {
        assert_contains_normalized(API_RS, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "desktop_import_flow_contract_exports_existing_import_and_preview_signatures",
        "desktop_import_flow_docs_core_api_and_udl_stay_aligned",
        "desktop_import_flow_documents_consumer_state_without_adjacent_capabilities",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "desktop_import_flow_implementation_previews_category_then_commits_copy",
        "desktop_import_flow_implementation_commits_move_and_index_modes",
        "desktop_import_flow_implementation_duplicate_ask_surfaces_error_without_success_state",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "desktop_import_flow_failure_recovery_empty_invalid_inputs_return_explicit_errors",
        "desktop_import_flow_failure_recovery_db_failure_removes_copy_half_product",
        "desktop_import_flow_failure_recovery_db_failure_restores_moved_source",
        "desktop_import_flow_failure_recovery_conflict_keeps_source_and_existing_files",
        "desktop_import_flow_failure_recovery_permission_denied_has_no_success_state",
        "desktop_import_flow_failure_recovery_maps_error_codes_without_string_parsing",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
