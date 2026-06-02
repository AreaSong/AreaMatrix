use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_latest_scan_session, init_repo, list_files, load_config, validate_repo_path, CoreError,
    CoreResult, ErrorKind, ErrorRecoverability, FileFilter, FileOrigin, OverviewOutput,
    PlatformPathKind, RepoConfig, RepoInitMode, RepoInitOptions, RepoPathIssue, RepoPathValidation,
    ScanSessionKind, ScanSessionStatus, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-49-c4-10-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-10-linux-repo-connect.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const REPO_PATH_RS: &str = include_str!("../src/repo_path.rs");
const REPO_INIT_RS: &str = include_str!("../src/repo_init.rs");
const CONTRACT_TEST: &str = include_str!("linux_repo_connect_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("linux_repo_connect_implementation.rs");
const FAILURE_TEST: &str = include_str!("linux_repo_connect_failure_recovery.rs");

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
                fs::read(path).expect("read Linux user file snapshot"),
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
fn linux_repo_connect_validation_proves_create_and_adopt_paths_are_ui_ready() {
    let empty_repo = tempfile::tempdir().expect("create empty Linux repo");

    let empty_validation =
        validate_repo_path(path_string(empty_repo.path())).expect("validate empty Linux path");
    assert!(empty_validation.exists);
    assert!(empty_validation.is_directory);
    assert!(empty_validation.is_readable);
    assert!(empty_validation.is_writable);
    assert!(empty_validation.is_empty);
    assert_eq!(empty_validation.platform_path_kind, PlatformPathKind::Local);
    assert!(empty_validation.is_case_sensitive_path);
    assert_eq!(
        empty_validation.recommended_mode,
        Some(RepoInitMode::CreateEmpty)
    );
    assert_eq!(empty_validation.issues, Vec::<RepoPathIssue>::new());

    init_repo(path_string(empty_repo.path()), create_empty_options())
        .expect("initialize Linux repo after confirmation");
    let config = load_config(path_string(empty_repo.path())).expect("load initialized config");
    assert_eq!(config.repo_path, path_string(empty_repo.path()));
    assert_eq!(config.default_mode, StorageMode::Copied);
    assert_eq!(config.overview_output, OverviewOutput::GeneratedOnly);
    assert!(empty_repo.path().join(".areamatrix/index.db").is_file());
    assert!(empty_repo
        .path()
        .join(".areamatrix/generated/root.md")
        .is_file());
    assert!(!empty_repo.path().join("README.md").exists());
    assert!(!empty_repo.path().join("AREAMATRIX.md").exists());

    let adopt_repo = tempfile::tempdir().expect("create non-empty Linux repo");
    prove_linux_adopt_path_preserves_user_files(adopt_repo.path());
}

fn prove_linux_adopt_path_preserves_user_files(repo: &Path) {
    let docs = repo.join("docs");
    let readme = repo.join("README.md");
    let spec = docs.join("spec.txt");
    let user_overview = repo.join("AREAMATRIX.md");
    fs::create_dir(&docs).expect("create Linux user docs directory");
    fs::write(&readme, b"user readme").expect("write user README");
    fs::write(&spec, b"user spec").expect("write user document");
    fs::write(&user_overview, b"user overview").expect("write user AREAMATRIX");
    let before = file_snapshot(&[readme.clone(), spec.clone(), user_overview.clone()]);

    let validation = validate_repo_path(path_string(repo)).expect("validate non-empty Linux path");
    assert!(!validation.is_empty);
    assert_eq!(validation.platform_path_kind, PlatformPathKind::Local);
    assert!(validation.is_case_sensitive_path);
    assert_eq!(
        validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(validation.issues, vec![RepoPathIssue::NonEmptyDirectory]);

    init_repo(path_string(repo), adopt_existing_options()).expect("adopt after confirmation");
    assert_eq!(
        file_snapshot(&[readme.clone(), spec.clone(), user_overview.clone()]),
        before
    );
    assert_adopted_index(repo);

    let session = get_latest_scan_session(path_string(repo))
        .expect("read latest adopt scan")
        .expect("adopt scan exists");
    assert_eq!(session.kind, ScanSessionKind::Adopt);
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert_eq!(session.inserted, 2);
    assert_eq!(session.errors, Vec::<String>::new());
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
fn linux_repo_connect_validation_covers_failures_without_user_file_mutation() {
    let repo = tempfile::tempdir().expect("create Linux failure repo");
    let readme = repo.path().join("README.md");
    fs::write(&readme, b"user readme").expect("write user README");
    let before = file_snapshot(std::slice::from_ref(&readme));

    let create_result = init_repo(path_string(repo.path()), create_empty_options());
    let mut invalid_adopt = adopt_existing_options();
    invalid_adopt.overview_output = OverviewOutput::RootAreaMatrixFile;
    let invalid_adopt_result = init_repo(path_string(repo.path()), invalid_adopt);
    let blank_result = validate_repo_path("   ".to_owned());
    let missing_path = repo.path().join("missing");
    let missing = validate_repo_path(path_string(&missing_path)).expect("validate missing path");
    let network = validate_repo_path("//server/share/AreaMatrix".to_owned())
        .expect("validate network-shaped missing Linux path");

    assert!(matches!(create_result, Err(CoreError::Config { .. })));
    assert!(matches!(
        invalid_adopt_result,
        Err(CoreError::Config { .. })
    ));
    let blank_error = blank_result.expect_err("blank Linux path is invalid");
    let mapping = blank_error.to_error_mapping();
    assert_eq!(mapping.kind, ErrorKind::InvalidPath);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert!(!mapping.user_message.is_empty());
    assert!(!mapping.suggested_action.contains("sudo"));
    assert!(!mapping.suggested_action.contains("chmod"));

    assert!(!missing.exists);
    assert_eq!(missing.platform_path_kind, PlatformPathKind::Local);
    assert!(missing.is_case_sensitive_path);
    assert_eq!(missing.issues, vec![RepoPathIssue::MissingPath]);
    assert!(!missing_path.exists());

    assert!(!network.exists);
    assert_eq!(network.platform_path_kind, PlatformPathKind::NetworkShare);
    assert!(!network.is_case_sensitive_path);
    assert_eq!(
        network.issues,
        vec![
            RepoPathIssue::WindowsCaseInsensitive,
            RepoPathIssue::MissingPath
        ]
    );

    assert_eq!(file_snapshot(std::slice::from_ref(&readme)), before);
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn linux_repo_connect_validation_locks_core_api_udl_rust_and_test_evidence() {
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
    assert_task_and_spec_alignment();
    assert_control_map_and_testing_doc_alignment();
}

fn assert_task_and_spec_alignment() {
    for fragment in [
        "# 4-3/task-49: C4-10 validation",
        "为 C4-10 linux-repo-connect 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-49",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-10 linux-repo-connect",
        "- S4-LNX-01 choose-repo",
        "- S4-LNX-03 local-folder-notice",
        "- S4-X-04 repository-init-confirm",
        "- S4-X-05 repository-adopt-confirm",
        "- `validate_repo_path`",
        "- `init_repo`",
        "Linux path。",
        "path validation、risk、repo state。",
        "只处理授权路径；不执行 sudo/chmod。",
        "本地目录风险提示可结构化展示。",
        "不建议用户执行危险权限命令。",
        "接管不改变用户文件。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
}

fn assert_control_map_and_testing_doc_alignment() {
    for fragment in [
        concat!(
            "| S4-LNX-01 | choose-repo | C4-10 | Linux repo connect | ",
            "不建议 sudo/chmod",
        ),
        concat!(
            "| S4-LNX-03 | local-folder-notice | C4-10, C4-17 | ",
            "local folder risk",
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
    assert_core_api_and_udl_type_alignment();
    assert_core_api_behavior_alignment();
    assert_rust_implementation_alignment();
    assert_linux_connect_forbidden_implementation_absent();
    assert_error_code_alignment();
}

fn assert_core_api_and_udl_type_alignment() {
    for fragment in [
        "RepoPathValidation validate_repo_path(string repo_path);",
        "void init_repo(string repo_path, RepoInitOptions options);",
        "RepoConfig load_config(string repo_path);",
        "dictionary RepoPathValidation",
        "boolean is_readable;",
        "boolean is_writable;",
        "PlatformPathKind platform_path_kind;",
        "boolean is_case_sensitive_path;",
        "RepoInitMode? recommended_mode;",
        "sequence<RepoPathIssue> issues;",
        "enum PlatformPathKind { \"Local\", \"ICloudDrive\", \"OneDrive\", \"NetworkShare\", \"Unknown\" };",
        "\"NotWritable\"",
        "\"NonEmptyDirectory\"",
        "\"AlreadyInitialized\"",
        "InvalidPath(string path);",
        "PermissionDenied(string path);",
        "Io(string message);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

fn assert_core_api_behavior_alignment() {
    for fragment in [
        "AdoptExisting`：目录可以非空；不移动、不重命名、不删除、不覆盖已有内容",
        "永不写入或覆盖已有 `README.md`",
        "不执行 `init_repo`，非空目录只返回 `AdoptExisting` 推荐和结构化风险。",
        "`PermissionDenied`：无法读取目录 metadata、列出目录内容或确认写权限。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_rust_implementation_alignment() {
    for fragment in [
        "pub fn validate_repo_path(repo_path: String) -> CoreResult<RepoPathValidation>",
        "pub fn init_repo(repo_path: String, options: RepoInitOptions) -> CoreResult<()>",
        "Linux shells call this only after local-folder, init, or adopt",
        "adjust POSIX permissions",
        "Core does not run or recommend sudo/chmod",
        "does not configure third-party sync or mount options",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "PlatformPathKind::NetworkShare",
        "metadata_allows_write",
        "RepoPathIssue::NotWritable",
        "RepoPathIssue::NonEmptyDirectory",
        "recommend_mode",
        "CoreError::permission_denied",
    ] {
        assert_contains(REPO_PATH_RS, fragment);
    }

    for fragment in [
        "preflight_adopt_existing",
        "init_adopt_existing_inner",
        "repo_scan::start_adopt_scan",
        "ensure_no_user_content_entries",
        "rollback.rollback()",
    ] {
        assert_contains(REPO_INIT_RS, fragment);
    }
}

fn assert_linux_connect_forbidden_implementation_absent() {
    for forbidden in [
        "Command::new(\"sudo\")",
        "Command::new(\"chmod\")",
        "std::process::Command",
        "sync-provider setup",
        "mount options",
    ] {
        assert!(!REPO_PATH_RS.contains(forbidden));
        assert!(!REPO_INIT_RS.contains(forbidden));
    }
}

fn assert_error_code_alignment() {
    for fragment in [
        "`InvalidPath { path }`",
        "`PermissionDenied { path }`",
        "`Io { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "linux_repo_connect_contract_exports_documented_signatures_and_errors",
        "linux_repo_connect_contract_validates_local_paths_without_mutation",
        "linux_repo_connect_docs_api_udl_and_control_map_stay_aligned",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "linux_repo_connect_initializes_empty_local_directory_after_confirmation",
        "linux_repo_connect_adopts_non_empty_local_directory_without_touching_user_files",
        "linux_repo_connect_keeps_local_folder_risk_state_structured_and_read_only",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "linux_repo_connect_failure_invalid_inputs_map_errors_without_metadata",
        "linux_repo_connect_failure_rejects_unconfirmed_adopt_options_without_user_file_changes",
        "linux_repo_connect_failure_corrupted_metadata_maps_db_without_repair_side_effects",
        "linux_repo_connect_failure_permission_denied_does_not_suggest_permission_mutation",
        "linux_repo_connect_failure_adopt_scan_rolls_back_metadata_without_touching_user_files",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
