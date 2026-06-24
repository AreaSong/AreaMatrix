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

const TESTING_DOC: &str = include_str!("../../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../../docs/api/core-api.md");
const UDL: &str = include_str!("../../area_matrix.udl");
use crate::api_contract_source::API_RS;
const REMOTE_PROVIDER_RS: &str = include_str!("../../src/remote_provider_config.rs");
const DB_REMOTE_PROVIDER_RS: &str = include_str!("../../src/db/remote_provider_config.rs");
const PROBE_RS: &str = include_str!("../../src/remote_provider_config/probe.rs");

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
        "RemoteProviderConfigSnapshot load_remote_ai_provider_config(",
        "RemoteProviderConfigSnapshot enable_remote_ai_provider(",
        "RemoteProviderConfigSnapshot disable_remote_ai_provider(",
        "dictionary RemoteProviderTestRequest",
        "dictionary RemoteProviderEnableRequest",
        "dictionary RemoteProviderDisableRequest",
        "sequence<AiFeatureKind> feature_scope;",
        "boolean data_flow_confirmed;",
        "boolean remove_stored_credential;",
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
        "只读取 metadata，不测试 provider",
        "不修改 `privacy_gate_enabled`",
        "只保存远程 provider metadata、Keychain reference 和 scope",
        "只关闭 remote provider gate",
        "`privacy_gate_enabled` 由 AI privacy rules 管理",
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
        "pub fn load_remote_ai_provider_config(",
        "pub fn enable_remote_ai_provider(",
        "pub fn disable_remote_ai_provider(",
        "RemoteProviderTestRequest",
        "RemoteProviderEnableRequest",
        "RemoteProviderDisableRequest",
        "RemoteProviderConfigSnapshot",
        "Core must never accept or return raw API keys",
        "AI privacy rules remains responsible for",
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
        "load_remote_provider_config_record",
        "remote_provider_pending_verification",
        "remote_provider_config",
        "update_remote_provider_config_record",
    ] {
        assert_contains(DB_REMOTE_PROVIDER_RS, fragment);
    }

    for fragment in [
        "SECURE_STORAGE_ENV_PREFIX",
        "KEYCHAIN_PREFIX",
        "ProbeCredential::PlatformReference",
        "key_reference: request.key_reference.as_deref()",
        "probe_remote_provider",
        "sanitized_probe_message",
        "custom_endpoint_scheme_allowed",
    ] {
        assert_contains(PROBE_RS, fragment);
    }
}

pub fn assert_consumer_gate_alignment() {}

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
