#![allow(dead_code)]

use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Mutex, MutexGuard},
};

#[path = "ai_persisted_privacy.rs"]
pub(crate) mod ai_persisted_privacy;
#[path = "external_runtime_harness.rs"]
mod external_runtime_harness;

use ai_persisted_privacy::allow_remote_ai;
use external_runtime_harness::{install_runtime_script, InstalledRuntime};

use area_matrix_core::{
    complete_remote_ai_provider_probe, enable_remote_ai_provider, import_file, init_repo,
    prepare_remote_ai_provider_probe, update_ai_config, AiFeatureConfig, AiFeatureKind,
    AiProviderPreference, DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput,
    RemoteProviderEnableRequest, RemoteProviderProbeObservation, RemoteProviderProbeOutcome,
    RemoteProviderTestRequest, RepoInitMode, RepoInitOptions, StorageMode,
};
use rusqlite::Connection;

static LOCAL_RUNTIME_LOCK: Mutex<()> = Mutex::new(());
static REMOTE_RUNTIME_LOCK: Mutex<()> = Mutex::new(());

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
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
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
    let plan = prepare_remote_ai_provider_probe(repo_path.clone(), test_request(endpoint_url))
        .expect("prepare provider probe");
    let test_result = complete_remote_ai_provider_probe(
        repo_path.clone(),
        RemoteProviderProbeObservation {
            probe_token: plan.probe_token,
            outcome: RemoteProviderProbeOutcome::HttpResponse,
            http_status: Some(200),
        },
    )
    .expect("complete provider probe");
    let token = test_result
        .verification_token
        .expect("successful test returns token");
    enable_remote_ai_provider(repo_path, enable_request(token, endpoint_url))
        .expect("enable remote summaries provider");
    allow_remote_ai(repo);
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
        content_locale: area_matrix_core::ContentLocale::En,
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
    _runtime: InstalledRuntime,
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
        let runtime = install_runtime_script(
            env_name,
            runtime_capability(env_name),
            &script_path,
            &script,
        );
        Self {
            _lock: guard,
            _runtime: runtime,
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
        let runtime = install_runtime_script(
            env_name,
            runtime_capability(env_name),
            &script_path,
            &script,
        );
        Self {
            _lock: guard,
            _runtime: runtime,
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

pub struct RemoteRuntimeProbe {
    _guard: MutexGuard<'static, ()>,
    _runtime: InstalledRuntime,
    output: tempfile::TempDir,
    marker_path: PathBuf,
}

impl RemoteRuntimeProbe {
    pub fn new() -> Self {
        let guard = REMOTE_RUNTIME_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let output = tempfile::tempdir().expect("create remote runtime probe directory");
        let script_path = output.path().join("remote-summary-runtime.sh");
        let marker_path = output.path().join("invoked");
        let script = format!(
            "#!/bin/sh\nprintf invoked > \"{}\"\nexit 33\n",
            marker_path.display()
        );
        let runtime = install_runtime_script(
            "AREAMATRIX_AI_SUMMARY_REMOTE_RUNTIME",
            "ai-summary-remote",
            &script_path,
            &script,
        );
        Self {
            _guard: guard,
            _runtime: runtime,
            output,
            marker_path,
        }
    }

    pub fn was_invoked(&self) -> bool {
        self.marker_path.exists()
    }
}

impl Drop for RemoteRuntimeProbe {
    fn drop(&mut self) {
        std::env::remove_var("AREAMATRIX_AI_SUMMARY_REMOTE_RUNTIME");
        let _ = self.output.path();
    }
}

fn runtime_capability(env_name: &str) -> &'static str {
    match env_name {
        "AREAMATRIX_AI_SUMMARY_LOCAL_RUNTIME" => "ai-summary-local",
        "AREAMATRIX_AI_SUMMARY_REMOTE_RUNTIME" => "ai-summary-remote",
        _ => panic!("unsupported AI summary runtime environment"),
    }
}
