use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Mutex, MutexGuard},
};

use area_matrix_core::{
    init_repo, AiFeatureKind, CoreError, ErrorKind, OverviewOutput, RemoteAiProviderKind,
    RemoteProviderEnableRequest, RemoteProviderTestRequest, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection, OptionalExtension};

const CAPABILITY_SPEC: &str =
    include_str!("../../../docs/core/capability-specs/stage-3-ai/C3-03-remote-provider-config.md");
const CONTROL_MAP: &str = include_str!("../../../docs/architecture/stage-3-control-map.md");
const TESTING_DOC: &str = include_str!("../../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../../docs/api/core-api.md");
const UDL: &str = include_str!("../../area_matrix.udl");
const API_RS: &str = include_str!("../../src/api.rs");
const REMOTE_PROVIDER_RS: &str = include_str!("../../src/remote_provider_config.rs");
const DB_REMOTE_PROVIDER_RS: &str = include_str!("../../src/db/remote_provider_config.rs");
const PROBE_RS: &str = include_str!("../../src/remote_provider_config/probe.rs");
const REMOTE_MODEL_PAGE: &str =
    include_str!("../../../docs/ux/page-specs/stage-3-ai/S3-03-remote-model-enable.md");
const PRIVACY_PAGE: &str =
    include_str!("../../../docs/ux/page-specs/stage-3-ai/S3-09-ai-privacy-rules.md");

const TEST_SECRET_ENV: &str = "AREAMATRIX_REMOTE_PROVIDER_VALIDATION_KEY";
const SECRET_VALUE: &str = "validation-provider-secret";
pub const REMOTE_CONFIG_KEY: &str = "remote_provider_config";
pub const PENDING_TEST_KEY: &str = "remote_provider_pending_verification";
static PROBE_RUNTIME_LOCK: Mutex<()> = Mutex::new(());

#[derive(Debug, Eq, PartialEq)]
pub struct RepoSnapshot {
    pub user_readme: String,
    pub user_overview: String,
    pub forbidden_remote_paths: Vec<String>,
}

pub fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub fn initialized_repo() -> tempfile::TempDir {
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
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
    fs::write(repo.path().join("AREAMATRIX.md"), "user overview\n").expect("write user AREAMATRIX");
    repo
}

pub fn test_key_reference() -> String {
    format!("secure-storage:env:{TEST_SECRET_ENV}")
}

pub fn test_request(endpoint_url: &str) -> RemoteProviderTestRequest {
    RemoteProviderTestRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some(endpoint_url.to_owned()),
        key_reference: test_key_reference(),
    }
}

pub fn enable_request(
    verification_token: String,
    endpoint_url: &str,
) -> RemoteProviderEnableRequest {
    RemoteProviderEnableRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some(endpoint_url.to_owned()),
        key_reference: test_key_reference(),
        feature_scope: vec![
            AiFeatureKind::ClassificationSuggestions,
            AiFeatureKind::AutoSummaries,
            AiFeatureKind::AutoTags,
            AiFeatureKind::SemanticSearch,
        ],
        verification_token,
        data_flow_confirmed: true,
    }
}

pub fn repo_snapshot(repo: &Path) -> RepoSnapshot {
    RepoSnapshot {
        user_readme: fs::read_to_string(repo.join("README.md")).expect("read user README"),
        user_overview: fs::read_to_string(repo.join("AREAMATRIX.md"))
            .expect("read user AREAMATRIX"),
        forbidden_remote_paths: forbidden_remote_paths(repo),
    }
}

pub fn repo_config_rows(repo: &Path) -> Vec<(String, String, i64)> {
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

pub fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .optional()
        .expect("query repo_config value")
}

pub fn assert_no_api_key_material(value: &str) {
    for fragment in [SECRET_VALUE, "Bearer", "sk-secret", "api_key=", "apikey="] {
        assert!(
            !value.contains(fragment),
            "unexpected API key fragment `{fragment}` in `{value}`"
        );
    }
}

pub fn assert_sanitized_error(error: CoreError, expected_kind: ErrorKind) {
    let text = error.to_string();
    let raw_context = error.raw_context().to_owned();
    let mapping = error.to_error_mapping();

    assert_eq!(error.kind(), expected_kind);
    assert_eq!(mapping.kind, expected_kind);
    assert_no_api_key_material(&text);
    assert_no_api_key_material(&raw_context);
    assert_no_api_key_material(&mapping.raw_context);
    assert_no_api_key_material(&mapping.user_message);
}

pub fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

pub fn assert_not_contains(haystack: &str, needle: &str) {
    assert!(
        !haystack.contains(needle),
        "expected text not to contain `{needle}`"
    );
}

pub fn assert_validation_docs_alignment() {
    for fragment in [
        "计划新增：`test_remote_ai_provider`、`enable_remote_ai_provider`",
        "provider_configured",
        "provider_verified",
        "remote_provider_enabled",
        "feature_scope",
        "保存 provider metadata 和 scope，不保存 key 明文。",
        "API key 不进入日志、诊断、错误文案。",
        "本地模型失败不得自动启用远程 provider。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S3-03 | remote-model-enable | C3-03, C3-09 | provider test/enable | provider metadata, Keychain ref",
        "| S3-09 | ai-privacy-rules | C3-01, C3-03, C3-09 | privacy rule CRUD/evaluate",
        "远程调用必须显式启用，且 API key 不进入日志、诊断或错误文案。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "集成测试目录",
        "测试断言 `assert!(true)` 类废话",
        "测试间共享全局状态",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }
}

pub fn assert_core_api_and_udl_alignment() {
    for fragment in [
        "RemoteProviderTestResult test_remote_ai_provider(",
        "RemoteProviderConfigSnapshot enable_remote_ai_provider(",
        "dictionary RemoteProviderTestRequest",
        "dictionary RemoteProviderEnableRequest",
        "sequence<AiFeatureKind> feature_scope;",
        "boolean data_flow_confirmed;",
        "dictionary RemoteProviderConfigSnapshot",
        "boolean provider_configured;",
        "boolean provider_verified;",
        "boolean remote_provider_enabled;",
        "boolean credential_configured;",
        "dictionary RemoteProviderTestResult",
        "RemoteProviderTestStatus status;",
        "string? verification_token;",
        "enum RemoteAiProviderKind",
        "\"OpenAi\", \"Anthropic\", \"Other\"",
        "enum RemoteProviderTestStatus",
        "\"Succeeded\", \"ProviderRejected\", \"ConnectionFailed\", \"UnsupportedProvider\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "不接受 API key 明文",
        "不得发送文件名、repo-relative path、提取文本",
        "不修改 `privacy_gate_enabled`",
        "只保存远程 provider metadata、Keychain reference 和 scope",
        "`privacy_gate_enabled` 由 C3-09 管理",
        "任一失败必须保留上一次成功的 remote provider state",
    ] {
        assert_contains(CORE_API, fragment);
    }

    let snapshot_udl = section_between(
        UDL,
        "dictionary RemoteProviderConfigSnapshot {",
        "dictionary RemoteProviderTestResult {",
    );
    assert_not_contains(snapshot_udl, "privacy_gate_enabled");
}

pub fn assert_rust_contract_alignment() {
    for fragment in [
        "pub fn test_remote_ai_provider(",
        "pub fn enable_remote_ai_provider(",
        "RemoteProviderTestRequest",
        "RemoteProviderEnableRequest",
        "RemoteProviderConfigSnapshot",
        "Core must never accept or return raw API keys",
        "C3-09 remains responsible for",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "validate_feature_scope",
        "validate_verification_token",
        "looks_sensitive",
        "RemoteProviderTestStatus",
        "remote provider data flow consent is required",
        "remote provider verification token is invalid",
    ] {
        assert_contains(REMOTE_PROVIDER_RS, fragment);
    }

    for fragment in [
        "remote_provider_pending_verification",
        "remote_provider_config",
        "update_remote_provider_config_record",
    ] {
        assert_contains(DB_REMOTE_PROVIDER_RS, fragment);
    }

    for fragment in [
        "SECURE_STORAGE_ENV_PREFIX",
        "probe_remote_provider",
        "sanitized_probe_message",
        "custom_endpoint_scheme_allowed",
    ] {
        assert_contains(PROBE_RS, fragment);
    }
}

pub fn assert_consumer_gate_alignment() {
    for fragment in [
        "`provider_configured`：provider、model 或 endpoint 已保存。",
        "`provider_verified`：当前 provider/model/endpoint/key 组合的 Test connection 成功",
        "`remote_provider_enabled`：用户在本页显式点击 `Enable remote AI` 后为 true",
        "`feature_scope`：本页保存的远程可用功能范围",
        "`privacy_gate_enabled`：由 S3-09 管理的远程隐私 gate",
        "Test connection 只发送 provider/model/key 可用性的最小探测请求",
        "API key 不出现在日志、诊断包、UI 明文和错误文本中。",
    ] {
        assert_contains(REMOTE_MODEL_PAGE, fragment);
    }

    for fragment in [
        "本区是隐私 gate，不是 provider 禁用页",
        "`provider_configured`、`provider_verified`、`remote_provider_enabled` 和 `feature_scope` 来自 S3-03，只读展示。",
        "本页的 `Block remote AI with privacy gate` 不得被实现为 S3-03 的 `Disable remote AI`",
        "如果 `feature_scope` 不包含某 AI 功能",
    ] {
        assert_contains(PRIVACY_PAGE, fragment);
    }
}

fn forbidden_remote_paths(repo: &Path) -> Vec<String> {
    [
        repo.join(".areamatrix/remote"),
        repo.join(".areamatrix/secrets"),
        repo.join(".areamatrix/ai_call_log"),
        repo.join(".areamatrix/generated/remote_provider.json"),
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

fn section_between<'a>(haystack: &'a str, start: &str, end: &str) -> &'a str {
    let start_index = haystack.find(start).expect("section start exists");
    let after_start = &haystack[start_index..];
    let end_index = after_start.find(end).expect("section end exists");
    &after_start[..end_index]
}

pub struct ProbeRuntime {
    _lock: MutexGuard<'static, ()>,
    output: tempfile::TempDir,
    payload_path: PathBuf,
}

impl ProbeRuntime {
    pub fn new(output_status: &str) -> Self {
        let lock = PROBE_RUNTIME_LOCK
            .lock()
            .expect("lock remote provider probe runtime env");
        std::env::set_var(TEST_SECRET_ENV, SECRET_VALUE);

        let output = tempfile::tempdir().expect("create probe runtime directory");
        let script_path = output.path().join("probe-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let script = format!(
            "#!/bin/sh\ncat > \"{}\"\nprintf '{}\\n'\n",
            payload_path.display(),
            output_status
        );
        fs::write(&script_path, script).expect("write probe runtime script");
        make_executable(&script_path);
        std::env::set_var(
            "AREAMATRIX_REMOTE_PROVIDER_PROBE_RUNTIME",
            script_path.to_string_lossy().into_owned(),
        );

        Self {
            _lock: lock,
            output,
            payload_path,
        }
    }

    pub fn captured_payload(self) -> String {
        fs::read_to_string(&self.payload_path).expect("read captured probe payload")
    }
}

impl Drop for ProbeRuntime {
    fn drop(&mut self) {
        std::env::remove_var("AREAMATRIX_REMOTE_PROVIDER_PROBE_RUNTIME");
        std::env::remove_var(TEST_SECRET_ENV);
        let _ = self.output.path();
    }
}

fn make_executable(path: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(path)
            .expect("read probe runtime metadata")
            .permissions();
        permissions.set_mode(0o700);
        fs::set_permissions(path, permissions).expect("mark probe runtime executable");
    }
}
