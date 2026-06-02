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
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-24-c4-05-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-05-share-extension-import.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const SHARE_PAGE: &str = include_str!(
    "../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-04-share-extension-import.md"
);
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CONTRACT_TEST: &str = include_str!("share_extension_import_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("share_extension_import_implementation.rs");
const FAILURE_TEST: &str = include_str!("share_extension_import_failure_recovery.rs");

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
        .expect("initialize repository for share import validation");
    repo
}

fn share_payload(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let app_group = tempfile::tempdir().expect("create app-group staging directory");
    let source_path = app_group.path().join(name);
    fs::write(&source_path, content).expect("write staged share payload fixture");
    (app_group, source_path)
}

fn share_options(filename: &str, duplicate_strategy: DuplicateStrategy) -> ImportOptions {
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

fn assert_no_share_import_side_effects(repo: &Path) {
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
        .expect("read share import change detail");
    serde_json::from_str(&detail_json).expect("parse share import detail JSON")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_imported_share_entry(entry: &FileEntry, source_path: &str) {
    assert_eq!(entry.path, "inbox/Shared Article.pdf");
    assert_eq!(entry.original_name, "article.pdf");
    assert_eq!(entry.current_name, "Shared Article.pdf");
    assert_eq!(entry.category, "inbox");
    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(entry.source_path.as_deref(), Some(source_path));
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Available);
}

fn assert_import_detail_matches_share_import(detail: &Value, source_path: &str, entry: &FileEntry) {
    assert_eq!(detail["source"], source_path);
    assert_eq!(detail["mode"], "copied");
    assert_eq!(detail["category"], "inbox");
    assert_eq!(detail["destination"], "auto_classify");
    assert_eq!(detail["requested_name"], "Shared Article.pdf");
    assert_eq!(detail["final_path"], entry.path);
    assert_eq!(detail["name_conflict_resolved"], false);
    assert!(
        !detail.to_string().contains("private payload marker"),
        "change log must not contain external app payload bytes"
    );
}

#[test]
fn share_extension_import_validation_proves_ui_ready_success_path() {
    let repo = initialized_repo();
    let (_app_group, source) = share_payload("article.pdf", b"private payload marker");
    let source_before = fs::read(&source).expect("read staged share payload before import");
    let source_path = path_string(&source);

    let prediction = predict_category(path_string(repo.path()), "article.pdf".to_owned())
        .expect("preview shared item category");
    assert_eq!(prediction.category, "docs");
    assert_eq!(metadata_counts(repo.path()), (0, 0, 0));

    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        share_options("Shared Article.pdf", DuplicateStrategy::KeepBoth),
    )
    .expect("import staged share payload");

    assert_eq!(
        fs::read(&source).expect("read platform-owned staged share payload"),
        source_before
    );
    assert_imported_share_entry(&entry, &source_path);
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read copied share import"),
        source_before
    );

    fs::remove_file(&source).expect("platform can clean app-group payload after import");
    assert!(
        repo.path().join(&entry.path).is_file(),
        "Core must not tie final repo file lifetime to app-group cleanup"
    );

    let listed =
        list_files(path_string(repo.path()), empty_filter()).expect("list imported share item");
    assert_eq!(listed, vec![entry.clone()]);
    assert_eq!(metadata_counts(repo.path()), (1, 0, 1));
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let detail = import_change_detail(repo.path(), entry.id);
    assert_import_detail_matches_share_import(&detail, &source_path, &entry);
}

#[test]
fn share_extension_import_validation_rejects_cancel_and_failures_without_side_effects() {
    let repo = initialized_repo();
    let (_cancel_group, cancelled) = share_payload("cancelled.pdf", b"cancelled share payload");

    assert_eq!(
        fs::read(&cancelled).expect("cancelled payload remains platform-owned"),
        b"cancelled share payload"
    );
    assert_no_share_import_side_effects(repo.path());

    let missing_source = repo.path().join("missing-share-item.pdf");
    let missing_result = import_file(
        path_string(repo.path()),
        path_string(&missing_source),
        share_options("Shared Article.pdf", DuplicateStrategy::KeepBoth),
    );
    assert!(matches!(
        missing_result,
        Err(CoreError::FileNotFound { .. })
    ));
    assert_no_share_import_side_effects(repo.path());

    let internal_source = repo.path().join(".areamatrix/staging/share-item.pdf");
    fs::write(&internal_source, b"internal staged bytes").expect("write internal share fixture");
    let internal_result = import_file(
        path_string(repo.path()),
        path_string(&internal_source),
        share_options("Shared Article.pdf", DuplicateStrategy::KeepBoth),
    );
    assert!(matches!(
        internal_result,
        Err(CoreError::InvalidPath { .. })
    ));
    assert_eq!(
        fs::read(&internal_source).expect("internal source remains untouched"),
        b"internal staged bytes"
    );
    assert_eq!(metadata_counts(repo.path()), (0, 0, 0));
    assert!(!repo.path().join("inbox").exists());
    assert_eq!(staging_entries(repo.path()), vec![internal_source]);
}

#[test]
fn share_extension_import_validation_keeps_existing_repo_file_on_duplicate_skip() {
    let repo = initialized_repo();
    let (_first_group, first_source) = share_payload("first.pdf", b"duplicate share bytes");
    let first = import_file(
        path_string(repo.path()),
        path_string(&first_source),
        share_options("Shared Article.pdf", DuplicateStrategy::KeepBoth),
    )
    .expect("import first shared item");
    let first_file = repo.path().join(&first.path);
    let first_bytes = fs::read(&first_file).expect("read first imported share item");

    let (_duplicate_group, duplicate_source) =
        share_payload("second.pdf", b"duplicate share bytes");
    let result = import_file(
        path_string(repo.path()),
        path_string(&duplicate_source),
        share_options("Shared Article.pdf", DuplicateStrategy::Skip),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path }) if existing_path == first.path
        ),
        "duplicate skip should report the existing imported share path"
    );
    assert_eq!(
        fs::read(&duplicate_source).expect("duplicate share payload remains platform-owned"),
        b"duplicate share bytes"
    );
    assert_eq!(
        fs::read(&first_file).expect("existing repo share file remains unchanged"),
        first_bytes
    );
    assert_eq!(metadata_counts(repo.path()), (1, 0, 1));
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn share_extension_import_validation_locks_core_api_udl_rust_and_test_evidence() {
    fn assert_predict(_: fn(String, String) -> CoreResult<ClassifyResult>) {}
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}

    assert_predict(predict_category);
    assert_import(import_file);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    assert_task_and_capability_docs();
    assert_page_control_map_and_testing_docs();
}

fn assert_task_and_capability_docs() {
    for fragment in [
        "# 4-3/task-24: C4-05 validation",
        "为 C4-05 share-extension-import 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-24",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-05 share-extension-import",
        "- S4-IOS-04 share-extension-import",
        "- `import_file`",
        "- `predict_category`",
        "Share Extension 提供的 staged file URL。",
        "导入结果或 deferred import ticket。",
        "导入成功后写 files/change_log。",
        "平台层把 share payload materialize 成 Core 可读文件。",
        "- `PermissionDenied`",
        "- `InvalidPath`",
        "- `Io`",
        "Share Extension 超时不留下成功假状态。",
        "deferred import 可被主 app 继续。",
        "不把外部 app payload 内容写入日志。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
}

fn assert_page_control_map_and_testing_docs() {
    for fragment in [
        "| S4-IOS-04 | share-extension-import | C4-05 | share staged import | Extension 超时/deferred import",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "iOS Share Extension sheet",
        "Save queued",
        "Open AreaMatrix",
        "Cancel 返回来源 App / Share Sheet，不写入 repo。",
        "AreaMatrix will copy these items into the repository after you confirm.",
        "Import may continue in AreaMatrix.",
        "超过合理时间的操作转交主 App，扩展只显示排队结果。",
        "默认写入任务时标记为 `needsConflictReview`",
        "保存后主 App 能继续完成导入。",
        "Main App takeover 协议：queued、needs review、permission expired、completed。",
    ] {
        assert_contains(SHARE_PAGE, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    assert_ffi_surface_alignment();
    assert_core_api_behavior_docs();
    assert_rust_api_docs();
}

fn assert_ffi_surface_alignment() {
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
        "InvalidPath(string path);",
        "PermissionDenied(string path);",
        "Io(string message);",
    ] {
        assert_contains(UDL, fragment);
    }
}

fn assert_core_api_behavior_docs() {
    for fragment in [
        "C4-05 share-extension-import reuses this read-only preview surface",
        "Share Extension has parsed an `NSExtensionItem`",
        "app-group queue persistence",
        "timeout handling stay in the platform layer",
        "C4-05 share-extension-import reuses `StorageMode::Copied` import semantics",
        "Core-readable app",
        "group staged file",
        "store the deferred",
        "import ticket",
        "log external app payload bytes",
        "platform-owned ticket records queued",
        "needs-review, or permission-expired takeover state",
        "calls this same Core import contract",
    ] {
        assert_contains(API_RS, fragment);
    }
}

fn assert_rust_api_docs() {
    for fragment in [
        "pub fn predict_category(repo_path: String, filename: String) -> CoreResult<ClassifyResult>",
        "pub fn import_file(",
        "Returns `CoreError::InvalidPath { path }`",
        "`CoreError::ICloudPlaceholder { path }`",
        "`CoreError::PermissionDenied { path }`",
        "`CoreError::Io { message }`",
        "`CoreError::Db { message }`",
    ] {
        assert_contains(API_RS, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "share_extension_import_contract_exports_existing_import_and_preview_signatures",
        "share_extension_import_docs_core_api_and_udl_stay_aligned",
        "share_extension_import_documents_consumer_state_and_platform_boundaries",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "share_extension_import_implementation_copies_staged_payload_into_repo",
        "share_extension_import_implementation_deferred_ticket_can_be_continued_by_main_app",
        "share_extension_import_implementation_change_log_omits_payload_content",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "share_extension_import_failure_recovery_empty_deferred_state_has_no_core_side_effects",
        "share_extension_import_failure_recovery_invalid_inputs_are_explicit_and_non_mutating",
        "share_extension_import_failure_recovery_permission_denied_maps_and_keeps_payload",
        "share_extension_import_failure_recovery_io_error_from_staging_root_has_no_half_product",
        "share_extension_import_failure_recovery_db_error_rolls_back_and_can_retry",
        "share_extension_import_failure_recovery_error_mapping_is_structured_and_side_effect_free",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
