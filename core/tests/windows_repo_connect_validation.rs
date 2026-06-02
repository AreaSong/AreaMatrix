use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_files, load_config, validate_repo_path, CoreError, CoreResult, FileFilter,
    FileOrigin, OverviewOutput, PlatformPathKind, RepoConfig, RepoInitMode, RepoInitOptions,
    RepoPathIssue, RepoPathValidation, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-44-c4-09-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-09-windows-repo-connect.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const REPO_PATH_RS: &str = include_str!("../src/repo_path.rs");
const REPO_INIT_RS: &str = include_str!("../src/repo_init.rs");
const CONTRACT_TEST: &str = include_str!("windows_repo_connect_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("windows_repo_connect_implementation.rs");
const FAILURE_TEST: &str = include_str!("windows_repo_connect_failure_recovery.rs");

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

fn adopt_existing_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::AdoptExisting,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
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

fn file_snapshot(paths: &[PathBuf]) -> Vec<(PathBuf, Vec<u8>)> {
    paths
        .iter()
        .map(|path| {
            (
                path.clone(),
                fs::read(path).expect("read user file snapshot"),
            )
        })
        .collect()
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn windows_repo_connect_validation_proves_create_and_adopt_paths_are_ui_ready() {
    let root = tempfile::tempdir().expect("create Windows validation root");
    let empty_repo = root.path().join("C:\\Users\\me\\Documents\\AreaMatrix");
    fs::create_dir_all(&empty_repo).expect("create Windows-shaped empty repo");

    let empty_validation =
        validate_repo_path(path_string(&empty_repo)).expect("validate empty Windows path");
    assert_eq!(
        empty_validation.recommended_mode,
        Some(RepoInitMode::CreateEmpty)
    );
    assert_eq!(
        empty_validation.issues,
        vec![RepoPathIssue::WindowsCaseInsensitive]
    );
    init_repo(path_string(&empty_repo), create_empty_options())
        .expect("initialize after create confirmation");
    let config = load_config(path_string(&empty_repo)).expect("load initialized config");
    assert_eq!(config.repo_path, path_string(&empty_repo));
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert!(empty_repo.join(".areamatrix/index.db").is_file());
    assert!(!empty_repo.join("README.md").exists());

    let adopt_repo = root
        .path()
        .join("C:\\Users\\me\\OneDrive - Org\\AreaMatrix");
    prove_onedrive_adopt_path_preserves_user_files(&adopt_repo);
}

fn prove_onedrive_adopt_path_preserves_user_files(repo: &Path) {
    let docs = repo.join("docs");
    let readme = repo.join("README.md");
    let spec = docs.join("spec.txt");
    fs::create_dir_all(&docs).expect("create user docs directory");
    fs::write(&readme, b"user readme").expect("write README");
    fs::write(&spec, b"user spec").expect("write user document");
    let before = file_snapshot(&[readme.clone(), spec.clone()]);

    let validation = validate_repo_path(path_string(repo)).expect("validate OneDrive path");
    assert_eq!(validation.platform_path_kind, PlatformPathKind::OneDrive);
    assert!(validation.is_onedrive_path);
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

    init_repo(path_string(repo), adopt_existing_options()).expect("adopt after confirmation");
    assert_eq!(file_snapshot(&[readme.clone(), spec.clone()]), before);
    assert_adopted_index(repo);
}

fn assert_adopted_index(repo: &Path) {
    let mut files = list_files(path_string(repo), empty_filter()).expect("list adopted files");
    files.sort_by(|left, right| left.path.cmp(&right.path));
    assert_eq!(
        files
            .iter()
            .map(|file| file.path.as_str())
            .collect::<Vec<_>>(),
        vec!["README.md", "docs/spec.txt"]
    );
    for file in files {
        assert_eq!(file.storage_mode, StorageMode::Indexed);
        assert_eq!(file.origin, FileOrigin::Adopted);
        assert_eq!(file.source_path, None);
    }
}

#[test]
fn windows_repo_connect_validation_covers_failures_without_user_file_mutation() {
    let root = tempfile::tempdir().expect("create Windows failure root");
    let repo = root.path().join("C:\\Users\\me\\OneDrive\\AreaMatrix");
    let readme = repo.join("README.md");
    fs::create_dir_all(&repo).expect("create Windows-shaped repo");
    fs::write(&readme, b"user readme").expect("write README");
    let before = file_snapshot(std::slice::from_ref(&readme));

    let create_result = init_repo(path_string(&repo), create_empty_options());
    let mut invalid_adopt = adopt_existing_options();
    invalid_adopt.overview_output = OverviewOutput::RootAreaMatrixFile;
    let invalid_adopt_result = init_repo(path_string(&repo), invalid_adopt);
    let reserved_result = validate_repo_path("C:\\Users\\me\\NUL.\\AreaMatrix".to_owned());
    let missing = validate_repo_path(path_string(
        &root
            .path()
            .join("C:\\Users\\me\\OneDrive\\MissingAreaMatrix"),
    ))
    .expect("validate missing OneDrive path");

    assert!(matches!(create_result, Err(CoreError::Config { .. })));
    assert!(matches!(
        invalid_adopt_result,
        Err(CoreError::Config { .. })
    ));
    assert!(matches!(
        reserved_result,
        Err(CoreError::InvalidPath { .. })
    ));
    assert!(!missing.exists);
    assert_eq!(missing.platform_path_kind, PlatformPathKind::OneDrive);
    assert_eq!(
        missing.issues,
        vec![
            RepoPathIssue::OneDrivePath,
            RepoPathIssue::WindowsCaseInsensitive,
            RepoPathIssue::MissingPath,
        ]
    );
    assert_eq!(file_snapshot(std::slice::from_ref(&readme)), before);
    assert!(!repo.join(".areamatrix").exists());
}

#[test]
fn windows_repo_connect_validation_locks_core_api_udl_rust_and_test_evidence() {
    fn assert_validate(_: fn(String) -> CoreResult<RepoPathValidation>) {}
    fn assert_init(_: fn(String, RepoInitOptions) -> CoreResult<()>) {}
    fn assert_load_config(_: fn(String) -> CoreResult<RepoConfig>) {}

    assert_validate(validate_repo_path);
    assert_init(init_repo);
    assert_load_config(load_config);

    assert_validation_docs_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_validation_docs_alignment() {
    for fragment in [
        "# 4-3/task-44: C4-09 validation",
        "为 C4-09 windows-repo-connect 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-44",
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
        "使用 Windows 路径规则和权限探测。",
        "Windows 路径分隔符、保留名、大小写规则有测试。",
        "OneDrive 路径能提示风险，不自动控制同步。",
        "接管非空目录仍不改用户文件。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        concat!(
            "| S4-WIN-01 | choose-repo | C4-09, C4-14 | Windows repo connect | ",
            "Windows path / OneDrive risk",
        ),
        concat!(
            "| S4-X-04 | repository-init-confirm | C4-02, C4-09, C4-10 | ",
            "init confirm | 不绕过确认",
        ),
        concat!(
            "| S4-X-05 | repository-adopt-confirm | C4-02, C4-09, C4-10 | ",
            "adopt confirm | 不移动/删除/覆盖用户文件",
        ),
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    for fragment in [
        "RepoPathValidation validate_repo_path(string repo_path);",
        "void init_repo(string repo_path, RepoInitOptions options);",
        "RepoConfig load_config(string repo_path);",
        "dictionary RepoPathValidation",
        "boolean is_onedrive_path;",
        "PlatformPathKind platform_path_kind;",
        "boolean is_case_sensitive_path;",
        "RepoInitMode? recommended_mode;",
        "sequence<RepoPathIssue> issues;",
        "enum PlatformPathKind { \"Local\", \"ICloudDrive\", \"OneDrive\", \"NetworkShare\", \"Unknown\" };",
        "\"OneDrivePath\"",
        "\"WindowsReservedName\"",
        "\"WindowsCaseInsensitive\"",
        "InvalidPath(string path);",
        "PermissionDenied(string path);",
        "Config(string reason);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "不调用 OneDrive SDK，不读取 OneDrive 客户端同步状态，不修改 OneDrive 同步设置。",
        "非空目录只返回 `AdoptExisting` 推荐和结构化风险。",
        "AdoptExisting`：目录可以非空；不移动、不重命名、不删除、不覆盖已有内容",
        "永不写入或覆盖已有 `README.md`",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "pub fn validate_repo_path(repo_path: String) -> CoreResult<RepoPathValidation>",
        "pub fn init_repo(repo_path: String, options: RepoInitOptions) -> CoreResult<()>",
        "pub fn load_config(repo_path: String) -> CoreResult<RepoConfig>",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "has_windows_drive_prefix",
        "split_windows_separators",
        "is_windows_reserved_name",
        "PlatformPathKind::OneDrive",
        "WindowsCaseInsensitive",
        "CoreError::invalid_path",
    ] {
        assert_contains(REPO_PATH_RS, fragment);
    }

    for fragment in [
        "preflight_adopt_existing",
        "init_adopt_existing_inner",
        "repo_scan::start_adopt_scan",
        "ensure_no_user_content_entries",
    ] {
        assert_contains(REPO_INIT_RS, fragment);
    }

    for forbidden in [
        "OneDrive SDK",
        "change OneDrive settings",
        "Windows shell extension",
    ] {
        assert!(!REPO_PATH_RS.contains(forbidden));
        assert!(!REPO_INIT_RS.contains(forbidden));
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "windows_repo_connect_contract_exports_existing_repo_signatures_and_errors",
        "windows_repo_connect_contract_detects_windows_shape_without_mutation",
        "windows_repo_connect_docs_api_udl_and_control_map_stay_aligned",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "windows_repo_connect_initializes_windows_shaped_empty_path_after_confirmation",
        "windows_repo_connect_adopts_onedrive_non_empty_path_without_touching_user_files",
        "windows_repo_connect_classifies_unc_and_mixed_separators_without_sdk_side_effects",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "windows_repo_connect_failure_invalid_inputs_map_errors_without_metadata",
        "windows_repo_connect_failure_onedrive_missing_path_is_read_only_risk_state",
        "windows_repo_connect_failure_rejects_unconfirmed_adopt_options_without_user_file_changes",
        "windows_repo_connect_failure_corrupted_metadata_maps_db_without_repair_side_effects",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
