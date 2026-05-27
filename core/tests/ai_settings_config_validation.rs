use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, load_ai_config, update_ai_config, AiConfig, AiConfigSnapshot, AiFeatureConfig,
    AiFeatureKind, AiProviderPreference, CoreError, CoreResult, ErrorKind, OverviewOutput,
    RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-01-ai-settings-config.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const AI_SETTINGS_RS: &str = include_str!("../src/ai_settings.rs");
const API_RS: &str = include_str!("../src/api.rs");

#[derive(Debug, Eq, PartialEq)]
struct AiSettingsValidationSnapshot {
    repo_config_rows: Vec<(String, String, i64)>,
    user_readme: String,
    user_overview: String,
    forbidden_metadata_paths: Vec<String>,
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");
    repo
}

fn remote_ready_toggles() -> Vec<AiFeatureConfig> {
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
            enabled: true,
            allow_remote: true,
        },
    ]
}

fn remote_ready_config(repo_path: String) -> AiConfig {
    AiConfig {
        repo_path,
        ai_enabled: true,
        provider_preference: AiProviderPreference::RemoteFirst,
        local_ai_enabled: true,
        remote_ai_allowed: true,
        privacy_gate_enabled: true,
        privacy_policy_ref: Some("policy:remote-default".to_owned()),
        feature_toggles: remote_ready_toggles(),
    }
}

fn disabled_config(repo_path: String) -> AiConfig {
    AiConfig {
        repo_path,
        ai_enabled: false,
        provider_preference: AiProviderPreference::LocalOnly,
        local_ai_enabled: false,
        remote_ai_allowed: false,
        privacy_gate_enabled: false,
        privacy_policy_ref: None,
        feature_toggles: remote_ready_toggles(),
    }
}

fn repo_config_rows(repo: &Path) -> Vec<(String, String, i64)> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    let mut statement = connection
        .prepare("SELECT key, value, updated_at FROM repo_config ORDER BY key")
        .expect("prepare repo_config query");
    let rows = statement
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })
        .expect("query repo_config rows");

    rows.map(|row| row.expect("read repo_config row")).collect()
}

fn snapshot(repo: &Path) -> AiSettingsValidationSnapshot {
    AiSettingsValidationSnapshot {
        repo_config_rows: repo_config_rows(repo),
        user_readme: fs::read_to_string(repo.join("README.md")).expect("read user README"),
        user_overview: fs::read_to_string(repo.join("AREAMATRIX.md"))
            .expect("read user AREAMATRIX"),
        forbidden_metadata_paths: forbidden_metadata_paths(repo),
    }
}

fn forbidden_metadata_paths(repo: &Path) -> Vec<String> {
    [
        repo.join(".areamatrix/remote"),
        repo.join(".areamatrix/secrets"),
        repo.join(".areamatrix/ai_call_log"),
        repo.join(".areamatrix/generated/ai_config.json"),
    ]
    .into_iter()
    .filter(|path| path.exists())
    .map(|path| {
        path.strip_prefix(repo)
            .expect("forbidden path is inside repository")
            .to_string_lossy()
            .into_owned()
    })
    .collect()
}

fn capability<'a>(
    snapshot: &'a AiConfigSnapshot,
    feature: AiFeatureKind,
) -> &'a area_matrix_core::AiCapabilityState {
    snapshot
        .capabilities
        .iter()
        .find(|state| state.feature == feature)
        .expect("capability state exists")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn ai_settings_config_validation_covers_default_success_and_ui_capability_state() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    fs::write(repo.path().join("AREAMATRIX.md"), "user overview\n").expect("write user AREAMATRIX");

    let default = load_ai_config(path_string(repo.path())).expect("load default AI config");
    assert!(!default.config.ai_enabled);
    assert!(!default.config.remote_ai_allowed);
    assert!(!default.config.privacy_gate_enabled);
    assert!(default.config.privacy_policy_ref.is_none());
    assert!(default.capabilities.iter().all(|state| !state.enabled));
    assert!(default
        .capabilities
        .iter()
        .all(|state| state.disabled_reason.as_deref() == Some("AI is off")));

    let before = snapshot(repo.path());
    let repo_path = path_string(repo.path());
    let saved = update_ai_config(repo_path.clone(), remote_ready_config(repo_path.clone()))
        .expect("persist UI-ready AI config");
    let reloaded = load_ai_config(repo_path).expect("reload persisted AI config");

    assert_eq!(saved, reloaded);
    assert!(saved.config.ai_enabled);
    assert_eq!(
        saved.config.provider_preference,
        AiProviderPreference::RemoteFirst
    );
    assert!(saved.config.local_ai_enabled);
    assert!(saved.config.remote_ai_allowed);
    assert!(saved.config.privacy_gate_enabled);
    assert_eq!(
        saved.config.privacy_policy_ref.as_deref(),
        Some("policy:remote-default")
    );
    assert_eq!(saved.config.feature_toggles.len(), 4);
    assert!(saved.updated_at.is_some());

    let classification = capability(&saved, AiFeatureKind::ClassificationSuggestions);
    assert!(classification.enabled);
    assert!(classification.local_allowed);
    assert!(!classification.remote_allowed);

    let summaries = capability(&saved, AiFeatureKind::AutoSummaries);
    assert!(summaries.enabled);
    assert!(summaries.local_allowed);
    assert!(summaries.remote_allowed);

    let tags = capability(&saved, AiFeatureKind::AutoTags);
    assert!(!tags.enabled);
    assert_eq!(tags.disabled_reason.as_deref(), Some("Feature is off"));

    let after = snapshot(repo.path());
    assert_eq!(after.user_readme, before.user_readme);
    assert_eq!(after.user_overview, before.user_overview);
    assert!(after.forbidden_metadata_paths.is_empty());
}

#[test]
fn ai_settings_config_validation_covers_failure_rollback_and_secret_boundaries() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    fs::write(repo.path().join("AREAMATRIX.md"), "user overview\n").expect("write user AREAMATRIX");
    let repo_path = path_string(repo.path());

    update_ai_config(repo_path.clone(), disabled_config(repo_path.clone()))
        .expect("persist baseline AI config");
    let before = snapshot(repo.path());
    let baseline = load_ai_config(repo_path.clone()).expect("load baseline AI config");

    let mut duplicate = remote_ready_config(repo_path.clone());
    duplicate.feature_toggles.push(AiFeatureConfig {
        feature: AiFeatureKind::AutoSummaries,
        enabled: true,
        allow_remote: true,
    });
    let duplicate_error =
        update_ai_config(repo_path.clone(), duplicate).expect_err("duplicate feature fails");
    assert_eq!(duplicate_error.kind(), ErrorKind::Config);

    let mut secret = remote_ready_config(repo_path.clone());
    secret.privacy_policy_ref = Some("token=must-not-leak".to_owned());
    let secret_error =
        update_ai_config(repo_path.clone(), secret).expect_err("secret-like reference fails");
    assert_eq!(secret_error.kind(), ErrorKind::Config);
    assert!(!secret_error.raw_context().contains("must-not-leak"));

    let metadata_path = repo.path().join(".areamatrix");
    assert!(matches!(
        load_ai_config(path_string(&metadata_path)),
        Err(CoreError::Config { .. })
    ));

    assert_eq!(
        load_ai_config(repo_path).expect("reload baseline after failures"),
        baseline
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn ai_settings_config_validation_locks_core_api_udl_and_rust_contract() {
    fn assert_load_signature(_: fn(String) -> CoreResult<AiConfigSnapshot>) {}
    fn assert_update_signature(_: fn(String, AiConfig) -> CoreResult<AiConfigSnapshot>) {}

    assert_load_signature(load_ai_config);
    assert_update_signature(update_ai_config);

    for fragment in [
        "计划新增：`load_ai_config`、`update_ai_config`",
        "AI 默认关闭。",
        "配置变更可持久化且不会自动触发远程调用。",
        "key 只允许平台安全存储，不进入日志或诊断。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
    for fragment in [
        "| S3-01 | ai-settings | C3-01 | AI config read/write | ai_config",
        "| S3-09 | ai-privacy-rules | C3-01, C3-03, C3-09 | privacy rule CRUD/evaluate",
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
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
    for fragment in [
        "pub(crate) fn load_ai_config",
        "pub(crate) fn update_ai_config",
        "validate_privacy_policy_ref",
        "validate_feature_toggles",
        "remote_route_enabled",
        "AI config requires initialized repository metadata",
    ] {
        assert_contains(AI_SETTINGS_RS, fragment);
    }
    for fragment in [
        "pub fn load_ai_config",
        "pub fn update_ai_config",
        "This contract accepts only settings metadata.",
        "actual model execution remain owned",
    ] {
        assert_contains(API_RS, fragment);
    }
}
