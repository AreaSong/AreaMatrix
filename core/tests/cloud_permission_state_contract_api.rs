use std::{fs, path::Path};

use area_matrix_core::{
    detect_cloud_storage_state, CloudPermissionState, CloudPlaceholderState,
    CloudStorageProviderKind, CloudStorageRecommendedAction, CloudStorageRiskLevel,
    CloudStorageState, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../workflow/versions/v1-mvp/execution/phase-4/4-3-stage4-multiplatform/task-36-c4-08-contract-api.md"
);
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
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
        recommended_action: CloudStorageRecommendedAction::None,
        requires_notice_acknowledgement: false,
        notice_acknowledged: false,
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
        "CloudStorageState detect_cloud_storage_state(string repo_path);",
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
        "enum CloudStorageProviderKind { \"Local\", \"ICloudDrive\", \"OneDrive\", \"Unknown\" };",
        "enum CloudStorageRiskLevel { \"NoRisk\", \"Low\", \"Medium\", \"High\", \"Unknown\" };",
        "enum CloudPlaceholderState { \"NotPlaceholder\", \"Placeholder\", \"Unknown\" };",
        "enum CloudPermissionState { \"Accessible\", \"PermissionDenied\", \"AccessExpired\", \"Unknown\" };",
        "\"AcknowledgeNotice\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `detect_cloud_storage_state(repo)` | cloud | √ | ICloudPlaceholder / PermissionDenied / Io |",
        "### `detect_cloud_storage_state(repoPath) throws -> CloudStorageState`",
        "cloud storage state 的云盘权限状态入口",
        "不写 DB、不写 last cloud state",
        "不触发 iCloud placeholder 下载，不调用 iCloud / OneDrive SDK",
        "iCloud permission surface 可以从 `provider_kind`",
        "OneDrive notice surface 可以从 `provider_kind = OneDrive`",
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
        "Detects cloud storage provider",
        "provider-specific recovery or notice state from structured fields",
        "inspects only the authorized repository path",
        "security-scoped bookmarks, iCloud availability, OneDrive client state",
        "settings links, SDK calls, provider downloads, acknowledgement UI",
        "reconnect UI remain in",
        "the platform layer",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "cloud storage permission and placeholder state contract.",
        "Cloud storage provider inferred from an authorized repository path.",
        "Coarse cloud-storage risk level consumed by recovery and notice pages.",
        "Placeholder availability state for cloud-backed paths.",
        "Permission state for the repository path.",
        "Structured cloud storage state returned to iOS and Windows recovery surfaces.",
        "platform-neutral and read-only",
        "iCloud, OneDrive, document",
        "picker, SDK, settings, acknowledgement UI, and security-scoped bookmark",
        "recovery stay in the",
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
