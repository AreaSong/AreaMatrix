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
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-19-c4-04-validation.md"
);
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-4-multiplatform/C4-04-camera-import.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const CAMERA_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-03-camera-import.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CONTRACT_TEST: &str = include_str!("camera_import_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("camera_import_implementation.rs");
const FAILURE_TEST: &str = include_str!("camera_import_failure_recovery.rs");

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
        .expect("initialize repository for camera import validation");
    repo
}

fn captured_photo(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let camera_temp = tempfile::tempdir().expect("create platform camera temp directory");
    let source_path = camera_temp.path().join(name);
    fs::write(&source_path, content).expect("write captured photo fixture");
    (camera_temp, source_path)
}

fn camera_options(filename: &str, duplicate_strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("photos".to_owned()),
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

fn assert_no_camera_import_side_effects(repo: &Path) {
    assert_eq!(metadata_counts(repo), (0, 0, 0));
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
    assert!(!repo.join("photos").exists());
}

fn import_change_detail(repo: &Path, file_id: i64) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log WHERE file_id = ?1 AND action = 'imported'",
            [file_id],
            |row| row.get(0),
        )
        .expect("read camera import change detail");
    serde_json::from_str(&detail_json).expect("parse camera import detail JSON")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_imported_camera_entry(entry: &FileEntry, source_path: &str) {
    assert_eq!(entry.path, "photos/Photo 2026-04-29 1130.jpg");
    assert_eq!(entry.original_name, "capture.jpg");
    assert_eq!(entry.current_name, "Photo 2026-04-29 1130.jpg");
    assert_eq!(entry.category, "photos");
    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(entry.source_path.as_deref(), Some(source_path));
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Available);
}

fn assert_import_detail_matches_camera_import(
    detail: &Value,
    source_path: &str,
    entry: &FileEntry,
) {
    assert_eq!(detail["source"], source_path);
    assert_eq!(detail["mode"], "copied");
    assert_eq!(detail["category"], "photos");
    assert_eq!(detail["destination"], "auto_classify");
    assert_eq!(detail["requested_name"], "Photo 2026-04-29 1130.jpg");
    assert_eq!(detail["final_path"], entry.path);
    assert_eq!(detail["name_conflict_resolved"], false);
}

#[test]
fn camera_import_validation_proves_ui_ready_success_path() {
    let repo = initialized_repo();
    let (_camera_temp, source) = captured_photo("capture.jpg", b"camera validation bytes");
    let source_before = fs::read(&source).expect("read captured photo before import");
    let source_path = path_string(&source);

    let prediction = predict_category(path_string(repo.path()), "capture.jpg".to_owned())
        .expect("preview camera photo category");
    assert_eq!(prediction.category, "media");

    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        camera_options("Photo 2026-04-29 1130.jpg", DuplicateStrategy::KeepBoth),
    )
    .expect("import captured camera photo");

    assert_eq!(
        fs::read(&source).expect("read platform temp photo"),
        source_before
    );
    assert_imported_camera_entry(&entry, &source_path);
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read copied repo photo"),
        source_before
    );

    fs::remove_file(&source).expect("platform can clean camera temp photo after import");
    assert!(
        repo.path().join(&entry.path).is_file(),
        "Core must not tie final repo file lifetime to platform temp cleanup"
    );

    let listed =
        list_files(path_string(repo.path()), empty_filter()).expect("list imported mobile photo");
    assert_eq!(listed, vec![entry.clone()]);
    assert_eq!(metadata_counts(repo.path()), (1, 0, 1));
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());

    let detail = import_change_detail(repo.path(), entry.id);
    assert_import_detail_matches_camera_import(&detail, &source_path, &entry);
}

#[test]
fn camera_import_validation_rejects_cancel_and_failures_without_side_effects() {
    let repo = initialized_repo();
    let (_cancel_temp, cancelled) = captured_photo("cancelled.jpg", b"cancelled bytes");

    assert_eq!(
        fs::read(&cancelled).expect("platform temp photo remains platform-owned"),
        b"cancelled bytes"
    );
    assert_no_camera_import_side_effects(repo.path());

    let missing_source = repo.path().join("missing-camera-photo.jpg");
    let missing_result = import_file(
        path_string(repo.path()),
        path_string(&missing_source),
        camera_options("Photo 2026-04-29 1130.jpg", DuplicateStrategy::KeepBoth),
    );
    assert!(matches!(
        missing_result,
        Err(CoreError::FileNotFound { .. })
    ));
    assert_no_camera_import_side_effects(repo.path());

    let internal_source = repo.path().join(".areamatrix/staging/camera-temp.jpg");
    fs::write(&internal_source, b"internal staging bytes").expect("write internal camera fixture");
    let internal_result = import_file(
        path_string(repo.path()),
        path_string(&internal_source),
        camera_options("Photo 2026-04-29 1130.jpg", DuplicateStrategy::KeepBoth),
    );
    assert!(matches!(
        internal_result,
        Err(CoreError::InvalidPath { .. })
    ));
    assert_eq!(
        fs::read(&internal_source).expect("internal source remains untouched"),
        b"internal staging bytes"
    );
    assert_eq!(metadata_counts(repo.path()), (0, 0, 0));
    assert!(!repo.path().join("photos").exists());
    assert_eq!(staging_entries(repo.path()), vec![internal_source]);
}

#[test]
fn camera_import_validation_keeps_existing_repo_files_on_duplicate_skip() {
    let repo = initialized_repo();
    let (_first_temp, first_source) = captured_photo("first.jpg", b"duplicate camera bytes");
    let first = import_file(
        path_string(repo.path()),
        path_string(&first_source),
        camera_options("Photo 2026-04-29 1130.jpg", DuplicateStrategy::KeepBoth),
    )
    .expect("import first camera photo");
    let first_file = repo.path().join(&first.path);
    let first_bytes = fs::read(&first_file).expect("read first imported photo");

    let (_duplicate_temp, duplicate_source) =
        captured_photo("second.jpg", b"duplicate camera bytes");
    let result = import_file(
        path_string(repo.path()),
        path_string(&duplicate_source),
        camera_options("Photo 2026-04-29 1130.jpg", DuplicateStrategy::Skip),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path }) if existing_path == first.path
        ),
        "duplicate skip should report the existing imported camera path"
    );
    assert_eq!(
        fs::read(&duplicate_source).expect("duplicate camera temp remains platform-owned"),
        b"duplicate camera bytes"
    );
    assert_eq!(
        fs::read(&first_file).expect("existing repo photo remains unchanged"),
        first_bytes
    );
    assert_eq!(metadata_counts(repo.path()), (1, 0, 1));
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn camera_import_validation_locks_core_api_udl_rust_and_test_evidence() {
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
        "# 4-3/task-19: C4-04 validation",
        "为 C4-04 camera-import 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-19",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-04 camera-import",
        "- S4-IOS-03 camera-import",
        "- `import_file`",
        "- `predict_category`",
        "平台层保存后的照片临时文件路径和 ImportOptions。",
        "Core 从平台临时路径导入到 repo。",
        "平台层负责相机权限和临时文件生命周期。",
        "- `PermissionDenied`",
        "- `InvalidPath`",
        "- `Io`",
        "- `Db`",
        "拍照取消不写 DB。",
        "导入失败不删除用户已有文件。",
        "临时文件清理不由 Core 删除最终 repo 文件。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
}

fn assert_page_control_map_and_testing_docs() {
    for fragment in [
        "| S4-IOS-03 | camera-import | C4-04 | camera staged import | 平台层处理相机/临时文件",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "Core transactional import API。",
        "点击 `Cancel` 不写入 repo，不创建 change log。",
        "默认保存方式是复制进 repo，不删除相机临时结果直到导入完成或用户取消。",
        "导入成功后移动端资料库能立刻看到新照片。",
    ] {
        assert_contains(CAMERA_PAGE, fragment);
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
        "Db(string message);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

fn assert_core_api_behavior_docs() {
    for fragment in [
        "### `predict_category(repoPath: String, filename: String) throws -> ClassifyResult`",
        "### `import_file(repoPath, sourcePath, options) throws -> FileEntry`",
        "无写入副作用：只读取 `.areamatrix/classifier.yaml`",
        "可能抛：`Io` / `Db` / `DuplicateFile` / `Conflict` / `InvalidPath` / `ICloudPlaceholder` / `Internal`。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_rust_api_docs() {
    for fragment in [
        "pub fn predict_category(repo_path: String, filename: String) -> CoreResult<ClassifyResult>",
        "pub fn import_file(",
        "C4-04 camera-import reuses this read-only preview surface",
        "temporary-file lifetime management remain outside Core",
        "C4-04 camera-import reuses `StorageMode::Copied` import semantics",
        "platform-saved temporary photo path",
        "does not request camera",
        "or clean up the final repository file",
        "without adding a camera-specific Core API",
    ] {
        assert_contains(API_RS, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "camera_import_contract_exports_existing_import_and_preview_signatures",
        "camera_import_docs_core_api_and_udl_stay_aligned",
        "camera_import_documents_consumer_state_and_platform_boundaries",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "camera_import_implementation_copies_platform_temp_photo_into_repo",
        "camera_import_implementation_cancel_without_core_call_writes_no_metadata",
        "camera_import_implementation_db_failure_keeps_temp_and_existing_repo_files",
        "camera_import_implementation_invalid_temp_path_writes_no_db_or_files",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "camera_import_failure_recovery_capture_cancel_empty_state_has_no_core_side_effects",
        "camera_import_failure_recovery_invalid_inputs_are_explicit_and_non_mutating",
        "camera_import_failure_recovery_permission_denied_maps_and_leaves_no_half_products",
        "camera_import_failure_recovery_io_error_from_staging_root_keeps_temp_file",
        "camera_import_failure_recovery_db_error_rolls_back_final_file_and_can_retry",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
