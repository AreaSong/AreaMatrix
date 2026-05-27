use area_matrix_core::{
    get_local_model_status, init_repo, locate_local_model_folder, AiFeatureKind, CoreError,
    CoreResult, LocalModelAvailability, LocalModelCachedStatus, LocalModelFeatureStatus,
    LocalModelFolderLocation, LocalModelFolderRequest, LocalModelRecommendedAction,
    LocalModelStatusRequest, LocalModelStatusSnapshot, OverviewOutput, RepoInitMode,
    RepoInitOptions,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-2-stage3-ai/task-06-c3-02-contract-api.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-02-local-model-status.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const LOCAL_MODEL_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-02-local-model-status.md");
const AI_SETTINGS_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-01-ai-settings.md");
const FALLBACK_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-10-ai-fallback.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const LOCAL_MODEL_STATUS_RS: &str = include_str!("../src/local_model_status.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn status_request() -> LocalModelStatusRequest {
    LocalModelStatusRequest {
        model_id: "areamatrix-local-classifier".to_owned(),
        storage_location: "~/Library/Application Support/AreaMatrix/Models".to_owned(),
        cached_status: Some(LocalModelCachedStatus {
            model_id: "areamatrix-local-classifier".to_owned(),
            storage_location: "~/Library/Application Support/AreaMatrix/Models".to_owned(),
            availability: LocalModelAvailability::Unknown,
            version: None,
            size_bytes: None,
            last_error: None,
            recommended_action: LocalModelRecommendedAction::CheckStatus,
            last_checked_at: None,
            diagnostics_summary: "manifest unknown; runtime not checked".to_owned(),
        }),
    }
}

#[test]
fn local_model_status_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_status(
        _: fn(String, LocalModelStatusRequest) -> CoreResult<LocalModelStatusSnapshot>,
    ) {
    }
    fn assert_location(
        _: fn(String, LocalModelFolderRequest) -> CoreResult<LocalModelFolderLocation>,
    ) {
    }

    assert_status(get_local_model_status);
    assert_location(locate_local_model_folder);

    let snapshot = LocalModelStatusSnapshot {
        model_id: "areamatrix-local-classifier".to_owned(),
        storage_location: "~/Library/Application Support/AreaMatrix/Models".to_owned(),
        availability: LocalModelAvailability::Corrupted,
        version: Some("1.0.3".to_owned()),
        size_bytes: Some(2_400_000_000),
        last_error: Some("manifest checksum mismatch".to_owned()),
        recommended_action: LocalModelRecommendedAction::RepairMetadata,
        last_checked_at: Some(1_777_300_800),
        diagnostics_summary: "manifest checksum mismatch; runtime not started".to_owned(),
        feature_statuses: vec![LocalModelFeatureStatus {
            feature: AiFeatureKind::ClassificationSuggestions,
            available: false,
            unavailable_reason: Some("Model metadata is corrupted".to_owned()),
        }],
    };
    assert_eq!(snapshot.availability, LocalModelAvailability::Corrupted);
    assert_eq!(
        snapshot.recommended_action,
        LocalModelRecommendedAction::RepairMetadata
    );
    assert_eq!(
        snapshot.feature_statuses[0].feature,
        AiFeatureKind::ClassificationSuggestions
    );

    let location = LocalModelFolderLocation {
        model_id: snapshot.model_id.clone(),
        folder_path: snapshot.storage_location.clone(),
        exists: true,
        readable: false,
        openable: false,
        unavailable_reason: Some("Model path is not readable".to_owned()),
    };
    assert!(location.exists);
    assert!(!location.readable);
    assert_eq!(
        location.unavailable_reason.as_deref(),
        Some("Model path is not readable")
    );

    let documented_errors = [
        CoreError::config("invalid local model status request"),
        CoreError::permission_denied("model folder unreadable"),
        CoreError::io("manifest read failed"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn local_model_status_contract_rejects_invalid_inputs_without_fake_success() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");

    assert!(matches!(
        get_local_model_status(String::new(), status_request()),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        locate_local_model_folder(
            String::new(),
            LocalModelFolderRequest {
                model_id: "areamatrix-local-classifier".to_owned(),
                storage_location: "~/Library/Application Support/AreaMatrix/Models".to_owned(),
            }
        ),
        Err(CoreError::Config { .. })
    ));

    let mut mismatched_cached = status_request();
    mismatched_cached
        .cached_status
        .as_mut()
        .expect("test request has cached status")
        .model_id = "other-model".to_owned();
    assert!(matches!(
        get_local_model_status(
            repo.path().to_string_lossy().into_owned(),
            mismatched_cached
        ),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn local_model_status_contract_returns_structured_missing_status_after_implementation() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        repo.path().to_string_lossy().into_owned(),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");
    let missing_model = repo.path().join("models/missing");

    let snapshot = get_local_model_status(
        repo.path().to_string_lossy().into_owned(),
        LocalModelStatusRequest {
            model_id: "areamatrix-local-classifier".to_owned(),
            storage_location: missing_model.to_string_lossy().into_owned(),
            cached_status: None,
        },
    )
    .expect("missing local model returns structured status");

    assert_eq!(snapshot.availability, LocalModelAvailability::NotInstalled);
    assert_eq!(
        snapshot.recommended_action,
        LocalModelRecommendedAction::OpenInstallHelp
    );
}

#[test]
fn local_model_status_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-2/task-06: C3-02 contract-api",
        "为 C3-02 local-model-status 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C3-02 local-model-status",
        "- S3-02 local-model-status",
        "计划新增：`get_local_model_status`、`locate_local_model_folder`",
        "model id、storage location、cached status snapshot。",
        "availability、version、size、last_error、recommended_action、last_checked_at、diagnostics_summary。",
        "读取本地模型 manifest、模型目录元数据和 runtime 状态。",
        "不下载、安装、删除或训练模型；安装器/下载器需要独立规格。",
        "- `Config`",
        "- `PermissionDenied`",
        "- `Io`",
        "本地模型不可用时不阻断 Core 基础功能。",
        "状态检测或定位失败不启用远程 fallback。",
        "健康检查和 diagnostics summary 不读取用户文件正文。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-02 | local-model-status | C3-02 | local model status | model metadata / cache",
        "AI 默认关闭，本地优先。",
        "远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "LocalModelStatusSnapshot get_local_model_status(",
        "string repo_path, LocalModelStatusRequest request",
        "LocalModelFolderLocation locate_local_model_folder(",
        "dictionary LocalModelCachedStatus",
        "LocalModelAvailability availability;",
        "LocalModelRecommendedAction recommended_action;",
        "dictionary LocalModelStatusSnapshot",
        "sequence<LocalModelFeatureStatus> feature_statuses;",
        "dictionary LocalModelFolderLocation",
        "boolean openable;",
        "enum LocalModelAvailability",
        "\"Ready\"",
        "\"PathUnreadable\"",
        "\"VersionIncompatible\"",
        "\"RuntimeFailed\"",
        "enum LocalModelRecommendedAction",
        "\"OpenInstallHelp\"",
        "\"OpenModelLocation\"",
        "\"RepairMetadata\"",
        "\"UseNonAiFallback\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `get_local_model_status(repo, request)` | ai | √ | Config / PermissionDenied / Io |",
        "| `locate_local_model_folder(repo, request)` | ai | √ | Config / PermissionDenied / Io |",
        "### `get_local_model_status(repoPath: String, request: LocalModelStatusRequest) throws -> LocalModelStatusSnapshot`",
        "### `locate_local_model_folder(repoPath: String, request: LocalModelFolderRequest) throws -> LocalModelFolderLocation`",
        "不下载、安装、删除、训练模型",
        "不自动启用远程 fallback",
        "S3-03 仍负责远程 provider/key/连接测试",
        "C3-10 仍负责",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Io"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}

#[test]
fn local_model_status_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "显示本地模型运行状态。",
        "显示模型名称、版本、大小、存储位置。",
        "显示最后状态检查时间、不可用原因和健康检查结果。",
        "提供重试状态检查、打开安装帮助、打开模型位置、健康检查和诊断入口。",
        "Status: Ready",
        "Not installed",
        "Path unreadable",
        "Version incompatible",
        "Loading",
        "Error",
        "Checking local model status...",
        "Verifying model manifest...",
        "Run health check",
        "Open diagnostics",
        "本地模型状态不可用不应自动启用远程 AI。",
        "健康检查只测试 runtime 和模型 manifest，不读取用户文件内容。",
        "Repair` 只允许重建 AreaMatrix 本地模型状态缓存、manifest 校验缓存和模型 metadata index",
        "不得切换远程 provider",
    ] {
        assert_contains(LOCAL_MODEL_PAGE, fragment);
    }

    for fragment in [
        "AI 设置页点击 `Local model status`",
        "本地 AI 功能失败时点击 `View local model status`",
    ] {
        assert_contains(LOCAL_MODEL_PAGE, fragment);
    }

    assert_contains(AI_SETTINGS_PAGE, "Local model status");

    assert_contains(FALLBACK_PAGE, "Open local model status");

    assert_contains(
        LOCAL_MODEL_STATUS_RS,
        "C3-02 local model status contract types",
    );
    for fragment in [
        "inspect_local_model",
        "update_local_model_status_record",
        "local model diagnostics summary contains disallowed content",
        "sk-",
        "remote_provider",
    ] {
        assert_contains(LOCAL_MODEL_STATUS_RS, fragment);
    }

    for fragment in [
        "This API must not download, install, delete, train",
        "enable remote fallback",
        "expose API keys/provider config through diagnostics",
        "Core must not create missing folders",
    ] {
        assert_contains(API_RS, fragment);
    }
}
