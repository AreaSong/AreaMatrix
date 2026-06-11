use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, list_files, load_config, validate_repo_path, CoreError, CoreResult, FileFilter,
    FileOrigin, OverviewOutput, RepoConfig, RepoInitMode, RepoInitOptions, RepoPathIssue,
    RepoPathValidation, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-09-c4-02-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-02-mobile-repo-connect.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CONTRACT_TEST: &str = include_str!("mobile_repo_connect_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("mobile_repo_connect_implementation.rs");
const FAILURE_TEST: &str = include_str!("mobile_repo_connect_failure_recovery.rs");

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

fn read_file(path: &Path) -> Vec<u8> {
    fs::read(path).expect("read user file")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn mobile_repo_connect_validation_proves_ui_ready_create_and_adopt_paths() {
    let empty_repo = tempfile::tempdir().expect("create empty mobile repository directory");
    let empty_validation =
        validate_repo_path(path_string(empty_repo.path())).expect("validate empty repo path");
    assert_eq!(
        empty_validation.recommended_mode,
        Some(RepoInitMode::CreateEmpty)
    );
    assert_eq!(empty_validation.issues, Vec::<RepoPathIssue>::new());
    assert!(!empty_repo.path().join(".areamatrix").exists());

    init_repo(path_string(empty_repo.path()), create_empty_options())
        .expect("initialize after create confirmation");
    let empty_config = load_config(path_string(empty_repo.path())).expect("load created config");
    assert_eq!(empty_config.repo_path, path_string(empty_repo.path()));
    assert_eq!(empty_config.overview_output, OverviewOutput::GeneratedOnly);
    assert!(empty_repo.path().join(".areamatrix/index.db").is_file());
    assert!(empty_repo
        .path()
        .join(".areamatrix/generated/root.md")
        .is_file());
    assert!(!empty_repo.path().join("README.md").exists());
    assert!(!empty_repo.path().join("AREAMATRIX.md").exists());

    let adopt_repo = tempfile::tempdir().expect("create non-empty mobile repository directory");
    fs::create_dir(adopt_repo.path().join("docs")).expect("create user docs directory");
    fs::write(adopt_repo.path().join("README.md"), b"user readme").expect("write README");
    fs::write(adopt_repo.path().join("docs/spec.txt"), b"user spec").expect("write user file");
    let readme_before = read_file(&adopt_repo.path().join("README.md"));
    let spec_before = read_file(&adopt_repo.path().join("docs/spec.txt"));

    let adopt_validation =
        validate_repo_path(path_string(adopt_repo.path())).expect("validate adopt path");
    assert_eq!(
        adopt_validation.recommended_mode,
        Some(RepoInitMode::AdoptExisting)
    );
    assert_eq!(
        adopt_validation.issues,
        vec![RepoPathIssue::NonEmptyDirectory]
    );
    init_repo(path_string(adopt_repo.path()), adopt_existing_options())
        .expect("adopt after explicit confirmation");

    assert_eq!(
        read_file(&adopt_repo.path().join("README.md")),
        readme_before
    );
    assert_eq!(
        read_file(&adopt_repo.path().join("docs/spec.txt")),
        spec_before
    );
    let mut files =
        list_files(path_string(adopt_repo.path()), empty_filter()).expect("list adopted files");
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
    }
}

#[test]
fn mobile_repo_connect_validation_rejects_failures_without_user_file_side_effects() {
    let repo = tempfile::tempdir().expect("create non-empty mobile repository directory");
    let readme = repo.path().join("README.md");
    let notes = repo.path().join("notes.txt");
    fs::write(&readme, b"user readme").expect("write README");
    fs::write(&notes, b"user notes").expect("write notes");
    let before = vec![read_file(&readme), read_file(&notes)];

    let create_result = init_repo(path_string(repo.path()), create_empty_options());
    let mut invalid_adopt = adopt_existing_options();
    invalid_adopt.overview_output = OverviewOutput::RootAreaMatrixFile;
    let invalid_adopt_result = init_repo(path_string(repo.path()), invalid_adopt);
    let placeholder_result = validate_repo_path(path_string(&repo.path().join("file.pdf.icloud")));

    assert!(matches!(create_result, Err(CoreError::Config { .. })));
    assert!(matches!(
        invalid_adopt_result,
        Err(CoreError::Config { .. })
    ));
    assert!(matches!(
        placeholder_result,
        Err(CoreError::ICloudPlaceholder { .. })
    ));
    assert_eq!(vec![read_file(&readme), read_file(&notes)], before);
    assert!(!repo.path().join(".areamatrix").exists());
    assert!(!repo.path().join("AREAMATRIX.md").exists());
}

#[test]
fn mobile_repo_connect_validation_locks_core_api_udl_rust_and_test_evidence() {
    fn assert_validate(_: fn(String) -> CoreResult<RepoPathValidation>) {}
    fn assert_init(_: fn(String, RepoInitOptions) -> CoreResult<()>) {}
    fn assert_load_config(_: fn(String) -> CoreResult<RepoConfig>) {}

    assert_validate(validate_repo_path);
    assert_init(init_repo);
    assert_load_config(load_config);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-09: C4-02 validation",
        "为 C4-02 mobile-repo-connect 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-09",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-02 mobile-repo-connect",
        "- S4-IOS-01 connect-repo",
        "- S4-X-04 repository-init-confirm",
        "- S4-X-05 repository-adopt-confirm",
        "- `validate_repo_path`",
        "- `init_repo`",
        "- `load_config`",
        "由平台层申请权限；Core 只处理授权后的路径。",
        "空目录初始化和非空目录接管仍走确认页。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-01 | connect-repo | C4-02, C4-08 | repo validate/init/adopt | iOS security-scoped URL",
        "| S4-X-04 | repository-init-confirm | C4-02, C4-09, C4-10 | init confirm | 不绕过确认",
        "| S4-X-05 | repository-adopt-confirm | C4-02, C4-09, C4-10 | adopt confirm | 不移动/删除/覆盖用户文件",
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
        "RepoInitMode? recommended_mode;",
        "sequence<RepoPathIssue> issues;",
        "dictionary RepoInitOptions",
        "RepoInitMode mode;",
        "OverviewOutput overview_output;",
        "dictionary RepoConfig",
        "StorageMode default_mode;",
        "enum RepoInitMode { \"CreateEmpty\", \"AdoptExisting\" };",
        "InvalidPath(string path);",
        "ICloudPlaceholder(string path);",
        "PermissionDenied(string path);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `validate_repo_path(repoPath: String) throws -> RepoPathValidation`",
        "### `init_repo(repoPath: String, options: RepoInitOptions) throws`",
        "### `load_config(repoPath: String) throws -> RepoConfig`",
        "不触发 iCloud 占位符下载。",
        "非空目录只返回 `AdoptExisting` 推荐和结构化风险。",
        "永不写入或覆盖已有 `README.md`",
        "`.areamatrix/index.db` 不存在时返回默认值",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "C4-02 mobile repository connection contract reuses the same surface",
        "Core receives only the authorized filesystem path",
        "mobile shells call this only after the shared init/adopt",
        "does not refresh platform permissions or create metadata",
    ] {
        assert_contains(API_RS, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "mobile_repo_connect_contract_exports_documented_signatures_and_errors",
        "mobile_repo_connect_docs_core_api_and_udl_stay_aligned",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "mobile_repo_connect_empty_directory_initializes_only_after_explicit_confirmed_call",
        "mobile_repo_connect_non_empty_directory_adopts_without_modifying_user_files",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "mobile_repo_connect_failure_invalid_inputs_do_not_create_metadata",
        "mobile_repo_connect_failure_rejects_unconfirmed_modes_without_touching_user_files",
        "mobile_repo_connect_failure_keeps_ai_and_remote_calls_disabled_by_default",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
