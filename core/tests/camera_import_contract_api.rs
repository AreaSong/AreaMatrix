use area_matrix_core::{
    import_file, predict_category, ClassifyResult, CoreError, CoreResult, DuplicateStrategy,
    FileAvailabilityStatus, FileEntry, FileOrigin, ImportDestination, ImportOptions, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-16-c4-04-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-04-camera-import.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const CAMERA_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-03-camera-import.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn camera_import_contract_exports_existing_import_and_preview_signatures() {
    fn assert_predict(_: fn(String, String) -> CoreResult<ClassifyResult>) {}
    fn assert_import(_: fn(String, String, ImportOptions) -> CoreResult<FileEntry>) {}

    assert_predict(predict_category);
    assert_import(import_file);
}

#[test]
fn camera_import_contract_exposes_mobile_copy_inputs_outputs_and_errors() {
    let camera_options = ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("docs".to_owned()),
        override_filename: Some("Photo 2026-04-29 1130.jpg".to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    };
    assert_eq!(camera_options.mode, StorageMode::Copied);
    assert_eq!(camera_options.destination, ImportDestination::AutoClassify);
    assert_eq!(
        camera_options.override_filename.as_deref(),
        Some("Photo 2026-04-29 1130.jpg")
    );
    assert_eq!(camera_options.duplicate_strategy, DuplicateStrategy::Skip);

    let imported_photo = FileEntry {
        id: 404,
        path: "docs/Photo 2026-04-29 1130.jpg".to_owned(),
        original_name: "Photo 2026-04-29 1130.jpg".to_owned(),
        current_name: "Photo 2026-04-29 1130.jpg".to_owned(),
        category: "docs".to_owned(),
        size_bytes: 2_048,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some("/tmp/areamatrix-camera/photo.jpg".to_owned()),
        availability_status: FileAvailabilityStatus::Available,
        imported_at: 1_777_300_000,
        updated_at: 1_777_300_000,
    };
    assert_eq!(imported_photo.storage_mode, StorageMode::Copied);
    assert_eq!(imported_photo.origin, FileOrigin::Imported);
    assert_eq!(
        imported_photo.source_path.as_deref(),
        Some("/tmp/areamatrix-camera/photo.jpg")
    );
    assert_eq!(imported_photo.availability_status, FileAvailabilityStatus::Available);

    let documented_errors = [
        CoreError::permission_denied("camera temp file is unreadable"),
        CoreError::invalid_path("camera temp path is invalid"),
        CoreError::io("camera import filesystem failure"),
        CoreError::db("camera import metadata failure"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn camera_import_docs_core_api_and_udl_stay_aligned() {
    for fragment in [
        "# 4-3/task-16: C4-04 contract-api",
        "为 C4-04 camera-import 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-04 camera-import",
        "- S4-IOS-03 camera-import",
        "- `import_file`",
        "- `predict_category`",
        "平台层保存后的照片临时文件路径和 ImportOptions。",
        "FileEntry、导入结果。",
        "Core 从平台临时路径导入到 repo。",
        "平台层负责相机权限和临时文件生命周期。",
        "- `PermissionDenied`",
        "- `InvalidPath`",
        "- `Io`",
        "- `Db`",
        "拍照取消不写 DB。",
        "导入失败不删除用户已有文件。",
        "临时文件清理不由 Core 删除最终 repo 文件。",
        "OCR 和拍照自动摘要属于 Stage 3+/后续。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-03 | camera-import | C4-04 | camera staged import | 平台层处理相机/临时文件",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "ClassifyResult predict_category(string repo_path, string filename);",
        "FileEntry import_file(",
        "string repo_path, string source_path, ImportOptions options",
        "dictionary ImportOptions",
        "StorageMode mode;",
        "ImportDestination destination;",
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
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "`PermissionDenied { path }`",
        "`InvalidPath { path }`",
        "`Io { message }`",
        "`Db { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn camera_import_documents_consumer_state_and_platform_boundaries() {
    for fragment in [
        "接收系统相机返回的单张照片临时文件。",
        "显示导入模式：复制到资料库，移动端不提供“原地索引”作为默认选项。",
        "处理同名冲突，默认保留两份并自动编号。",
        "权限拒绝：不进入本 sheet",
        "拍摄取消：不进入本 sheet",
        "临时照片不可读：显示错误页状态 `Could not read captured photo.`",
        "点击 `Cancel` 不写入 repo，不创建 change log。",
        "Core transactional import API。",
        "导入成功后移动端资料库能立刻看到新照片。",
    ] {
        assert_contains(CAMERA_PAGE, fragment);
    }

    for fragment in [
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
