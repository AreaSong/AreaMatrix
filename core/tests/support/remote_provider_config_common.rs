#![allow(dead_code)]

use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Mutex, MutexGuard},
};

use area_matrix_core::{
    init_repo, AiFeatureKind, OverviewOutput, RemoteAiProviderKind, RemoteProviderEnableRequest,
    RemoteProviderTestRequest, RepoInitMode, RepoInitOptions,
};
use rusqlite::{params, Connection, OptionalExtension};

pub const TEST_SECRET_ENV: &str = "AREAMATRIX_REMOTE_PROVIDER_TEST_KEY";
pub const SECRET_VALUE: &str = "test-provider-secret";
static PROBE_RUNTIME_LOCK: Mutex<()> = Mutex::new(());

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
    repo
}

pub fn test_request() -> RemoteProviderTestRequest {
    test_request_for_endpoint("https://provider.example.test/probe")
}

pub fn test_request_for_endpoint(endpoint_url: &str) -> RemoteProviderTestRequest {
    test_request_with_key_reference(endpoint_url, test_key_reference())
}

pub fn test_request_with_key_reference(
    endpoint_url: &str,
    key_reference: String,
) -> RemoteProviderTestRequest {
    RemoteProviderTestRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some(endpoint_url.to_owned()),
        key_reference,
    }
}

pub fn enable_request(verification_token: String) -> RemoteProviderEnableRequest {
    enable_request_for_endpoint(verification_token, "https://provider.example.test/probe")
}

pub fn enable_request_for_endpoint(
    verification_token: String,
    endpoint_url: &str,
) -> RemoteProviderEnableRequest {
    enable_request_with_key_reference(verification_token, endpoint_url, test_key_reference())
}

pub fn enable_request_with_key_reference(
    verification_token: String,
    endpoint_url: &str,
    key_reference: String,
) -> RemoteProviderEnableRequest {
    RemoteProviderEnableRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some(endpoint_url.to_owned()),
        key_reference,
        feature_scope: vec![AiFeatureKind::AutoSummaries, AiFeatureKind::AutoTags],
        verification_token,
        data_flow_confirmed: true,
    }
}

pub fn test_key_reference() -> String {
    std::env::set_var(TEST_SECRET_ENV, SECRET_VALUE);
    format!("secure-storage:env:{TEST_SECRET_ENV}")
}

pub fn keychain_reference() -> String {
    "keychain:areamatrix-remote-openai".to_owned()
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

pub fn repo_config_rows(repo: &Path) -> Vec<(String, String)> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    let mut statement = connection
        .prepare("SELECT key, value FROM repo_config ORDER BY key")
        .expect("prepare repo_config query");
    let rows = statement
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .expect("query repo_config rows");

    rows.map(|row| row.expect("read repo_config row")).collect()
}

pub struct ProbeRuntime {
    _lock: MutexGuard<'static, ()>,
    output: tempfile::TempDir,
    payload_path: PathBuf,
}

impl ProbeRuntime {
    pub fn new(output_status: impl ToString) -> Self {
        let lock = PROBE_RUNTIME_LOCK
            .lock()
            .expect("lock remote provider probe runtime env");
        let output = tempfile::tempdir().expect("create probe runtime directory");
        let script_path = output.path().join("probe-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let script = format!(
            "#!/bin/sh\ncat > \"{}\"\nprintf '{}\\n'\n",
            payload_path.display(),
            output_status.to_string()
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
