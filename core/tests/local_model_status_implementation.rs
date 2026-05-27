use std::{fs, path::Path};

use area_matrix_core::{
    get_local_model_status, init_repo, locate_local_model_folder, AiFeatureKind, CoreError,
    LocalModelAvailability, LocalModelFolderRequest, LocalModelRecommendedAction,
    LocalModelStatusRequest, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

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

fn write_ready_manifest(model_dir: &Path) {
    fs::create_dir_all(model_dir).expect("create model directory");
    fs::write(
        model_dir.join("manifest.json"),
        r#"{
          "model_id": "areamatrix-local-classifier",
          "version": "1.0.3",
          "features": [
            {
              "feature": "ClassificationSuggestions",
              "available": true
            },
            {
              "feature": "AutoTags",
              "available": false,
              "unavailable_reason": "Tag head not bundled"
            },
            {
              "feature": "SemanticSearch",
              "available": true
            }
          ]
        }"#,
    )
    .expect("write model manifest");
    fs::write(
        model_dir.join("runtime-health.json"),
        r#"{ "status": "ready" }"#,
    )
    .expect("write runtime health");
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

#[test]
fn local_model_status_implementation_reads_manifest_runtime_and_persists_status_cache() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/local-classifier");
    write_ready_manifest(&model_dir);
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");

    let snapshot = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect("read local model status");

    assert_eq!(snapshot.availability, LocalModelAvailability::Ready);
    assert_eq!(snapshot.version.as_deref(), Some("1.0.3"));
    assert!(snapshot.size_bytes.expect("size is recorded") > 0);
    assert_eq!(
        snapshot.recommended_action,
        LocalModelRecommendedAction::None
    );
    assert!(snapshot.last_checked_at.is_some());
    assert!(snapshot.diagnostics_summary.contains("manifest=ok"));
    assert!(!snapshot.diagnostics_summary.contains("user readme"));

    let classifier = snapshot
        .feature_statuses
        .iter()
        .find(|status| status.feature == AiFeatureKind::ClassificationSuggestions)
        .expect("classification feature exists");
    assert!(classifier.available);
    let auto_tags = snapshot
        .feature_statuses
        .iter()
        .find(|status| status.feature == AiFeatureKind::AutoTags)
        .expect("auto-tags feature exists");
    assert!(!auto_tags.available);
    assert_eq!(
        auto_tags.unavailable_reason.as_deref(),
        Some("Tag head not bundled")
    );

    let cached = repo_config_value(repo.path(), "local_model_status:")
        .expect("local model status cache persisted");
    assert!(cached.contains("\"availability\":\"Ready\""));
    assert!(!repo
        .path()
        .join(".areamatrix/generated/ai_config.json")
        .exists());
    assert_eq!(
        fs::read_to_string(repo.path().join("README.md")).expect("read user README"),
        "user readme\n"
    );
}

#[test]
fn local_model_status_implementation_reports_missing_model_without_remote_fallback() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/missing");

    let snapshot = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect("missing model returns structured status");

    assert_eq!(snapshot.availability, LocalModelAvailability::NotInstalled);
    assert_eq!(
        snapshot.recommended_action,
        LocalModelRecommendedAction::OpenInstallHelp
    );
    assert_eq!(
        snapshot.last_error.as_deref(),
        Some("Model is not installed")
    );
    assert!(snapshot
        .feature_statuses
        .iter()
        .all(|status| !status.available));
    assert!(!snapshot.diagnostics_summary.contains("remote"));
}

#[test]
fn local_model_status_implementation_maps_manifest_and_runtime_failures() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/broken");
    fs::create_dir_all(&model_dir).expect("create model directory");
    fs::write(model_dir.join("manifest.json"), "{not-json").expect("write broken manifest");

    let corrupted = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect("broken manifest returns structured status");

    assert_eq!(corrupted.availability, LocalModelAvailability::Corrupted);
    assert_eq!(
        corrupted.recommended_action,
        LocalModelRecommendedAction::RepairMetadata
    );

    fs::write(
        model_dir.join("manifest.json"),
        r#"{
          "model_id": "areamatrix-local-classifier",
          "version": "0.9.0",
          "compatible": false
        }"#,
    )
    .expect("write incompatible manifest");
    let incompatible = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect("incompatible manifest returns structured status");
    assert_eq!(
        incompatible.availability,
        LocalModelAvailability::VersionIncompatible
    );

    fs::write(
        model_dir.join("manifest.json"),
        r#"{
          "model_id": "areamatrix-local-classifier",
          "version": "1.0.3"
        }"#,
    )
    .expect("write ready manifest");
    fs::write(
        model_dir.join("runtime-health.json"),
        r#"{ "status": "runtime_failed", "last_error": "loader exited" }"#,
    )
    .expect("write failed runtime health");
    let runtime_failed = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect("runtime failure returns structured status");
    assert_eq!(
        runtime_failed.availability,
        LocalModelAvailability::RuntimeFailed
    );
    assert_eq!(
        runtime_failed.recommended_action,
        LocalModelRecommendedAction::RunHealthCheck
    );
}

#[test]
fn local_model_status_implementation_locates_folder_without_creating_it() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/not-created");

    let location = locate_local_model_folder(path_string(repo.path()), folder_request(&model_dir))
        .expect("locate missing model folder");

    assert!(!location.exists);
    assert!(!location.readable);
    assert!(!location.openable);
    assert!(!model_dir.exists());

    fs::create_dir_all(&model_dir).expect("create model directory");
    let location = locate_local_model_folder(path_string(repo.path()), folder_request(&model_dir))
        .expect("locate existing model folder");
    assert!(location.exists);
    assert!(location.readable);
    assert!(location.openable);
}

#[test]
fn local_model_status_implementation_rejects_invalid_inputs_without_writing_cache() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/local-classifier");
    write_ready_manifest(&model_dir);

    let mut invalid = request(&model_dir);
    invalid.model_id = "bad/model".to_owned();
    let error = get_local_model_status(path_string(repo.path()), invalid)
        .expect_err("invalid model id is rejected");
    assert!(matches!(error, CoreError::Config { .. }));

    let metadata_path = repo.path().join(".areamatrix").join("models");
    let metadata_request = LocalModelStatusRequest {
        model_id: "areamatrix-local-classifier".to_owned(),
        storage_location: path_string(&metadata_path),
        cached_status: None,
    };
    let error = get_local_model_status(path_string(repo.path()), metadata_request)
        .expect_err("metadata-internal storage path is rejected");
    assert!(matches!(error, CoreError::Config { .. }));
    assert!(repo_config_value(repo.path(), "local_model_status:").is_none());
}
