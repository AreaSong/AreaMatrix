#![allow(dead_code)]

use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Mutex, MutexGuard},
};

use area_matrix_core::{
    enable_remote_ai_provider, import_file, init_repo, test_remote_ai_provider, update_ai_config,
    AiFeatureConfig, AiFeatureKind, AiProviderPreference, DuplicateStrategy, ImportDestination,
    ImportOptions, OverviewOutput, RemoteProviderEnableRequest, RemoteProviderTestRequest,
    RepoInitMode, RepoInitOptions, StorageMode,
};
use rusqlite::Connection;

static LOCAL_RUNTIME_LOCK: Mutex<()> = Mutex::new(());
static REMOTE_RUNTIME_LOCK: Mutex<()> = Mutex::new(());
static PROVIDER_PROBE_LOCK: Mutex<()> = Mutex::new(());

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

pub fn import_fixture(repo: &Path, name: &str, content: &str) -> i64 {
    let source_dir = repo.join("fixtures");
    fs::create_dir_all(&source_dir).expect("create fixture source directory");
    let source = source_dir.join(name);
    fs::write(&source, content).expect("write fixture source");
    import_file(path_string(repo), path_string(&source), import_options())
        .expect("import fixture file")
        .id
}

pub fn enable_local_summaries(repo: &Path) {
    let repo_path = path_string(repo);
    update_ai_config(repo_path.clone(), ai_config(repo_path, true, false, false))
        .expect("enable local AI summaries");
}

pub fn enable_remote_summaries(repo: &Path, endpoint_url: &str) {
    let repo_path = path_string(repo);
    update_ai_config(
        repo_path.clone(),
        ai_config(repo_path.clone(), true, true, true),
    )
    .expect("enable remote AI summaries setting");
    let _probe = ProviderProbeRuntime::new(200);
    let test_result = test_remote_ai_provider(repo_path.clone(), test_request(endpoint_url))
        .expect("test provider");
    let token = test_result
        .verification_token
        .expect("successful test returns token");
    enable_remote_ai_provider(repo_path, enable_request(token, endpoint_url))
        .expect("enable remote summaries provider");
}

pub fn ai_summary_row(repo: &Path, file_id: i64) -> Option<String> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .query_row(
            "SELECT summary_text FROM ai_summaries WHERE file_id = ?1",
            [file_id],
            |row| row.get(0),
        )
        .ok()
}

pub fn ai_call_log_count(repo: &Path) -> i64 {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .query_row("SELECT COUNT(*) FROM ai_call_log", [], |row| row.get(0))
        .expect("count AI call logs")
}

pub fn change_log_kinds(repo: &Path) -> Vec<String> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    let mut statement = connection
        .prepare("SELECT detail_json FROM change_log ORDER BY id")
        .expect("prepare change log query");
    let rows = statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query change log");
    rows.map(|row| {
        let detail: serde_json::Value =
            serde_json::from_str(&row.expect("read change log detail")).expect("valid detail json");
        detail["kind"].as_str().unwrap_or_default().to_owned()
    })
    .collect()
}

fn import_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("docs".to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn ai_config(
    repo_path: String,
    feature_enabled: bool,
    remote_allowed: bool,
    local_enabled: bool,
) -> area_matrix_core::AiConfig {
    area_matrix_core::AiConfig {
        repo_path,
        ai_enabled: true,
        provider_preference: if remote_allowed {
            AiProviderPreference::RemoteFirst
        } else {
            AiProviderPreference::LocalFirst
        },
        local_ai_enabled: local_enabled || !remote_allowed,
        remote_ai_allowed: remote_allowed,
        privacy_gate_enabled: true,
        privacy_policy_ref: None,
        feature_toggles: vec![
            AiFeatureConfig {
                feature: AiFeatureKind::ClassificationSuggestions,
                enabled: false,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::AutoSummaries,
                enabled: feature_enabled,
                allow_remote: remote_allowed,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::AutoTags,
                enabled: false,
                allow_remote: false,
            },
            AiFeatureConfig {
                feature: AiFeatureKind::SemanticSearch,
                enabled: false,
                allow_remote: false,
            },
        ],
    }
}

fn test_request(endpoint_url: &str) -> RemoteProviderTestRequest {
    std::env::set_var("AREAMATRIX_AI_SUMMARY_TEST_KEY", "summary-provider-secret");
    RemoteProviderTestRequest {
        provider: area_matrix_core::RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some(endpoint_url.to_owned()),
        key_reference: "secure-storage:env:AREAMATRIX_AI_SUMMARY_TEST_KEY".to_owned(),
    }
}

fn enable_request(token: String, endpoint_url: &str) -> RemoteProviderEnableRequest {
    RemoteProviderEnableRequest {
        provider: area_matrix_core::RemoteAiProviderKind::Other,
        model_id: "gpt-4.1-mini".to_owned(),
        endpoint_url: Some(endpoint_url.to_owned()),
        key_reference: "secure-storage:env:AREAMATRIX_AI_SUMMARY_TEST_KEY".to_owned(),
        feature_scope: vec![AiFeatureKind::AutoSummaries],
        verification_token: token,
        data_flow_confirmed: true,
    }
}

pub struct AiSummaryRuntime {
    _lock: MutexGuard<'static, ()>,
    output: tempfile::TempDir,
    payload_path: PathBuf,
    env_name: &'static str,
}

impl AiSummaryRuntime {
    pub fn local(summary_text: &str) -> Self {
        Self::new(
            &LOCAL_RUNTIME_LOCK,
            "AREAMATRIX_AI_SUMMARY_LOCAL_RUNTIME",
            summary_text,
        )
    }

    pub fn remote(summary_text: &str) -> Self {
        Self::new(
            &REMOTE_RUNTIME_LOCK,
            "AREAMATRIX_AI_SUMMARY_REMOTE_RUNTIME",
            summary_text,
        )
    }

    pub fn failing_local() -> Self {
        Self::failing(&LOCAL_RUNTIME_LOCK, "AREAMATRIX_AI_SUMMARY_LOCAL_RUNTIME")
    }

    pub fn captured_payload(&self) -> String {
        fs::read_to_string(&self.payload_path).expect("read captured summary payload")
    }

    fn new(lock: &'static Mutex<()>, env_name: &'static str, summary_text: &str) -> Self {
        let guard = lock.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let output = tempfile::tempdir().expect("create summary runtime directory");
        let script_path = output.path().join("ai-summary-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let response = serde_json::json!({ "summary_text": summary_text }).to_string();
        let script = format!(
            "#!/bin/sh\ncat > \"{}\"\nprintf '%s\\n' '{}'\n",
            payload_path.display(),
            response.replace('\'', "'\\''")
        );
        fs::write(&script_path, script).expect("write summary runtime script");
        make_executable(&script_path);
        std::env::set_var(env_name, script_path.to_string_lossy().into_owned());
        Self {
            _lock: guard,
            output,
            payload_path,
            env_name,
        }
    }

    fn failing(lock: &'static Mutex<()>, env_name: &'static str) -> Self {
        let guard = lock.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let output = tempfile::tempdir().expect("create failing summary runtime directory");
        let script_path = output.path().join("ai-summary-runtime.sh");
        let payload_path = output.path().join("payload.json");
        let script = format!("#!/bin/sh\ncat > \"{}\"\nexit 42\n", payload_path.display());
        fs::write(&script_path, script).expect("write failing summary runtime script");
        make_executable(&script_path);
        std::env::set_var(env_name, script_path.to_string_lossy().into_owned());
        Self {
            _lock: guard,
            output,
            payload_path,
            env_name,
        }
    }
}

impl Drop for AiSummaryRuntime {
    fn drop(&mut self) {
        std::env::remove_var(self.env_name);
        let _ = self.output.path();
    }
}

struct ProviderProbeRuntime {
    _lock: MutexGuard<'static, ()>,
    output: tempfile::TempDir,
}

impl ProviderProbeRuntime {
    fn new(output_status: impl ToString) -> Self {
        let guard = PROVIDER_PROBE_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let output = tempfile::tempdir().expect("create provider probe runtime directory");
        let script_path = output.path().join("probe-runtime.sh");
        let script = format!(
            "#!/bin/sh\ncat >/dev/null\nprintf '{}\\n'\n",
            output_status.to_string()
        );
        fs::write(&script_path, script).expect("write probe runtime script");
        make_executable(&script_path);
        std::env::set_var(
            "AREAMATRIX_REMOTE_PROVIDER_PROBE_RUNTIME",
            script_path.to_string_lossy().into_owned(),
        );
        Self {
            _lock: guard,
            output,
        }
    }
}

impl Drop for ProviderProbeRuntime {
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
            .expect("read script metadata")
            .permissions();
        permissions.set_mode(0o700);
        fs::set_permissions(path, permissions).expect("mark script executable");
    }
}
