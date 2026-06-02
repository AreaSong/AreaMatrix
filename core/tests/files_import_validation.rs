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
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-29-c4-06-validation.md"
);
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-4-multiplatform/C4-06-files-import.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const FILES_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-07-files-import.md");
const REPLACE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-09-replace-confirm.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CONTRACT_TEST: &str = include_str!("files_import_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("files_import_implementation.rs");
const FAILURE_TEST: &str = include_str!("files_import_failure_recovery.rs");

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
        .expect("initialize repository for files import validation");
    repo
}

fn files_provider_selection(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let provider_scope = tempfile::tempdir().expect("create files-provider scope directory");
    let source_path = provider_scope.path().join(name);
    fs::write(&source_path, content).expect("write selected files-provider fixture");
    (provider_scope, source_path)
}

fn files_options(filename: &str, duplicate_strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("inbox".to_owned()),
        override_filename: Some(filename.to_owned()),
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
        .expect("count change log rows");
    (active, staging, changes)
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn assert_no_files_import_side_effects(repo: &Path) {
    assert_eq!(metadata_counts(repo), (0, 0, 0));
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
    assert!(!repo.join("inbox").exists());
}

fn import_change_detail(repo: &Path, file_id: i64) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log WHERE file_id = ?1 AND action = 'imported'",
            [file_id],
            |row| row.get(0),
        )
        .expect("read files import change detail");
    serde_json::from_str(&detail_json).expect("parse files import detail JSON")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_imported_files_entry(entry: &FileEntry, source_path: &str) {
    assert_eq!(entry.path, "inbox/Files Statement.pdf");
    assert_eq!(entry.original_name, "statement.pdf");
    assert_eq!(entry.current_name, "Files Statement.pdf");
    assert_eq!(entry.category, "inbox");
    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(entry.source_path.as_deref(), Some(source_path));
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Available);
}

fn assert_import_detail_matches_files_import(
    detail: &Value,
    source_path: &str,
    entry: &FileEntry,
) {
    assert_eq!(detail["source"].as_str(), Some(source_path));
    assert_eq!(detail["mode"].as_str(), Some("copied"));
    assert_eq!(detail["category"].as_str(), Some("inbox"));
    assert_eq!(detail["destination"].as_str(), Some("auto_classify"));
    assert_eq!(detail["requested_name"].as_str(), Some("Files Statement.pdf"));
    assert_eq!(detail["final_path"].as_str(), Some(entry.path.as_str()));
    assert_eq!(detail["name_conflict_resolved"].as_bool(), Some(false));
    assert!(
        !detail.to_string().contains("files-provider secret bytes"),
        "change log must not contain selected file contents"
    );
}

#[test]
fn files_import_validation_proves_ui_ready_success_path() {
    let repo = initialized_repo();
    let (_provider_scope, selected) =
        files_provider_selection("statement.pdf", b"files-provider secret bytes");
    let selected_before = fs::read(&selected).expect("read selected provider file before import");
    let selected_path = path_string(&selected);

    let preview = predict_category(path_string(repo.path()), "statement.pdf".to_owned())
        .expect("preview selected files-provider item");
    assert_eq!(preview.category, "docs");
    assert_eq!(metadata_counts(repo.path()), (0, 0, 0));

    let entry = import_file(
        path_string(repo.path()),
        selected_path.clone(),
        files_options("Files Statement.pdf", DuplicateStrategy::KeepBoth),
    )
    .expect("import authorized files-provider selection");

    assert_eq!(
        fs::read(&selected).expect("read selected provider file after import"),
        selected_before
    );
    assert_imported_files_entry(&entry, &selected_path);
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read copied repo file"),
        selected_before
    );

    let listed =
        list_files(path_string(repo.path()), empty_filter()).expect("list imported Files item");
    assert_eq!(listed, vec![entry.clone()]);
    assert_eq!(metadata_counts(repo.path()), (1, 0, 1));
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let detail = import_change_detail(repo.path(), entry.id);
    assert_import_detail_matches_files_import(&detail, &selected_path, &entry);
}

#[test]
fn files_import_validation_rejects_cancel_and_placeholder_without_side_effects() {
    let repo = initialized_repo();
    let (_cancel_scope, cancelled) =
        files_provider_selection("cancelled.pdf", b"cancelled selection bytes");

    assert_eq!(
        fs::read(&cancelled).expect("read cancelled Files selection"),
        b"cancelled selection bytes"
    );
    assert_no_files_import_side_effects(repo.path());

    let (_provider_scope, placeholder) =
        files_provider_selection("remote.pdf.icloud", b"placeholder marker");
    let result = import_file(
        path_string(repo.path()),
        path_string(&placeholder),
        files_options("Remote.pdf", DuplicateStrategy::KeepBoth),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::ICloudPlaceholder { path }) if path == path_string(&placeholder)
        ),
        "iCloud placeholder should return a structured provider-path error"
    );
    assert_eq!(
        fs::read(&placeholder).expect("provider placeholder remains untouched"),
        b"placeholder marker"
    );
    assert_no_files_import_side_effects(repo.path());
}

#[test]
fn files_import_validation_duplicate_skip_keeps_existing_state() {
    let repo = initialized_repo();
    let (_first_scope, first_source) =
        files_provider_selection("first.pdf", b"duplicate files bytes");
    let first = import_file(
        path_string(repo.path()),
        path_string(&first_source),
        files_options("Files Statement.pdf", DuplicateStrategy::KeepBoth),
    )
    .expect("import first Files selection");
    let first_file = repo.path().join(&first.path);
    let first_bytes = fs::read(&first_file).expect("read first imported file");

    let (_duplicate_scope, duplicate_source) =
        files_provider_selection("second.pdf", b"duplicate files bytes");
    let result = import_file(
        path_string(repo.path()),
        path_string(&duplicate_source),
        files_options("Second Statement.pdf", DuplicateStrategy::Skip),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path }) if existing_path == first.path
        ),
        "duplicate skip should report the existing imported Files path"
    );
    assert_eq!(
        fs::read(&duplicate_source).expect("duplicate provider file remains untouched"),
        b"duplicate files bytes"
    );
    assert_eq!(
        fs::read(&first_file).expect("first imported file remains unchanged"),
        first_bytes
    );
    assert_eq!(metadata_counts(repo.path()), (1, 0, 1));
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn files_import_validation_locks_core_api_udl_rust_and_test_evidence() {
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
        "# 4-3/task-29: C4-06 validation",
        "为 C4-06 files-import 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-29",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-06 files-import",
        "- S4-IOS-07 files-import",
        "- `import_file`",
        "- `predict_category`",
        "iOS Files provider 授权后的 file URL。",
        "导入预览和导入结果。",
        "文件未下载/无权限时给出结构化状态。",
        "Replace 必须进入 S4-X-09。",
        "Cancel 不写 DB。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-07 | files-import | C4-06, C4-21 | Files import / replace confirm",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
        "初始化、接管、Replace、Remove record、rescan 都必须确认后执行。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    assert_files_page_alignment();
    assert_replace_page_alignment();
    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`", "关键测试场景"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_files_page_alignment() {
    for fragment in [
        "不实现 Share Extension，也不在选择完成前写入 repo。",
        "仅提供 `Copy into repository`，不显示 `Move` 或 `Index in place`。",
        "默认冲突策略为安全策略：重复内容 `Skip duplicate`，同名不同内容 `Keep both`。",
        "Replace 选项如展示，必须标为危险，并在应用前进入 `S4-X-09 replace-confirm`。",
        "用户取消时不写入 repo，也不删除 Files app 中的源文件。",
        "默认保存方式只复制到 repo，不移动源文件。",
        "导入成功后资料库列表立即可见新文件。",
    ] {
        assert_contains(FILES_PAGE, fragment);
    }
}

fn assert_replace_page_alignment() {
    for fragment in [
        "入口：`S4-WIN-05 import-flow`、`S4-LNX-05 import-flow`、`S4-IOS-07 files-import`",
        "iOS：不保证系统回收站，优先保留两份；Replace 默认隐藏，除非 Core 提供安全备份。",
        "Core conflict/import replacement API。",
        "Replace 前必定出现二次确认。",
        "iOS 不默认显示 Replace，除非有安全备份能力。",
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
        "string? override_category;",
        "string? override_filename;",
        "DuplicateStrategy duplicate_strategy;",
        "dictionary FileEntry",
        "StorageMode storage_mode;",
        "FileOrigin origin;",
        "string? source_path;",
        "FileAvailabilityStatus availability_status;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "enum ImportDestination { \"AutoClassify\", \"SelectedDirectory\", \"Category\" };",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
        "ICloudPlaceholder(string path);",
        "PermissionDenied(string path);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    assert_core_api_behavior_alignment();
    assert_rust_implementation_alignment();
}

fn assert_core_api_behavior_alignment() {
    for fragment in [
        "| `import_file(repo, src, options)` | storage | √ | Io / Db / DuplicateFile / Conflict / InvalidPath / ICloudPlaceholder / PermissionDenied |",
        "可能抛：`Io` / `Db` / `DuplicateFile` / `Conflict` / `InvalidPath` / `ICloudPlaceholder` / `PermissionDenied` / `Internal`。",
        "`ImportOptions.destination` 语义：",
        "catch CoreError.ICloudPlaceholder(let p)",
        "catch CoreError.PermissionDenied(let p)",
        "无写入副作用：只读取 `.areamatrix/classifier.yaml`，不创建、不移动、",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_rust_implementation_alignment() {
    for fragment in [
        "C4-06 files-import reuses this read-only preview surface",
        "Files provider or document picker has granted access",
        "Core only predicts a category/name from the authorized",
        "C4-06 files-import reuses `StorageMode::Copied` import semantics",
        "Core receives only the authorized path plus",
        "does not open the document picker, retain",
        "security-scoped bookmarks, trigger provider downloads, move source files, or",
        "perform C4-21 replace confirmation",
        "Cancelled selections stay in the",
        "storage::import_file(repo_path, source_path, options)",
    ] {
        assert_contains(API_RS, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "files_import_contract_exports_existing_import_and_preview_signatures",
        "files_import_docs_core_api_and_udl_stay_aligned",
        "files_import_documents_consumer_state_and_platform_boundaries",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "files_import_implementation_copies_authorized_provider_file_into_repo",
        "files_import_implementation_cancel_without_core_call_writes_no_state",
        "files_import_implementation_duplicate_skip_preserves_existing_import",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "files_import_failure_recovery_icloud_placeholder_maps_and_writes_no_state",
        "files_import_failure_recovery_permission_denied_keeps_provider_file_and_repo_clean",
        "files_import_failure_recovery_db_error_removes_final_file_and_can_retry",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
