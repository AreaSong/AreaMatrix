use std::{
    fs,
    path::Path,
    sync::{Mutex, MutexGuard},
};

use area_matrix_core::{
    enable_remote_ai_provider, init_repo, test_remote_ai_provider, AiFeatureKind, CoreError,
    OverviewOutput, RemoteAiProviderKind, RemoteProviderEnableRequest, RemoteProviderTestRequest,
    RemoteProviderTestStatus, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection, OptionalExtension};

const TEST_SECRET_ENV: &str = "AREAMATRIX_REMOTE_PROVIDER_TEST_KEY";
static PROBE_RUNTIME_LOCK: Mutex<()> = Mutex::new(());

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn test_request() -> RemoteProviderTestRequest {
    test_request_for_endpoint("https://provider.example.test/probe")
}

fn test_request_for_endpoint(endpoint_url: &str) -> RemoteProviderTestRequest {
    RemoteProviderTestRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some(endpoint_url.to_owned()),
        key_reference: test_key_reference(),
    }
}

fn enable_request(verification_token: String) -> RemoteProviderEnableRequest {
    enable_request_for_endpoint(verification_token, "https://provider.example.test/probe")
}

fn enable_request_for_endpoint(
    verification_token: String,
    endpoint_url: &str,
) -> RemoteProviderEnableRequest {
    RemoteProviderEnableRequest {
        provider: RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some(endpoint_url.to_owned()),
        key_reference: test_key_reference(),
        feature_scope: vec![AiFeatureKind::AutoSummaries, AiFeatureKind::AutoTags],
        verification_token,
        data_flow_confirmed: true,
    }
}

fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
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

fn repo_config_rows(repo: &Path) -> Vec<(String, String)> {
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

#[test]
fn remote_provider_config_implementation_tests_then_enables_persisted_snapshot() {
    let repo = initialized_repo();
    let runtime = ProbeRuntime::new(200);
    let endpoint_url = "https://provider.example.test/probe";
    let request = test_request_for_endpoint(&endpoint_url);
    let expected_key_reference = request.key_reference.clone();
    let test_result =
        test_remote_ai_provider(path_string(repo.path()), request).expect("test provider");
    let verification_token = test_result
        .verification_token
        .clone()
        .expect("successful test returns verification token");
    let captured_request = runtime.captured_payload();

    assert_eq!(test_result.status, RemoteProviderTestStatus::Succeeded);
    assert!(test_result.provider_verified);
    assert_eq!(
        test_result.sanitized_message,
        "Remote provider metadata verified"
    );
    assert!(!verification_token.contains("keychain"));
    assert!(captured_request.contains("\"url\":\"https://provider.example.test/probe?model_id=gpt-4.1-mini&probe=provider_metadata\""));
    assert!(captured_request.contains("\"name\":\"Authorization\""));
    assert!(captured_request.contains("\"value\":\"Bearer test-provider-secret\""));
    assert!(!captured_request.contains("README"));
    assert!(!captured_request.contains("AREAMATRIX"));
    assert!(!captured_request.contains("note"));

    let snapshot = enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request_for_endpoint(verification_token.clone(), &endpoint_url),
    )
    .expect("enable tested provider");

    assert!(snapshot.provider_configured);
    assert!(snapshot.provider_verified);
    assert!(snapshot.remote_provider_enabled);
    assert!(snapshot.credential_configured);
    assert_eq!(snapshot.provider, Some(RemoteAiProviderKind::Other));
    assert_eq!(snapshot.model_id.as_deref(), Some("gpt-4.1-mini"));
    assert_eq!(snapshot.endpoint_url.as_deref(), Some(endpoint_url));
    assert_eq!(
        snapshot.feature_scope,
        vec![AiFeatureKind::AutoSummaries, AiFeatureKind::AutoTags]
    );
    assert!(snapshot.updated_at.is_some());
    assert_eq!(snapshot.disabled_reason, None);

    let stored = repo_config_value(repo.path(), "remote_provider_config")
        .expect("remote provider config persisted");
    assert!(stored.contains("gpt-4.1-mini"));
    assert!(stored.contains(&expected_key_reference));
    assert!(!stored.contains(&verification_token));
    assert!(!stored.contains("test-provider-secret"));
    assert!(repo_config_value(repo.path(), "remote_provider_pending_verification").is_none());
}

#[test]
fn remote_provider_config_implementation_requires_matching_successful_test() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());

    let without_test = enable_remote_ai_provider(
        repo_path.clone(),
        enable_request("verify:remote-provider:not-tested".to_owned()),
    );
    assert!(matches!(without_test, Err(CoreError::Config { .. })));
    assert!(repo_config_value(repo.path(), "remote_provider_config").is_none());

    let runtime = ProbeRuntime::new(200);
    let endpoint_url = "https://provider.example.test/probe";
    let test_result =
        test_remote_ai_provider(repo_path.clone(), test_request_for_endpoint(&endpoint_url))
            .expect("test provider before enable");
    let _ = runtime.captured_payload();
    let mut changed_model = enable_request(
        test_result
            .verification_token
            .expect("successful test returns verification token"),
    );
    changed_model.model_id = "gpt-4.1".to_owned();

    let result = enable_remote_ai_provider(repo_path, changed_model);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert!(repo_config_value(repo.path(), "remote_provider_config").is_none());
}

#[test]
fn remote_provider_config_implementation_rejects_secret_like_key_without_partial_write() {
    let repo = initialized_repo();
    let before_rows = repo_config_rows(repo.path());
    let mut request = test_request();
    request.key_reference = "sk-secret-key-material".to_owned();

    let result = test_remote_ai_provider(path_string(repo.path()), request);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(repo_config_rows(repo.path()), before_rows);

    let mut hidden_secret = test_request();
    hidden_secret.key_reference = "keychain:sk-secret-key-material".to_owned();
    let result = test_remote_ai_provider(path_string(repo.path()), hidden_secret);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(repo_config_rows(repo.path()), before_rows);

    let mut plain_reference = test_request();
    plain_reference.key_reference = "remote-openai".to_owned();
    let result = test_remote_ai_provider(path_string(repo.path()), plain_reference);

    assert!(matches!(result, Err(CoreError::Config { .. })));
    assert_eq!(repo_config_rows(repo.path()), before_rows);
}

#[test]
fn remote_provider_config_implementation_maps_provider_test_failures_without_verification() {
    let repo = initialized_repo();
    let before_rows = repo_config_rows(repo.path());

    let rejected_runtime = ProbeRuntime::new(401);
    let rejected = test_request_for_endpoint("https://provider.example.test/rejected");
    assert_unverified_test_status(
        repo.path(),
        rejected,
        RemoteProviderTestStatus::ProviderRejected,
    );
    let _ = rejected_runtime.captured_payload();

    let connection_failed_runtime = ProbeRuntime::new(503);
    let connection_failed = test_request_for_endpoint("https://provider.example.test/unavailable");
    assert_unverified_test_status(
        repo.path(),
        connection_failed,
        RemoteProviderTestStatus::ConnectionFailed,
    );
    let _ = connection_failed_runtime.captured_payload();

    let unsupported_runtime = ProbeRuntime::new(404);
    let unsupported = test_request_for_endpoint("https://provider.example.test/unsupported");
    assert_unverified_test_status(
        repo.path(),
        unsupported,
        RemoteProviderTestStatus::UnsupportedProvider,
    );
    let _ = unsupported_runtime.captured_payload();

    assert_eq!(repo_config_rows(repo.path()), before_rows);
}

#[test]
fn remote_provider_config_implementation_maps_credential_inspection_denied() {
    let repo = initialized_repo();
    let before_rows = repo_config_rows(repo.path());
    let mut request = test_request();
    request.key_reference = "keychain:areamatrix-remote-openai".to_owned();

    let result = test_remote_ai_provider(path_string(repo.path()), request);

    assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
    assert_eq!(repo_config_rows(repo.path()), before_rows);
}

#[test]
fn remote_provider_config_implementation_rolls_back_when_enable_write_fails() {
    let repo = initialized_repo();
    let repo_path = path_string(repo.path());
    let runtime = ProbeRuntime::new(200);
    let endpoint_url = "https://provider.example.test/probe";
    let test_result =
        test_remote_ai_provider(repo_path.clone(), test_request_for_endpoint(&endpoint_url))
            .expect("test provider");
    let _ = runtime.captured_payload();
    let pending_before = repo_config_value(repo.path(), "remote_provider_pending_verification")
        .expect("pending verification persisted");
    let connection =
        Connection::open(repo.path().join(".areamatrix/index.db")).expect("open database");
    connection
        .execute_batch(
            "CREATE TRIGGER fail_remote_provider_config_insert
             BEFORE INSERT ON repo_config
             WHEN NEW.key = 'remote_provider_config'
             BEGIN
               SELECT RAISE(ABORT, 'forced remote provider config write failure');
             END;",
        )
        .expect("install failing remote provider trigger");
    drop(connection);

    let result = enable_remote_ai_provider(
        repo_path,
        enable_request_for_endpoint(
            test_result
                .verification_token
                .expect("successful test returns verification token"),
            &endpoint_url,
        ),
    );

    assert!(matches!(result, Err(CoreError::Internal { .. })));
    assert!(repo_config_value(repo.path(), "remote_provider_config").is_none());
    assert_eq!(
        repo_config_value(repo.path(), "remote_provider_pending_verification"),
        Some(pending_before)
    );
}

#[test]
fn remote_provider_config_implementation_preserves_user_files_and_ai_boundaries() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    let overview_path = repo.path().join("AREAMATRIX.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&overview_path, "user overview\n").expect("write user overview");

    let runtime = ProbeRuntime::new(200);
    let endpoint_url = "https://provider.example.test/probe";
    let test_result = test_remote_ai_provider(
        path_string(repo.path()),
        test_request_for_endpoint(&endpoint_url),
    )
    .expect("test remote provider");
    let captured_request = runtime.captured_payload();
    assert!(!captured_request.contains("user readme"));
    assert!(!captured_request.contains("user overview"));
    enable_remote_ai_provider(
        path_string(repo.path()),
        enable_request_for_endpoint(
            test_result
                .verification_token
                .expect("successful test returns verification token"),
            &endpoint_url,
        ),
    )
    .expect("enable remote provider");

    assert_eq!(
        fs::read_to_string(&readme_path).expect("read README"),
        "user readme\n"
    );
    assert_eq!(
        fs::read_to_string(&overview_path).expect("read AREAMATRIX"),
        "user overview\n"
    );
    for path in [
        repo.path().join(".areamatrix/secrets"),
        repo.path().join(".areamatrix/ai_call_log"),
        repo.path()
            .join(".areamatrix/generated/remote_provider.json"),
    ] {
        assert!(!path.exists(), "C3-03 must not create {}", path.display());
    }
}

fn assert_unverified_test_status(
    repo: &Path,
    request: RemoteProviderTestRequest,
    expected_status: RemoteProviderTestStatus,
) {
    let result =
        test_remote_ai_provider(path_string(repo), request).expect("test provider returns status");

    assert_eq!(result.status, expected_status);
    assert!(!result.provider_verified);
    assert!(result.verification_token.is_none());
    assert!(!result.sanitized_message.contains("keychain"));
    assert!(repo_config_value(repo, "remote_provider_pending_verification").is_none());
}

fn test_key_reference() -> String {
    std::env::set_var(TEST_SECRET_ENV, "test-provider-secret");
    format!("secure-storage:env:{TEST_SECRET_ENV}")
}

struct ProbeRuntime {
    _lock: MutexGuard<'static, ()>,
    output: tempfile::TempDir,
    payload_path: std::path::PathBuf,
}

impl ProbeRuntime {
    fn new(status_code: u16) -> Self {
        let lock = PROBE_RUNTIME_LOCK
            .lock()
            .expect("lock remote provider probe runtime env");
        let output = tempfile::tempdir().expect("create probe runtime directory");
        let script_path = output.path().join("probe-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let script = format!(
            "#!/bin/sh\ncat > \"{}\"\nprintf '{}\\n'\n",
            payload_path.display(),
            status_code
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

    fn captured_payload(self) -> String {
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
