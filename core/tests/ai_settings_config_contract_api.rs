use std::path::Path;

use area_matrix_core::{
    load_ai_config, update_ai_config, AiCapabilityState, AiConfig, AiConfigSnapshot,
    AiFeatureConfig, AiFeatureKind, AiProviderPreference, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-01-ai-settings-config.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const AI_SETTINGS_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-01-ai-settings.md");
const AI_PRIVACY_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-3-ai/S3-09-ai-privacy-rules.md");
const STAGE_3_INDEX: &str = include_str!("../../docs/ux/page-specs/stage-3-ai.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const AI_SETTINGS_RS: &str = include_str!("../src/ai_settings.rs");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn feature_toggles() -> Vec<AiFeatureConfig> {
    vec![
        AiFeatureConfig {
            feature: AiFeatureKind::ClassificationSuggestions,
            enabled: true,
            allow_remote: false,
        },
        AiFeatureConfig {
            feature: AiFeatureKind::AutoSummaries,
            enabled: true,
            allow_remote: true,
        },
        AiFeatureConfig {
            feature: AiFeatureKind::AutoTags,
            enabled: false,
            allow_remote: true,
        },
        AiFeatureConfig {
            feature: AiFeatureKind::SemanticSearch,
            enabled: false,
            allow_remote: false,
        },
    ]
}

fn ai_config(repo_path: String) -> AiConfig {
    AiConfig {
        repo_path,
        ai_enabled: true,
        provider_preference: AiProviderPreference::LocalFirst,
        local_ai_enabled: true,
        remote_ai_allowed: false,
        privacy_gate_enabled: false,
        privacy_policy_ref: Some("default-remote-gate".to_owned()),
        feature_toggles: feature_toggles(),
    }
}

#[test]
fn ai_settings_config_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_load(_: fn(String) -> CoreResult<AiConfigSnapshot>) {}
    fn assert_update(_: fn(String, AiConfig) -> CoreResult<AiConfigSnapshot>) {}

    assert_load(load_ai_config);
    assert_update(update_ai_config);

    let config = ai_config("/tmp/repo".to_owned());
    assert!(config.ai_enabled);
    assert_eq!(config.provider_preference, AiProviderPreference::LocalFirst);
    assert!(config.local_ai_enabled);
    assert!(!config.remote_ai_allowed);
    assert_eq!(
        config.privacy_policy_ref.as_deref(),
        Some("default-remote-gate")
    );
    assert_eq!(config.feature_toggles.len(), 4);

    let snapshot = AiConfigSnapshot {
        config,
        capabilities: vec![AiCapabilityState {
            feature: AiFeatureKind::AutoSummaries,
            enabled: true,
            local_allowed: true,
            remote_allowed: false,
            disabled_reason: None,
        }],
        updated_at: Some(1_000),
    };
    assert_eq!(
        snapshot.capabilities[0].feature,
        AiFeatureKind::AutoSummaries
    );
    assert!(snapshot.capabilities[0].local_allowed);
    assert!(!snapshot.capabilities[0].remote_allowed);

    let documented_errors = [
        CoreError::config("invalid AI config"),
        CoreError::permission_denied("metadata unavailable"),
        CoreError::io("metadata inspection failed"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn ai_settings_config_contract_loads_default_off_without_side_effects() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");

    let snapshot = load_ai_config(path_string(repo.path())).expect("load default AI config");

    assert_eq!(snapshot.config.repo_path, path_string(repo.path()));
    assert!(!snapshot.config.ai_enabled);
    assert_eq!(
        snapshot.config.provider_preference,
        AiProviderPreference::LocalFirst
    );
    assert!(snapshot.config.local_ai_enabled);
    assert!(!snapshot.config.remote_ai_allowed);
    assert!(!snapshot.config.privacy_gate_enabled);
    assert!(snapshot.config.privacy_policy_ref.is_none());
    assert_eq!(snapshot.config.feature_toggles.len(), 4);
    assert!(snapshot.capabilities.iter().all(|state| !state.enabled));
    assert!(snapshot
        .capabilities
        .iter()
        .all(|state| { state.disabled_reason.as_deref() == Some("AI is off") }));
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn ai_settings_config_contract_rejects_invalid_updates_without_fake_success() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let valid = ai_config(path_string(repo.path()));

    assert!(matches!(
        update_ai_config(String::new(), valid.clone()),
        Err(CoreError::Config { .. })
    ));

    let mut mismatched = valid.clone();
    mismatched.repo_path = "/tmp/other".to_owned();
    assert!(matches!(
        update_ai_config(path_string(repo.path()), mismatched),
        Err(CoreError::Config { .. })
    ));

    let mut missing_feature = valid.clone();
    missing_feature.feature_toggles.pop();
    assert!(matches!(
        update_ai_config(path_string(repo.path()), missing_feature),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        update_ai_config(path_string(repo.path()), valid),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn ai_settings_config_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C3-01 ai-settings-config",
        "- S3-01 ai-settings",
        "- S3-09 ai-privacy-rules",
        "计划新增：`load_ai_config`、`update_ai_config`",
        "AI enabled、provider preference、本地/远程开关、隐私策略引用。",
        "当前 AI 配置和可用能力。",
        "AI 默认关闭。",
        "配置变更可持久化且不会自动触发远程调用。",
        "key 只允许平台安全存储，不进入日志或诊断。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-01 | ai-settings | C3-01 | AI config read/write | ai_config",
        "| S3-09 | ai-privacy-rules | C3-01, C3-03, C3-09 | privacy rule CRUD/evaluate",
        "AI 默认关闭，本地优先。",
        "远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "AiConfigSnapshot load_ai_config(string repo_path);",
        "AiConfigSnapshot update_ai_config(string repo_path, AiConfig new_config);",
        "dictionary AiConfig",
        "boolean ai_enabled;",
        "AiProviderPreference provider_preference;",
        "boolean local_ai_enabled;",
        "boolean remote_ai_allowed;",
        "boolean privacy_gate_enabled;",
        "string? privacy_policy_ref;",
        "sequence<AiFeatureConfig> feature_toggles;",
        "dictionary AiConfigSnapshot",
        "sequence<AiCapabilityState> capabilities;",
        "enum AiProviderPreference { \"LocalFirst\", \"LocalOnly\", \"RemoteFirst\" };",
        "enum AiFeatureKind",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `load_ai_config(repo)` | ai | √ | Config / PermissionDenied / Io |",
        "| `update_ai_config(repo, cfg)` | ai | √ | Config / PermissionDenied / Io |",
        "C3-01 的 AI settings 读取入口",
        "C3-01 的 AI settings 更新入口",
        "不得传入或返回 API key",
        "不测试远程 provider、不启用远程 provider",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Io"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(CORE_API, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}

#[test]
fn ai_settings_config_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "显示 AI 总开关。",
        "分功能开关：分类建议、摘要、自动标签、语义搜索。",
        "远程 AI 不能通过本页普通 toggle 直接开启。",
        "Pause all AI 立即阻止后续调用，不删除已有结果。",
        "Clear AI generated suggestions 只清理未采纳建议和草稿摘要",
    ] {
        assert_contains(AI_SETTINGS_PAGE, fragment);
    }

    for fragment in [
        "privacy_gate_enabled",
        "provider_configured",
        "provider_verified",
        "remote_provider_enabled",
        "feature_scope",
        "本页关闭 `privacy_gate_enabled` 只阻止远程调用",
    ] {
        assert_contains(AI_PRIVACY_PAGE, fragment);
    }

    for fragment in [
        "AI 默认关闭；本地模型为默认推荐路径。",
        "API key 只允许存入 Keychain",
        "自动摘要、自动标签、AI 分类结果在用户确认前都是建议或草稿",
    ] {
        assert_contains(STAGE_3_INDEX, fragment);
    }

    assert_contains(AI_SETTINGS_RS, "C3-01 AI settings contract types");
    for fragment in [
        "This contract accepts only settings metadata.",
        "API keys",
        "provider connection",
        "privacy rule CRUD/evaluation",
        "actual model execution remain owned",
    ] {
        assert_contains(API_RS, fragment);
    }
    for fragment in [
        "load_ai_config_record",
        "update_ai_config_record",
        "AI config requires initialized repository metadata",
    ] {
        assert_contains(AI_SETTINGS_RS, fragment);
    }
}
