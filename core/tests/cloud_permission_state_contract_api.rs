use std::{fs, path::Path};

use area_matrix_core::{
    detect_cloud_storage_state, CloudPermissionState, CloudPlaceholderState,
    CloudStorageProviderKind, CloudStorageRiskLevel, CloudStorageState, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-36-c4-08-contract-api.md"
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
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const CLOUD_PERMISSION_RS: &str = include_str!("../src/cloud_permission_state.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
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
fn cloud_permission_state_contract_exports_signature_outputs_and_errors() {
    fn assert_detect(_: fn(String) -> CoreResult<CloudStorageState>) {}
    assert_detect(detect_cloud_storage_state);

    let state = CloudStorageState {
        repo_path: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/AreaMatrix".to_owned(),
        provider_kind: CloudStorageProviderKind::ICloudDrive,
        risk: CloudStorageRiskLevel::Medium,
        placeholder_state: CloudPlaceholderState::NotPlaceholder,
        permission_state: CloudPermissionState::Accessible,
        status_summary: "iCloud Drive path detected".to_owned(),
        risk_reasons: vec!["iCloud may expose placeholder files.".to_owned()],
        can_retry: false,
        requires_reconnect: false,
    };
    assert_eq!(state.provider_kind, CloudStorageProviderKind::ICloudDrive);
    assert_eq!(state.risk, CloudStorageRiskLevel::Medium);
    assert_eq!(
        state.placeholder_state,
        CloudPlaceholderState::NotPlaceholder
    );
    assert_eq!(state.permission_state, CloudPermissionState::Accessible);
    assert_eq!(state.risk_reasons.len(), 1);

    let documented_errors = [
        CoreError::permission_denied("cloud metadata permission denied"),
        CoreError::icloud_placeholder("cloud placeholder"),
        CoreError::io("cloud state filesystem failure"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn cloud_permission_state_contract_returns_structured_local_state_without_writes() {
    let repo = tempfile::tempdir().expect("create local repository directory");
    fs::write(repo.path().join("README.md"), "user content\n").expect("write user file");

    let state =
        detect_cloud_storage_state(path_string(repo.path())).expect("detect local cloud state");

    assert_eq!(state.repo_path, path_string(repo.path()));
    assert_eq!(state.provider_kind, CloudStorageProviderKind::Local);
    assert_eq!(state.risk, CloudStorageRiskLevel::NoRisk);
    assert_eq!(
        state.placeholder_state,
        CloudPlaceholderState::NotPlaceholder
    );
    assert_eq!(state.permission_state, CloudPermissionState::Accessible);
    assert!(state.risk_reasons.is_empty());
    assert!(!state.can_retry);
    assert!(!state.requires_reconnect);
    assert!(!repo.path().join(".areamatrix").exists());
    assert_eq!(
        fs::read_to_string(repo.path().join("README.md")).expect("read user file"),
        "user content\n"
    );
}

#[test]
fn cloud_permission_state_contract_rejects_placeholder_marker_without_side_effects() {
    let repo = tempfile::tempdir().expect("create temporary root");
    let placeholder = repo.path().join("AreaMatrix.icloud");

    let result = detect_cloud_storage_state(path_string(&placeholder));

    assert!(matches!(result, Err(CoreError::ICloudPlaceholder { .. })));
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn cloud_permission_state_docs_core_api_and_udl_stay_aligned() {
    for fragment in [
        "# 4-3/task-36: C4-08 contract-api",
        "为 C4-08 cloud-permission-state 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
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
        "iCloud/OneDrive 风险提示来自结构化状态。",
        "Core 不调用云盘 SDK 管理同步。",
        "不建议危险 chmod/sudo 操作。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-01 | connect-repo | C4-02, C4-08 | repo validate/init/adopt | iOS security-scoped URL",
        "| S4-IOS-06 | icloud-permission | C4-08 | cloud permission state | Core 不管理 iCloud 同步",
        "| S4-WIN-03 | onedrive-notice | C4-08, C4-14 | OneDrive risk state | 不控制 OneDrive 同步",
        "平台差异必须结构化暴露。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

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
        "enum CloudPermissionState { \"Accessible\", \"PermissionDenied\", \"AccessExpired\", \"Unknown\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `detect_cloud_storage_state(repo)` | cloud | √ | ICloudPlaceholder / PermissionDenied / Io |",
        "### `detect_cloud_storage_state(repoPath) throws -> CloudStorageState`",
        "C4-08 的云盘权限状态入口",
        "不写 DB、不写 last cloud state",
        "不触发 iCloud placeholder 下载，不调用 iCloud / OneDrive SDK",
        "S4-IOS-06 可以从 `provider_kind`",
        "S4-WIN-03 可以从 `provider_kind = OneDrive`",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "`ICloudPlaceholder { path }`",
        "`PermissionDenied { path }`",
        "`Io { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn cloud_permission_state_documents_consumers_and_scope_boundaries() {
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
        "可选 OneDrive sync status probe，状态不可得时降级为 unknown。",
        "AreaMatrix cannot control OneDrive sync timing.",
        "本页不触发 reindex，不写入 repo。",
        "页面明确说明不控制 OneDrive 同步，也不使用 OneDrive SDK 管理同步。",
    ] {
        assert_contains(ONEDRIVE_NOTICE_PAGE, fragment);
    }

    for fragment in [
        "iCloud availability 检测。",
        "iCloud 不可用时能进入权限提示页",
        "选择目录后先执行只读校验",
        "是否处于 iCloud 占位状态。",
    ] {
        assert_contains(CONNECT_REPO_PAGE, fragment);
    }

    for fragment in [
        "Detects C4-08 cloud storage provider",
        "provider-specific recovery or notice state from structured fields",
        "inspects only the authorized repository path",
        "security-scoped bookmarks, iCloud availability, OneDrive client state",
        "settings links, SDK calls, provider downloads, and reconnect UI remain in",
        "the platform layer",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C4-08 cloud storage permission and placeholder state contract.",
        "Cloud storage provider inferred from an authorized repository path.",
        "Coarse cloud-storage risk level consumed by recovery and notice pages.",
        "Placeholder availability state for cloud-backed paths.",
        "Permission state for the repository path.",
        "Structured C4-08 cloud state returned to iOS and Windows recovery surfaces.",
        "platform-neutral and read-only",
        "iCloud, OneDrive, document",
        "picker, SDK, settings, and security-scoped bookmark recovery stay in the",
        "platform layer",
    ] {
        assert_contains(CLOUD_PERMISSION_RS, fragment);
    }

    for fragment in [
        "CloudPermissionState, CloudPlaceholderState, CloudStorageProviderKind",
        "CloudStorageRiskLevel",
        "CloudStorageState",
    ] {
        assert_contains(LIB_RS, fragment);
    }
}
