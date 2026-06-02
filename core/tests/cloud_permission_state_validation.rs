use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    detect_cloud_storage_state, CloudPermissionState, CloudPlaceholderState,
    CloudStorageProviderKind, CloudStorageRiskLevel, CloudStorageState, CoreError, CoreResult,
    ErrorKind, ErrorRecoverability,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-39-c4-08-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-08-cloud-permission-state.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const ICLOUD_PERMISSION_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-06-icloud-permission.md");
const ONEDRIVE_NOTICE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-03-onedrive-notice.md");
const CONNECT_REPO_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-01-connect-repo.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CLOUD_PERMISSION_RS: &str = include_str!("../src/cloud_permission_state.rs");
const CONTRACT_TEST: &str = include_str!("cloud_permission_state_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("cloud_permission_state_implementation.rs");
const FAILURE_TEST: &str = include_str!("cloud_permission_state_failure_recovery.rs");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn nested_repo(root: &Path, components: &[&str]) -> PathBuf {
    let repo = components
        .iter()
        .fold(root.to_path_buf(), |path, component| path.join(component));
    fs::create_dir_all(&repo).expect("create nested cloud repository path");
    repo
}

fn file_snapshot(paths: &[PathBuf]) -> Vec<(PathBuf, Vec<u8>)> {
    paths
        .iter()
        .map(|path| (path.clone(), fs::read(path).expect("read file snapshot")))
        .collect()
}

fn assert_no_probe_side_effects(repo: &Path, before: &[(PathBuf, Vec<u8>)]) {
    let paths = before
        .iter()
        .map(|(path, _)| path.clone())
        .collect::<Vec<_>>();
    assert_eq!(file_snapshot(&paths), before);
    assert!(!repo.join(".areamatrix").exists());
    assert!(!repo.join("AREAMATRIX.md").exists());
}

fn assert_accessible_state(
    state: &CloudStorageState,
    repo: &Path,
    provider: CloudStorageProviderKind,
    risk: CloudStorageRiskLevel,
) {
    assert_eq!(state.repo_path, path_string(repo));
    assert_eq!(state.provider_kind, provider);
    assert_eq!(state.risk, risk);
    assert_eq!(
        state.placeholder_state,
        CloudPlaceholderState::NotPlaceholder
    );
    assert_eq!(state.permission_state, CloudPermissionState::Accessible);
    assert!(!state.can_retry);
    assert!(!state.requires_reconnect);
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn cloud_permission_state_validation_proves_ui_ready_provider_states() {
    let root = tempfile::tempdir().expect("create cloud validation root");
    let local = nested_repo(root.path(), &["Users", "me", "Documents", "AreaMatrix"]);
    let icloud = nested_repo(
        root.path(),
        &[
            "Users",
            "me",
            "Library",
            "Mobile Documents",
            "com~apple~CloudDocs",
            "AreaMatrix",
        ],
    );
    let onedrive = nested_repo(root.path(), &["Users", "me", "OneDrive", "AreaMatrix"]);
    fs::write(local.join("README.md"), b"local user readme").expect("write local file");
    fs::write(icloud.join("report.txt"), b"icloud user file").expect("write iCloud file");
    fs::write(onedrive.join("spec.txt"), b"onedrive user file").expect("write OneDrive file");

    let local_before = file_snapshot(&[local.join("README.md")]);
    let icloud_before = file_snapshot(&[icloud.join("report.txt")]);
    let onedrive_before = file_snapshot(&[onedrive.join("spec.txt")]);

    let local_state = detect_cloud_storage_state(path_string(&local)).expect("detect local state");
    let icloud_state =
        detect_cloud_storage_state(path_string(&icloud)).expect("detect iCloud state");
    let onedrive_state =
        detect_cloud_storage_state(path_string(&onedrive)).expect("detect OneDrive state");

    assert_accessible_state(
        &local_state,
        &local,
        CloudStorageProviderKind::Local,
        CloudStorageRiskLevel::NoRisk,
    );
    assert!(local_state.risk_reasons.is_empty());
    assert_accessible_state(
        &icloud_state,
        &icloud,
        CloudStorageProviderKind::ICloudDrive,
        CloudStorageRiskLevel::Medium,
    );
    assert_contains(&icloud_state.status_summary, "iCloud Drive path detected");
    assert_contains(&icloud_state.risk_reasons.join("\n"), "placeholder files");
    assert_accessible_state(
        &onedrive_state,
        &onedrive,
        CloudStorageProviderKind::OneDrive,
        CloudStorageRiskLevel::Medium,
    );
    assert_contains(&onedrive_state.status_summary, "OneDrive path detected");
    assert_contains(&onedrive_state.risk_reasons.join("\n"), "OneDrive SDK");

    assert_no_probe_side_effects(&local, &local_before);
    assert_no_probe_side_effects(&icloud, &icloud_before);
    assert_no_probe_side_effects(&onedrive, &onedrive_before);
}

#[test]
fn cloud_permission_state_validation_covers_failures_without_mutation() {
    let repo = tempfile::tempdir().expect("create validation repository");
    let readme = repo.path().join("README.md");
    let note = repo.path().join("note.txt");
    let file_path = repo.path().join("not-a-directory.txt");
    fs::write(&readme, b"user readme").expect("write README");
    fs::write(&note, b"user note").expect("write note");
    fs::write(&file_path, b"not a directory").expect("write file path");
    let before = file_snapshot(&[readme, note, file_path.clone()]);

    let empty = detect_cloud_storage_state(String::new()).expect_err("empty path is invalid");
    let internal = detect_cloud_storage_state(path_string(&repo.path().join(".areamatrix")))
        .expect_err("metadata path is invalid");
    let placeholder_path = repo.path().join("AreaMatrix.icloud");
    let placeholder = detect_cloud_storage_state(path_string(&placeholder_path))
        .expect_err("placeholder path must be rejected");
    let not_directory =
        detect_cloud_storage_state(path_string(&file_path)).expect_err("file path is invalid");

    assert_eq!(empty.kind(), ErrorKind::InvalidPath);
    assert_eq!(internal.kind(), ErrorKind::InvalidPath);
    assert_eq!(placeholder.kind(), ErrorKind::ICloudPlaceholder);
    assert_eq!(
        placeholder.to_error_mapping().recoverability,
        ErrorRecoverability::Retryable
    );
    assert!(matches!(
        placeholder,
        CoreError::ICloudPlaceholder { path } if path == path_string(&placeholder_path)
    ));
    assert_eq!(not_directory.kind(), ErrorKind::Io);
    assert_no_probe_side_effects(repo.path(), &before);
    assert!(!placeholder_path.exists());
}

#[test]
fn cloud_permission_state_validation_locks_api_udl_rust_and_test_evidence() {
    fn assert_detect(_: fn(String) -> CoreResult<CloudStorageState>) {}
    assert_detect(detect_cloud_storage_state);

    assert_validation_docs_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_consumer_scope_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_validation_docs_alignment() {
    for fragment in [
        "# 4-3/task-39: C4-08 validation",
        "为 C4-08 cloud-permission-state 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-39",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-08 cloud-permission-state",
        "- S4-IOS-06 icloud-permission",
        "- S4-WIN-03 onedrive-notice",
        "计划新增：`detect_cloud_storage_state(repo_path) -> CloudStorageState`",
        "provider kind、risk、placeholder/permission state。",
        "只读探测。",
        "- `PermissionDenied`",
        "- `ICloudPlaceholder`",
        "- `Io`",
        "Core 不调用云盘 SDK 管理同步。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        concat!(
            "| S4-IOS-06 | icloud-permission | C4-08 | cloud permission state | ",
            "Core 不管理 iCloud 同步",
        ),
        concat!(
            "| S4-WIN-03 | onedrive-notice | C4-08, C4-14 | OneDrive risk state | ",
            "不控制 OneDrive 同步",
        ),
        "平台差异必须结构化暴露。",
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
        "dictionary CloudStorageState",
        "CloudStorageProviderKind provider_kind;",
        "CloudStorageRiskLevel risk;",
        "CloudPlaceholderState placeholder_state;",
        "CloudPermissionState permission_state;",
        "sequence<string> risk_reasons;",
        "boolean can_retry;",
        "boolean requires_reconnect;",
        "enum CloudStorageProviderKind { \"Local\", \"ICloudDrive\", \"OneDrive\", \"Unknown\" };",
        "enum CloudStorageRiskLevel { \"NoRisk\", \"Low\", \"Medium\", \"High\", \"Unknown\" };",
        "enum CloudPlaceholderState { \"NotPlaceholder\", \"Placeholder\", \"Unknown\" };",
        concat!(
            "enum CloudPermissionState { \"Accessible\", \"PermissionDenied\", ",
            "\"AccessExpired\", \"Unknown\" };",
        ),
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `detect_cloud_storage_state(repoPath) throws -> CloudStorageState`",
        "C4-08 的云盘权限状态入口",
        "不写 DB、不写 last cloud state",
        "不触发 iCloud placeholder 下载，不调用 iCloud / OneDrive SDK",
        concat!(
            "| `detect_cloud_storage_state(repo)` | cloud | √ | ",
            "ICloudPlaceholder / PermissionDenied / Io |",
        ),
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "pub fn detect_cloud_storage_state(repo_path: String) -> CoreResult<CloudStorageState>",
        "provider-specific recovery or notice state from structured fields",
        "security-scoped bookmarks, iCloud availability, OneDrive client state",
        "provider downloads, and reconnect UI remain in",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C4-08 cloud storage permission and placeholder state contract.",
        "pub(crate) fn detect_cloud_storage_state(repo_path: String)",
        "platform-neutral and read-only",
        "Cloud storage provider inferred from an authorized repository path.",
        "Structured C4-08 cloud state returned to iOS and Windows recovery surfaces.",
    ] {
        assert_contains(CLOUD_PERMISSION_RS, fragment);
    }
}

fn assert_consumer_scope_alignment() {
    for fragment in [
        "iCloud availability detection。",
        "security scoped bookmark validation。",
        "占位符未下载：显示重试",
        "security scoped bookmark 失效：显示重新连接文件夹。",
        "不承诺 AreaMatrix 能替用户开启系统 iCloud 设置。",
    ] {
        assert_contains(ICLOUD_PERMISSION_PAGE, fragment);
    }

    for fragment in [
        "OneDrive path detection。",
        "AreaMatrix cannot control OneDrive sync timing.",
        "本页不触发 reindex，不写入 repo。",
        "页面明确说明不控制 OneDrive 同步，也不使用 OneDrive SDK 管理同步。",
    ] {
        assert_contains(ONEDRIVE_NOTICE_PAGE, fragment);
    }

    for fragment in [
        "iCloud 不可用时能进入权限提示页",
        "选择目录后先执行只读校验",
        "是否处于 iCloud 占位状态。",
    ] {
        assert_contains(CONNECT_REPO_PAGE, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "cloud_permission_state_contract_exports_signature_outputs_and_errors",
        "cloud_permission_state_docs_core_api_and_udl_stay_aligned",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "cloud_permission_state_implementation_detects_local_repo_read_only",
        "cloud_permission_state_implementation_detects_icloud_risk_without_downloads",
        "cloud_permission_state_implementation_detects_onedrive_risk_without_sdk_state",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "cloud_permission_state_failure_invalid_inputs_are_explicit_and_side_effect_free",
        "cloud_permission_state_failure_placeholder_maps_to_retryable_error_without_downloads",
        "cloud_permission_state_failure_permission_denied_requires_reconnect_without_mutation",
        "cloud_permission_state_failure_corrupted_db_is_not_read_or_repaired_by_probe",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
