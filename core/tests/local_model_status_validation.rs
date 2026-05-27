use std::{fs, path::Path};

use area_matrix_core::{
    get_local_model_status, init_repo, locate_local_model_folder, AiFeatureKind, CoreError,
    CoreResult, LocalModelAvailability, LocalModelFolderLocation, LocalModelFolderRequest,
    LocalModelRecommendedAction, LocalModelStatusRequest, LocalModelStatusSnapshot, OverviewOutput,
    RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-3-ai/C3-02-local-model-status.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-3-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const LOCAL_MODEL_STATUS_RS: &str = include_str!("../src/local_model_status.rs");
const INSPECTION_RS: &str = include_str!("../src/local_model_status/inspection.rs");
const SNAPSHOT_RS: &str = include_str!("../src/local_model_status/snapshot.rs");

#[derive(Debug, Eq, PartialEq)]
struct ValidationSnapshot {
    status_cache: Option<String>,
    user_readme: String,
    generated_entries: Vec<String>,
    model_entries: Vec<String>,
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

fn request(model_dir: &Path) -> LocalModelStatusRequest {
    LocalModelStatusRequest {
        model_id: "areamatrix-local-classifier".to_owned(),
        storage_location: path_string(model_dir),
        cached_status: None,
    }
}

fn folder_request(model_dir: &Path) -> LocalModelFolderRequest {
    LocalModelFolderRequest {
        model_id: "areamatrix-local-classifier".to_owned(),
        storage_location: path_string(model_dir),
    }
}

fn write_ready_model(model_dir: &Path) {
    fs::create_dir_all(model_dir).expect("create local model directory");
    fs::write(
        model_dir.join("manifest.json"),
        r#"{
          "model_id": "areamatrix-local-classifier",
          "version": "1.0.3",
          "features": [
            { "feature": "ClassificationSuggestions", "available": true },
            {
              "feature": "AutoTags",
              "available": false,
              "unavailable_reason": "Tag head not installed"
            },
            { "feature": "SemanticSearch", "available": true }
          ]
        }"#,
    )
    .expect("write local model manifest");
    fs::write(
        model_dir.join("runtime-health.json"),
        r#"{ "status": "ready", "diagnostics_summary": "runtime warmed" }"#,
    )
    .expect("write local runtime health");
}

fn write_invalid_runtime_model(model_dir: &Path) {
    fs::create_dir_all(model_dir).expect("create local model directory");
    fs::write(
        model_dir.join("manifest.json"),
        r#"{
          "model_id": "areamatrix-local-classifier",
          "version": "1.0.3",
          "last_error": "api key sk-SECRET"
        }"#,
    )
    .expect("write local model manifest");
    fs::write(model_dir.join("runtime-health.json"), "{not-json")
        .expect("write invalid runtime health");
}

fn snapshot(repo: &Path, model_dir: &Path) -> ValidationSnapshot {
    ValidationSnapshot {
        status_cache: repo_config_value(repo, "local_model_status:"),
        user_readme: fs::read_to_string(repo.join("README.md")).expect("read user README"),
        generated_entries: relative_entries(repo, &repo.join(".areamatrix/generated")),
        model_entries: relative_entries(repo, model_dir),
    }
}

fn repo_config_value(repo: &Path, key_prefix: &str) -> Option<String> {
    let connection =
        Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database");
    connection
        .query_row(
            "SELECT value FROM repo_config WHERE key LIKE ?1 ORDER BY key LIMIT 1",
            [format!("{key_prefix}%")],
            |row| row.get::<_, String>(0),
        )
        .ok()
}

fn relative_entries(repo: &Path, dir: &Path) -> Vec<String> {
    if !dir.exists() {
        return Vec::new();
    }
    let mut entries = Vec::new();
    collect_relative_entries(repo, dir, &mut entries);
    entries.sort();
    entries
}

fn collect_relative_entries(repo: &Path, current: &Path, entries: &mut Vec<String>) {
    for entry in fs::read_dir(current).expect("read directory entries") {
        let entry = entry.expect("read directory entry");
        let path = entry.path();
        entries.push(
            path.strip_prefix(repo)
                .expect("entry is inside repository")
                .to_string_lossy()
                .into_owned(),
        );
        if path.is_dir() {
            collect_relative_entries(repo, &path, entries);
        }
    }
}

fn feature(
    snapshot: &LocalModelStatusSnapshot,
    kind: AiFeatureKind,
) -> &area_matrix_core::LocalModelFeatureStatus {
    snapshot
        .feature_statuses
        .iter()
        .find(|status| status.feature == kind)
        .expect("feature status exists")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_not_contains(haystack: &str, needle: &str) {
    assert!(
        !haystack.contains(needle),
        "expected text not to contain `{needle}`"
    );
}

#[test]
fn local_model_status_validation_covers_success_path_for_ui_readiness() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/local-classifier");
    write_ready_model(&model_dir);
    fs::write(repo.path().join("README.md"), "user readme must stay private\n")
        .expect("write user README");
    let before = snapshot(repo.path(), &model_dir);

    let status = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect("ready local model status succeeds");
    let location = locate_local_model_folder(path_string(repo.path()), folder_request(&model_dir))
        .expect("ready local model folder can be located");

    assert_eq!(status.availability, LocalModelAvailability::Ready);
    assert_eq!(status.version.as_deref(), Some("1.0.3"));
    assert!(status.size_bytes.expect("disk usage is available") > 0);
    assert_eq!(
        status.recommended_action,
        LocalModelRecommendedAction::None
    );
    assert!(status.last_checked_at.is_some());
    assert!(status.diagnostics_summary.contains("manifest=ok"));
    assert!(status.diagnostics_summary.contains("runtime=ready"));
    assert_not_contains(&status.diagnostics_summary, "user readme");

    assert!(feature(&status, AiFeatureKind::ClassificationSuggestions).available);
    assert!(feature(&status, AiFeatureKind::SemanticSearch).available);
    let tags = feature(&status, AiFeatureKind::AutoTags);
    assert!(!tags.available);
    assert_eq!(
        tags.unavailable_reason.as_deref(),
        Some("Tag head not installed")
    );

    assert!(location.exists);
    assert!(location.readable);
    assert!(location.openable);
    assert_eq!(location.unavailable_reason, None);

    let after = snapshot(repo.path(), &model_dir);
    let cached = after
        .status_cache
        .as_deref()
        .expect("successful status persists local model status cache");
    assert!(cached.contains("\"availability\":\"Ready\""));
    assert_eq!(after.user_readme, before.user_readme);
    assert_eq!(after.generated_entries, before.generated_entries);
    assert_eq!(after.model_entries, before.model_entries);
}

#[test]
fn local_model_status_validation_covers_failure_paths_without_remote_fallback_or_writes() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/broken-runtime");
    write_invalid_runtime_model(&model_dir);
    fs::write(repo.path().join("README.md"), "private local document body\n")
        .expect("write user README");
    let before = snapshot(repo.path(), &model_dir);

    let status = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect("invalid runtime health maps to structured local status");

    assert_eq!(status.availability, LocalModelAvailability::RuntimeFailed);
    assert_eq!(
        status.recommended_action,
        LocalModelRecommendedAction::RunHealthCheck
    );
    assert_eq!(
        status.last_error.as_deref(),
        Some("runtime health metadata is invalid")
    );
    for leaked in ["sk-SECRET", "remote_provider", "provider_config", "private local"] {
        assert_not_contains(&status.diagnostics_summary, leaked);
    }
    assert!(status
        .feature_statuses
        .iter()
        .all(|feature| !feature.available));

    let after = snapshot(repo.path(), &model_dir);
    let cached = after
        .status_cache
        .as_deref()
        .expect("structured failure status persists sanitized cache");
    assert!(cached.contains("\"availability\":\"RuntimeFailed\""));
    assert_not_contains(cached, "sk-SECRET");
    assert_not_contains(cached, "remote_provider");
    assert_eq!(after.user_readme, before.user_readme);
    assert_eq!(after.generated_entries, before.generated_entries);
    assert_eq!(after.model_entries, before.model_entries);

    let mut invalid_request = request(&model_dir);
    invalid_request.model_id = "bad/model".to_owned();
    let invalid_error = get_local_model_status(path_string(repo.path()), invalid_request)
        .expect_err("invalid request is rejected");
    assert!(matches!(invalid_error, CoreError::Config { .. }));
    assert_eq!(snapshot(repo.path(), &model_dir), after);
}

#[test]
fn local_model_status_validation_locks_core_api_udl_and_rust_contract() {
    fn assert_status_signature(
        _: fn(String, LocalModelStatusRequest) -> CoreResult<LocalModelStatusSnapshot>,
    ) {
    }
    fn assert_folder_signature(
        _: fn(String, LocalModelFolderRequest) -> CoreResult<LocalModelFolderLocation>,
    ) {
    }

    assert_status_signature(get_local_model_status);
    assert_folder_signature(locate_local_model_folder);

    for fragment in [
        "计划新增：`get_local_model_status`、`locate_local_model_folder`",
        "availability、version、size、last_error、recommended_action、last_checked_at、diagnostics_summary。",
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
        "LocalModelFolderLocation locate_local_model_folder(",
        "dictionary LocalModelCachedStatus",
        "dictionary LocalModelStatusSnapshot",
        "sequence<LocalModelFeatureStatus> feature_statuses;",
        "dictionary LocalModelFolderLocation",
        "boolean openable;",
        "enum LocalModelAvailability",
        "\"Ready\"",
        "\"RuntimeFailed\"",
        "enum LocalModelRecommendedAction",
        "\"RunHealthCheck\"",
        "\"UseNonAiFallback\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
    for fragment in [
        "pub fn get_local_model_status",
        "pub fn locate_local_model_folder",
        "This API must not download, install, delete, train",
        "enable remote fallback",
        "expose API keys/provider config through diagnostics",
        "Core must not create missing folders",
    ] {
        assert_contains(API_RS, fragment);
    }
    for fragment in [
        "pub(crate) fn get_local_model_status",
        "pub(crate) fn locate_local_model_folder",
        "validate_cached_status",
        "looks_sensitive",
        "update_local_model_status_record",
    ] {
        assert_contains(LOCAL_MODEL_STATUS_RS, fragment);
    }
    for fragment in [
        "inspect_local_model",
        "read_manifest",
        "read_runtime_health",
        "manifest_features",
        "runtime_availability",
    ] {
        assert_contains(INSPECTION_RS, fragment);
    }
    for fragment in [
        "LocalModelRecommendedAction::OpenInstallHelp",
        "LocalModelRecommendedAction::RunHealthCheck",
        "LocalModelRecommendedAction::RepairMetadata",
        "AiFeatureKind::ClassificationSuggestions",
        "AiFeatureKind::SemanticSearch",
    ] {
        assert_contains(SNAPSHOT_RS, fragment);
    }
}
