use std::{fs, path::Path};

use area_matrix_core::{
    detect_cloud_storage_state, CloudPermissionState, CloudPlaceholderState,
    CloudStorageProviderKind, CloudStorageRecommendedAction, CloudStorageRiskLevel,
    CloudStorageState, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-66-c4-14-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-14-onedrive-risk-state.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const WIN_CHOOSE_REPO_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-01-choose-repo.md");
const ONEDRIVE_NOTICE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-03-onedrive-notice.md");
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
    assert_detect(detect_cloud_storage_state);

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
        "# C4-14 onedrive-risk-state",
        "- S4-WIN-03 onedrive-notice",
        "- `detect_cloud_storage_state`",
        "OneDrive risk state、placeholder state、recommended action。",
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
        "| S4-WIN-01 | choose-repo | C4-09, C4-14 | Windows repo connect | Windows path / OneDrive risk",
        "| S4-WIN-03 | onedrive-notice | C4-08, C4-14 | OneDrive risk state | 不控制 OneDrive 同步",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
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
        "`recommended_action`",
        "`requires_notice_acknowledgement`",
        "`notice_acknowledged`",
        "OneDrive 路径默认返回 `AcknowledgeNotice`",
        "当前合同只定义读取状态；确认写入和 DB 细节由后续 C4-14 implementation task 实现。",
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
        "OneDrive 路径：必须进入 `onedrive-notice` 确认，不直接进入主窗口。",
        "OneDrive 路径检测，包含用户目录下 `OneDrive` 和组织 OneDrive 命名。",
        "选择 OneDrive 后必须经过 OneDrive 提示页。",
    ] {
        assert_contains(WIN_CHOOSE_REPO_PAGE, fragment);
    }

    for fragment in [
        "显示当前选择的 OneDrive 路径。",
        "提供确认复选框。",
        "提供等待同步、打开 OneDrive 文件夹、进入 watcher 状态页的可操作建议。",
        "已连接场景下显示只读状态，不要求重复确认。",
        "OneDrive 状态不可检测：显示 `Status: Unknown`，仍允许确认继续。",
        "本页不触发 reindex，不写入 repo。",
        "页面明确说明不控制 OneDrive 同步，也不使用 OneDrive SDK 管理同步。",
        "不出现“AreaMatrix 将自动解决冲突”的错误承诺。",
    ] {
        assert_contains(ONEDRIVE_NOTICE_PAGE, fragment);
    }

    for fragment in [
        "Detects C4-08 cloud storage provider state and C4-14 OneDrive risk state.",
        "recommended_action",
        "requires_notice_acknowledgement",
        "notice_acknowledged",
        "acknowledgement persistence",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Primary cloud-storage action recommended to the platform shell.",
        "AcknowledgeNotice",
        "Whether the OneDrive notice must be acknowledged before continuing.",
        "Detects C4-08 cloud provider state and C4-14 OneDrive risk state.",
        "acknowledgement UI",
    ] {
        assert_contains(CLOUD_PERMISSION_RS, fragment);
    }

    for fragment in ["CloudStorageRecommendedAction", "CloudStorageState"] {
        assert_contains(LIB_RS, fragment);
    }
}
