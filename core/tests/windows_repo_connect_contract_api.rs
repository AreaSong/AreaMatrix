use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_config, validate_repo_path, CoreError, CoreResult, PlatformPathKind,
    RepoConfig, RepoInitMode, RepoInitOptions, RepoPathIssue, RepoPathValidation,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-41-c4-09-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-09-windows-repo-connect.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const WIN_CHOOSE_REPO_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-01-choose-repo.md");
const INIT_CONFIRM_PAGE: &str = include_str!(
    "../../docs/ux/page-specs/stage-4-multiplatform/S4-X-04-repository-init-confirm.md"
);
const ADOPT_CONFIRM_PAGE: &str = include_str!(
    "../../docs/ux/page-specs/stage-4-multiplatform/S4-X-05-repository-adopt-confirm.md"
);
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const REPO_PATH_RS: &str = include_str!("../src/repo_path.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn windows_repo_connect_contract_exports_existing_repo_signatures_and_errors() {
    fn assert_validate(_: fn(String) -> CoreResult<RepoPathValidation>) {}
    fn assert_init(_: fn(String, RepoInitOptions) -> CoreResult<()>) {}
    fn assert_load_config(_: fn(String) -> CoreResult<RepoConfig>) {}

    assert_validate(validate_repo_path);
    assert_init(init_repo);
    assert_load_config(load_config);

    let documented_errors = [
        CoreError::invalid_path("invalid path"),
        CoreError::permission_denied("permission denied"),
        CoreError::config("configuration error"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn windows_repo_connect_contract_exposes_page_ready_path_state() {
    let validation = RepoPathValidation {
        repo_path: "C:\\Users\\me\\OneDrive\\AreaMatrix".to_owned(),
        exists: true,
        is_directory: true,
        is_readable: true,
        is_writable: true,
        is_empty: false,
        is_initialized: false,
        is_inside_area_matrix: false,
        is_icloud_path: false,
        is_onedrive_path: true,
        platform_path_kind: PlatformPathKind::OneDrive,
        is_case_sensitive_path: false,
        has_unfinished_scan_session: false,
        recommended_mode: Some(RepoInitMode::AdoptExisting),
        issues: vec![
            RepoPathIssue::OneDrivePath,
            RepoPathIssue::WindowsCaseInsensitive,
            RepoPathIssue::NonEmptyDirectory,
        ],
    };

    assert_eq!(validation.platform_path_kind, PlatformPathKind::OneDrive);
    assert!(validation.is_onedrive_path);
    assert!(!validation.is_case_sensitive_path);
    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert!(validation.issues.contains(&RepoPathIssue::OneDrivePath));
    assert!(validation
        .issues
        .contains(&RepoPathIssue::WindowsCaseInsensitive));
}

#[test]
fn windows_repo_connect_contract_detects_windows_shape_without_mutation() {
    let root = tempfile::tempdir().expect("create Windows-shaped root");
    let repo = root.path().join("C:\\Users\\me\\OneDrive\\AreaMatrix");
    fs::create_dir_all(&repo).expect("create Windows-shaped repository path");
    fs::write(repo.join("README.md"), "owned by user\n").expect("write user file");

    let validation = validate_repo_path(path_string(&repo)).expect("validate Windows path");

    assert!(validation.exists);
    assert!(validation.is_directory);
    assert!(validation.is_onedrive_path);
    assert_eq!(validation.platform_path_kind, PlatformPathKind::OneDrive);
    assert!(!validation.is_case_sensitive_path);
    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(
        validation.issues,
        vec![
            RepoPathIssue::OneDrivePath,
            RepoPathIssue::WindowsCaseInsensitive,
            RepoPathIssue::NonEmptyDirectory,
        ]
    );
    assert!(!repo.join(".areamatrix").exists());
    assert_eq!(
        fs::read_to_string(repo.join("README.md")).expect("read preserved user file"),
        "owned by user\n"
    );
}

#[test]
fn windows_repo_connect_contract_rejects_reserved_names() {
    let result = validate_repo_path("C:\\Users\\me\\CON\\AreaMatrix".to_owned());

    assert!(matches!(result, Err(CoreError::InvalidPath { .. })));
}

#[test]
fn windows_repo_connect_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-41: C4-09 contract-api",
        "为 C4-09 windows-repo-connect 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-09 windows-repo-connect",
        "- S4-WIN-01 choose-repo",
        "- S4-X-04 repository-init-confirm",
        "- S4-X-05 repository-adopt-confirm",
        "- `validate_repo_path`",
        "- `init_repo`",
        "- `load_config`",
        "Windows path。",
        "repo path validation 和 init/adopt result。",
        "使用 Windows 路径规则和权限探测。",
        "- `InvalidPath`",
        "- `PermissionDenied`",
        "- `Config`",
        "Windows 路径分隔符、保留名、大小写规则有测试。",
        "OneDrive 路径能提示风险，不自动控制同步。",
        "接管非空目录仍不改用户文件。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-WIN-01 | choose-repo | C4-09, C4-14 | Windows repo connect | Windows path / OneDrive risk",
        "| S4-X-04 | repository-init-confirm | C4-02, C4-09, C4-10 | init confirm | 不绕过确认",
        "| S4-X-05 | repository-adopt-confirm | C4-02, C4-09, C4-10 | adopt confirm | 不移动/删除/覆盖用户文件",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "RepoPathValidation validate_repo_path(string repo_path);",
        "void init_repo(string repo_path, RepoInitOptions options);",
        "RepoConfig load_config(string repo_path);",
        "dictionary RepoPathValidation",
        "boolean is_onedrive_path;",
        "PlatformPathKind platform_path_kind;",
        "boolean is_case_sensitive_path;",
        "sequence<RepoPathIssue> issues;",
        "enum PlatformPathKind { \"Local\", \"ICloudDrive\", \"OneDrive\", \"NetworkShare\", \"Unknown\" };",
        "\"OneDrivePath\"",
        "\"WindowsReservedName\"",
        "\"WindowsCaseInsensitive\"",
        "InvalidPath(string path);",
        "PermissionDenied(string path);",
        "Config(string reason);",
    ] {
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "dictionary RepoPathValidation",
        "boolean is_onedrive_path;",
        "PlatformPathKind platform_path_kind;",
        "boolean is_case_sensitive_path;",
        "enum PlatformPathKind { \"Local\", \"ICloudDrive\", \"OneDrive\", \"NetworkShare\", \"Unknown\" };",
        "\"OneDrivePath\"",
        "\"WindowsReservedName\"",
        "\"WindowsCaseInsensitive\"",
        "`isOnedrivePath`",
        "`platformPathKind`",
        "`isCaseSensitivePath`",
        "不调用 OneDrive SDK，不读取 OneDrive 客户端同步状态，不修改 OneDrive 同步设置。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "is_onedrive_path",
        "platform_path_kind",
        "is_case_sensitive_path",
        "OneDrivePath",
        "WindowsReservedName",
        "WindowsCaseInsensitive",
        "PlatformPathKind",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }

    for fragment in [
        "has_windows_drive_prefix",
        "is_windows_reserved_name",
        "PlatformPathKind::OneDrive",
        "WindowsCaseInsensitive",
        "CoreError::invalid_path",
    ] {
        assert_contains(REPO_PATH_RS, fragment);
    }
}

#[test]
fn windows_repo_connect_documents_consumer_state_without_adjacent_capabilities() {
    for fragment in [
        "Windows 用户需要选择一个 AreaMatrix 资料库目录，可能位于本地磁盘、外接盘或 OneDrive。",
        "识别非空普通目录并要求后续确认。",
        "检测路径是否可读、可写、是否在 OneDrive、是否网络盘或外接盘。",
        "OneDrive 路径：必须进入 `onedrive-notice` 确认，不直接进入主窗口。",
        "非空目录：不得直接创建 `.areamatrix/`。",
        "OneDrive 路径检测，包含用户目录下 `OneDrive` 和组织 OneDrive 命名。",
    ] {
        assert_contains(WIN_CHOOSE_REPO_PAGE, fragment);
    }

    for fragment in [
        "Type: iCloud Drive / OneDrive / Local folder / Network mount / Unknown",
        "Folder is empty",
        "Write permission available",
        "云盘或挂载类型检测。",
    ] {
        assert_contains(INIT_CONFIRM_PAGE, fragment);
    }

    for fragment in [
        "Location type: iCloud Drive / OneDrive / Local folder / Network mount / Unknown",
        "不移动、不删除、不重命名、不覆盖已有用户文件",
        "只会创建 `.areamatrix/` 并建立索引。",
        "删除 `.areamatrix/` 不得导致用户文件丢失",
    ] {
        assert_contains(ADOPT_CONFIRM_PAGE, fragment);
    }

    for fragment in [
        "Returns `CoreError::InvalidPath { path }`",
        "`CoreError::PermissionDenied { path }`",
        "`CoreError::Config { reason }`",
        "must never create,",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "`InvalidPath { path }`",
        "`PermissionDenied { path }`",
        "`Config { reason }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for forbidden in [
        "Windows shell extension",
        "OneDrive SDK",
        "change OneDrive settings",
    ] {
        assert!(
            !REPO_PATH_RS.contains(forbidden),
            "C4-09 repo path contract must not implement adjacent capability `{forbidden}`"
        );
    }

    assert_contains(
        CORE_API,
        "### `validate_repo_path(repoPath: String) throws -> RepoPathValidation`",
    );
}
