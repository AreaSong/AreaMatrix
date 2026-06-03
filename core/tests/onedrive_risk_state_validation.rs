use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    acknowledge_onedrive_risk_notice, detect_cloud_storage_state, init_repo, CloudPermissionState,
    CloudPlaceholderState, CloudStorageProviderKind, CloudStorageRecommendedAction,
    CloudStorageRiskLevel, CloudStorageState, CoreError, CoreResult, ErrorKind, OverviewOutput,
    RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{Connection, OptionalExtension};

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-69-c4-14-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-14-onedrive-risk-state.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const ONEDRIVE_NOTICE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-03-onedrive-notice.md");
const WIN_CHOOSE_REPO_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-01-choose-repo.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CLOUD_PERMISSION_RS: &str = include_str!("../src/cloud_permission_state.rs");
const CONTRACT_TEST: &str = include_str!("onedrive_risk_state_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("onedrive_risk_state_implementation.rs");
const FAILURE_TEST: &str = include_str!("onedrive_risk_state_failure_recovery.rs");

const ACK_KEY: &str = "onedrive_risk_notice_acknowledged";

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_onedrive_repo(root: &Path) -> PathBuf {
    let repo = root
        .join("Users")
        .join("me")
        .join("OneDrive - Example Org")
        .join("AreaMatrix");
    fs::create_dir_all(&repo).expect("create OneDrive-shaped repository path");
    repo
}

fn init_empty_repo(repo: &Path) {
    init_repo(
        path_string(repo),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository metadata");
}

fn file_snapshot(paths: &[PathBuf]) -> Vec<(PathBuf, Vec<u8>)> {
    paths
        .iter()
        .map(|path| (path.clone(), fs::read(path).expect("read file snapshot")))
        .collect()
}

fn assert_files_unchanged(paths: &[PathBuf], before: &[(PathBuf, Vec<u8>)]) {
    assert_eq!(file_snapshot(paths), before);
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    let db_path = repo.join(".areamatrix").join("index.db");
    let connection = Connection::open(db_path).expect("open repository database");
    connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            [key],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .expect("query repo_config value")
}

fn assert_unacknowledged_onedrive_state(state: &CloudStorageState, repo: &Path) {
    assert_eq!(state.repo_path, path_string(repo));
    assert_eq!(state.provider_kind, CloudStorageProviderKind::OneDrive);
    assert_eq!(state.risk, CloudStorageRiskLevel::Medium);
    assert_eq!(
        state.placeholder_state,
        CloudPlaceholderState::NotPlaceholder
    );
    assert_eq!(state.permission_state, CloudPermissionState::Accessible);
    assert_eq!(
        state.recommended_action,
        CloudStorageRecommendedAction::AcknowledgeNotice
    );
    assert!(state.requires_notice_acknowledgement);
    assert!(!state.notice_acknowledged);
}

fn assert_acknowledged_onedrive_state(state: &CloudStorageState, repo: &Path) {
    assert_eq!(state.repo_path, path_string(repo));
    assert_eq!(state.provider_kind, CloudStorageProviderKind::OneDrive);
    assert_eq!(state.risk, CloudStorageRiskLevel::Medium);
    assert_eq!(
        state.recommended_action,
        CloudStorageRecommendedAction::None
    );
    assert!(!state.requires_notice_acknowledgement);
    assert!(state.notice_acknowledged);
}

#[test]
fn onedrive_risk_state_validation_proves_success_and_acknowledgement_paths() {
    let root = tempfile::tempdir().expect("create OneDrive validation root");
    let repo = create_onedrive_repo(root.path());
    init_empty_repo(&repo);
    let user_files = vec![repo.join("README.md"), repo.join("notes.txt")];
    fs::write(&user_files[0], b"user readme").expect("write user README");
    fs::write(&user_files[1], b"user notes").expect("write user notes");
    let before = file_snapshot(&user_files);

    let first =
        detect_cloud_storage_state(path_string(&repo)).expect("detect initial OneDrive state");
    assert_unacknowledged_onedrive_state(&first, &repo);
    assert_contains(&first.status_summary, "OneDrive path detected");
    assert_contains(&first.risk_reasons.join("\n"), "OneDrive SDK");
    assert_contains(&first.risk_reasons.join("\n"), "Conflict copies");
    assert_files_unchanged(&user_files, &before);

    let acknowledged = acknowledge_onedrive_risk_notice(path_string(&repo))
        .expect("acknowledge OneDrive risk notice");
    assert_acknowledged_onedrive_state(&acknowledged, &repo);
    assert_eq!(repo_config_value(&repo, ACK_KEY), Some("true".to_owned()));

    let reloaded =
        detect_cloud_storage_state(path_string(&repo)).expect("reload acknowledged state");
    assert_acknowledged_onedrive_state(&reloaded, &repo);
    assert_files_unchanged(&user_files, &before);
}

#[test]
fn onedrive_risk_state_validation_covers_failure_paths_without_mutation() {
    let root = tempfile::tempdir().expect("create OneDrive failure root");
    let repo = create_onedrive_repo(root.path());
    let user_file = repo.join("secret.txt");
    let file_path = repo.join("not-a-directory.txt");
    fs::write(&user_file, b"api_key=sk-secret").expect("write user file");
    fs::write(&file_path, b"not a directory").expect("write file path");
    let protected = vec![user_file.clone(), file_path.clone()];
    let before = file_snapshot(&protected);

    let empty = detect_cloud_storage_state(String::new()).expect_err("empty path is invalid");
    let internal = detect_cloud_storage_state(path_string(&repo.join(".areamatrix")))
        .expect_err("metadata path is invalid");
    let placeholder_path = repo.join("AreaMatrix.icloud");
    let placeholder = detect_cloud_storage_state(path_string(&placeholder_path))
        .expect_err("placeholder path is unavailable");
    let not_directory =
        detect_cloud_storage_state(path_string(&file_path)).expect_err("file path is invalid");
    let uninitialized_ack = acknowledge_onedrive_risk_notice(path_string(&repo))
        .expect_err("acknowledgement requires initialized metadata");

    assert_eq!(empty.kind(), ErrorKind::InvalidPath);
    assert_eq!(internal.kind(), ErrorKind::InvalidPath);
    assert_eq!(placeholder.kind(), ErrorKind::ICloudPlaceholder);
    assert_eq!(not_directory.kind(), ErrorKind::Io);
    assert_eq!(uninitialized_ack.kind(), ErrorKind::Io);
    assert!(matches!(
        placeholder,
        CoreError::ICloudPlaceholder { path } if path == path_string(&placeholder_path)
    ));
    assert!(!uninitialized_ack.raw_context().contains("sk-secret"));
    assert_files_unchanged(&protected, &before);
    assert!(!repo.join(".areamatrix").exists());
    assert!(!repo.join("AREAMATRIX.md").exists());
}

#[test]
fn onedrive_risk_state_validation_locks_api_udl_rust_and_test_evidence() {
    fn assert_detect(_: fn(String) -> CoreResult<CloudStorageState>) {}
    fn assert_acknowledge(_: fn(String) -> CoreResult<CloudStorageState>) {}
    assert_detect(detect_cloud_storage_state);
    assert_acknowledge(acknowledge_onedrive_risk_notice);

    assert_validation_docs_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_consumer_scope_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_validation_docs_alignment() {
    for fragment in [
        "# 4-3/task-69: C4-14 validation",
        "为 C4-14 onedrive-risk-state 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-69",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-14 onedrive-risk-state",
        "- S4-WIN-03 onedrive-notice",
        "- `detect_cloud_storage_state`",
        "- `acknowledge_onedrive_risk_notice`",
        "OneDrive risk state、placeholder state、recommended action。",
        "用户确认后返回已刷新的 OneDrive risk state。",
        "可记录用户已确认提示。",
        "只读探测。",
        "- `PermissionDenied`",
        "- `Io`",
        "只提示风险，不承诺控制 OneDrive 同步。",
        "用户确认状态可持久化。",
        "不使用 OneDrive SDK 管理用户文件。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        concat!(
            "| S4-WIN-01 | choose-repo | C4-09, C4-14 | Windows repo connect | ",
            "Windows path / OneDrive risk",
        ),
        concat!(
            "| S4-WIN-03 | onedrive-notice | C4-08, C4-14 | OneDrive risk state | ",
            "不控制 OneDrive 同步",
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
        "CloudStorageState detect_cloud_storage_state(string repo_path);",
        "CloudStorageState acknowledge_onedrive_risk_notice(string repo_path);",
        "dictionary CloudStorageState",
        "CloudStorageProviderKind provider_kind;",
        "CloudStorageRiskLevel risk;",
        "CloudPlaceholderState placeholder_state;",
        "CloudPermissionState permission_state;",
        "sequence<string> risk_reasons;",
        "CloudStorageRecommendedAction recommended_action;",
        "boolean requires_notice_acknowledgement;",
        "boolean notice_acknowledged;",
        "boolean can_retry;",
        "boolean requires_reconnect;",
        "enum CloudStorageRecommendedAction",
        "\"AcknowledgeNotice\"",
        "\"ChooseLocalFolder\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `detect_cloud_storage_state(repoPath) throws -> CloudStorageState`",
        "C4-08 的云盘权限状态入口，也是 C4-14 的 OneDrive 风险状态合同。",
        "OneDrive 路径默认返回 `AcknowledgeNotice`",
        "不调用 iCloud / OneDrive SDK",
        "不写 DB、不写 last cloud state",
        "### `acknowledge_onedrive_risk_notice(repoPath) throws -> CloudStorageState`",
        "C4-14 的 OneDrive 风险提示确认写入入口。",
        "只写 `.areamatrix/index.db` 中的 `repo_config` 元数据",
        "| `acknowledge_onedrive_risk_notice(repo)` | cloud | √ |",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in ["`PermissionDenied { path }`", "`Io { message }`"] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "pub fn detect_cloud_storage_state(repo_path: String) -> CoreResult<CloudStorageState>",
        "pub fn acknowledge_onedrive_risk_notice(repo_path: String)",
        "Detects C4-08 cloud storage provider state and C4-14 OneDrive risk state.",
        "Persists the C4-14 OneDrive risk notice acknowledgement.",
        "It does not create a repository, move,",
        "rename, delete, overwrite, reindex",
        "call the OneDrive",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C4-08 cloud storage permission and placeholder state contract.",
        "pub(crate) fn detect_cloud_storage_state(repo_path: String)",
        "pub(crate) fn acknowledge_onedrive_risk_notice(repo_path: String)",
        "platform-neutral and read-only",
        "The acknowledgement is stored only in initialized repository metadata.",
        "ONEDRIVE_NOTICE_ACK_KEY",
    ] {
        assert_contains(CLOUD_PERMISSION_RS, fragment);
    }
}

fn assert_consumer_scope_alignment() {
    for fragment in [
        "OneDrive 路径：必须进入 `onedrive-notice` 确认，不直接进入主窗口。",
        "选择 OneDrive 后必须经过 OneDrive 提示页。",
        "OneDrive 路径检测，包含用户目录下 `OneDrive` 和组织 OneDrive 命名。",
    ] {
        assert_contains(WIN_CHOOSE_REPO_PAGE, fragment);
    }

    for fragment in [
        "显示当前选择的 OneDrive 路径。",
        "提供确认复选框。",
        "已连接场景下显示只读状态，不要求重复确认。",
        "OneDrive 状态不可检测：显示 `Status: Unknown`，仍允许确认继续。",
        "本页不触发 reindex，不写入 repo。",
        "页面明确说明不控制 OneDrive 同步，也不使用 OneDrive SDK 管理同步。",
        "不出现“AreaMatrix 将自动解决冲突”的错误承诺。",
    ] {
        assert_contains(ONEDRIVE_NOTICE_PAGE, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "onedrive_risk_state_contract_exports_page_ready_state",
        "onedrive_risk_state_contract_detects_onedrive_without_side_effects",
        "onedrive_risk_state_docs_api_udl_and_control_map_stay_aligned",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "onedrive_risk_state_implementation_persists_notice_acknowledgement_via_core_api",
        "onedrive_risk_state_implementation_keeps_uninitialized_probe_read_only",
        "onedrive_risk_state_implementation_does_not_initialize_repo_when_acknowledging_notice",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "onedrive_risk_failure_invalid_inputs_and_io_errors_are_explicit",
        "onedrive_risk_failure_permission_denied_maps_to_user_action_without_mutation",
        "onedrive_risk_failure_detect_db_schema_error_is_reported_without_repair",
        "onedrive_risk_failure_acknowledge_write_error_leaves_no_half_metadata",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
