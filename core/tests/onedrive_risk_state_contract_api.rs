use std::{fs, path::Path};

use area_matrix_core::{
    acknowledge_onedrive_risk_notice, detect_cloud_storage_state, CloudPermissionState,
    CloudPlaceholderState, CloudStorageProviderKind, CloudStorageRecommendedAction,
    CloudStorageRiskLevel, CloudStorageState, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../workflow/versions/v1-mvp/execution/phase-4/4-3-stage4-multiplatform/task-66-c4-14-contract-api.md"
);
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
fn onedrive_risk_state_contract_exports_page_ready_state() {
    fn assert_detect(_: fn(String) -> CoreResult<CloudStorageState>) {}
    fn assert_acknowledge(_: fn(String) -> CoreResult<CloudStorageState>) {}
    assert_detect(detect_cloud_storage_state);
    assert_acknowledge(acknowledge_onedrive_risk_notice);

    let state = CloudStorageState {
        repo_path: "C:\\Users\\me\\OneDrive\\AreaMatrix".to_owned(),
        provider_kind: CloudStorageProviderKind::OneDrive,
        risk: CloudStorageRiskLevel::Medium,
        placeholder_state: CloudPlaceholderState::NotPlaceholder,
        permission_state: CloudPermissionState::Accessible,
        status_summary: "OneDrive path detected".to_owned(),
        risk_reasons: vec![
            "Files may appear before cloud sync has completed.".to_owned(),
            "Core does not use the OneDrive SDK or change OneDrive settings.".to_owned(),
        ],
        recommended_action: CloudStorageRecommendedAction::AcknowledgeNotice,
        requires_notice_acknowledgement: true,
        notice_acknowledged: false,
        can_retry: false,
        requires_reconnect: false,
    };

    assert_eq!(state.provider_kind, CloudStorageProviderKind::OneDrive);
    assert_eq!(state.risk, CloudStorageRiskLevel::Medium);
    assert_eq!(
        state.recommended_action,
        CloudStorageRecommendedAction::AcknowledgeNotice
    );
    assert!(state.requires_notice_acknowledgement);
    assert!(!state.notice_acknowledged);

    let documented_errors = [
        CoreError::permission_denied("OneDrive path permission denied"),
        CoreError::io("OneDrive risk probe failed"),
    ];
    assert_eq!(documented_errors.len(), 2);
}

#[test]
fn onedrive_risk_state_contract_detects_onedrive_without_side_effects() {
    let root = tempfile::tempdir().expect("create OneDrive risk root");
    let repo = root
        .path()
        .join("C:\\Users\\me\\OneDrive - Example Org\\AreaMatrix");
    fs::create_dir_all(&repo).expect("create OneDrive-shaped repository path");
    fs::write(repo.join("README.md"), "user content\n").expect("write user file");
    let before = fs::read_to_string(repo.join("README.md")).expect("read user file");

    let state = detect_cloud_storage_state(path_string(&repo)).expect("detect OneDrive risk state");

    assert_eq!(state.repo_path, path_string(&repo));
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
    assert!(state.status_summary.contains("OneDrive path detected"));
    assert!(state
        .risk_reasons
        .iter()
        .any(|reason| reason.to_ascii_lowercase().contains("conflict copies")));
    assert!(state
        .risk_reasons
        .iter()
        .any(|reason| reason.contains("OneDrive SDK")));
    assert!(!state.can_retry);
    assert!(!state.requires_reconnect);
    assert_eq!(
        fs::read_to_string(repo.join("README.md")).expect("read preserved user file"),
        before
    );
    assert!(!repo.join(".areamatrix").exists());
}

#[test]
fn onedrive_risk_state_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-66: C4-14 contract-api",
        "为 C4-14 onedrive-risk-state 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

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
        "enum CloudStorageRecommendedAction",
        "\"AcknowledgeNotice\"",
        "\"RetryStatusCheck\"",
        "\"ReconnectFolder\"",
        "\"ChooseLocalFolder\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "也是 C4-14 的 OneDrive 风险状态合同",
        "### `acknowledge_onedrive_risk_notice(repoPath) throws -> CloudStorageState`",
        "C4-14 的 OneDrive 风险提示确认写入入口。",
        "`recommended_action`",
        "`requires_notice_acknowledgement`",
        "`notice_acknowledged`",
        "OneDrive 路径默认返回 `AcknowledgeNotice`",
        "C4-14 通过 `acknowledge_onedrive_risk_notice` 在已初始化 repo 的 `repo_config` 中持久化该状态。",
        "S4-WIN-01 可以从 OneDrive path validation 路由到 S4-WIN-03",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in ["`PermissionDenied { path }`", "`Io { message }`"] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn onedrive_risk_state_documents_consumers_and_scope_boundaries() {
    for fragment in [
        "Detects C4-08 cloud storage provider state and C4-14 OneDrive risk state.",
        "recommended_action",
        "requires_notice_acknowledgement",
        "notice_acknowledged",
        "acknowledgement UI",
        "Persists the C4-14 OneDrive risk notice acknowledgement.",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Primary cloud-storage action recommended to the platform shell.",
        "AcknowledgeNotice",
        "Whether the OneDrive notice must be acknowledged before continuing.",
        "Detects C4-08 cloud provider state and C4-14 OneDrive risk state.",
        "acknowledgement UI",
        "Persists the C4-14 OneDrive notice acknowledgement and returns refreshed state.",
    ] {
        assert_contains(CLOUD_PERMISSION_RS, fragment);
    }

    for fragment in ["CloudStorageRecommendedAction", "CloudStorageState"] {
        assert_contains(LIB_RS, fragment);
    }
}
