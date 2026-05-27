use std::{fs, path::Path};

use area_matrix_core::{
    get_local_model_status, init_repo, locate_local_model_folder, CoreError, ErrorKind,
    ErrorRecoverability, ErrorSeverity, LocalModelAvailability, LocalModelCachedStatus,
    LocalModelFolderRequest, LocalModelRecommendedAction, LocalModelStatusRequest, OverviewOutput,
    RepoInitMode, RepoInitOptions,
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

fn cached_request(model_dir: &Path) -> LocalModelStatusRequest {
    let storage_location = path_string(model_dir);
    LocalModelStatusRequest {
        model_id: "areamatrix-local-classifier".to_owned(),
        storage_location: storage_location.clone(),
        cached_status: Some(LocalModelCachedStatus {
            model_id: "areamatrix-local-classifier".to_owned(),
            storage_location,
            availability: LocalModelAvailability::Unknown,
            version: None,
            size_bytes: None,
            last_error: None,
            recommended_action: LocalModelRecommendedAction::CheckStatus,
            last_checked_at: None,
            diagnostics_summary: "manifest=unknown; runtime=not checked".to_owned(),
        }),
    }
}

fn folder_request(model_dir: &Path) -> LocalModelFolderRequest {
    LocalModelFolderRequest {
        model_id: "areamatrix-local-classifier".to_owned(),
        storage_location: path_string(model_dir),
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

fn write_manifest(model_dir: &Path, content: &str) {
    fs::create_dir_all(model_dir).expect("create model directory");
    fs::write(model_dir.join("manifest.json"), content).expect("write model manifest");
}

#[test]
fn local_model_status_failure_rejects_invalid_inputs_without_cache_writes() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/local");

    let mut negative_size = cached_request(&model_dir);
    negative_size
        .cached_status
        .as_mut()
        .expect("test request has cached status")
        .size_bytes = Some(-1);
    assert!(matches!(
        get_local_model_status(path_string(repo.path()), negative_size),
        Err(CoreError::Config { .. })
    ));

    let mut sensitive_cached_error = cached_request(&model_dir);
    sensitive_cached_error
        .cached_status
        .as_mut()
        .expect("test request has cached status")
        .last_error = Some("api key sk-SECRET must not cross diagnostics".to_owned());
    assert!(matches!(
        get_local_model_status(path_string(repo.path()), sensitive_cached_error),
        Err(CoreError::Config { .. })
    ));

    let mut sensitive_cached_summary = cached_request(&model_dir);
    sensitive_cached_summary
        .cached_status
        .as_mut()
        .expect("test request has cached status")
        .diagnostics_summary = "remote_provider token=secret".to_owned();
    assert!(matches!(
        get_local_model_status(path_string(repo.path()), sensitive_cached_summary),
        Err(CoreError::Config { .. })
    ));

    assert!(repo_config_value(repo.path(), "local_model_status:").is_none());
    assert!(!model_dir.exists());
}

#[test]
fn local_model_status_failure_reports_invalid_manifest_state_explicitly() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/invalid-state");
    write_manifest(
        &model_dir,
        r#"{
          "model_id": "areamatrix-local-classifier",
          "version": "1.0.3",
          "availability": "UnexpectedState"
        }"#,
    );

    let snapshot = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect("invalid manifest state returns structured local status");

    assert_eq!(snapshot.availability, LocalModelAvailability::Corrupted);
    assert_eq!(
        snapshot.recommended_action,
        LocalModelRecommendedAction::RepairMetadata
    );
    assert_eq!(
        snapshot.last_error.as_deref(),
        Some("manifest availability is invalid")
    );
    assert!(snapshot
        .diagnostics_summary
        .contains("manifest availability is invalid"));
}

#[test]
fn local_model_status_failure_sanitizes_sensitive_manifest_and_runtime_details() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/sensitive");
    write_manifest(
        &model_dir,
        r#"{
          "model_id": "areamatrix-local-classifier",
          "version": "1.0.3",
          "availability": "Error",
          "last_error": "provider_config api key sk-SECRET"
        }"#,
    );
    fs::write(
        model_dir.join("runtime-health.json"),
        r#"{ "status": "error", "diagnostics_summary": "authorization: Bearer secret" }"#,
    )
    .expect("write runtime health metadata");

    let snapshot = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect("sensitive manifest details are sanitized");
    let cached = repo_config_value(repo.path(), "local_model_status:")
        .expect("sanitized local model status cache exists");

    assert_eq!(
        snapshot.last_error.as_deref(),
        Some("redacted sensitive local model detail")
    );
    for leaked in [
        "sk-SECRET",
        "provider_config",
        "authorization:",
        "Bearer secret",
    ] {
        assert!(!snapshot.diagnostics_summary.contains(leaked));
        assert!(!cached.contains(leaked));
    }
    assert!(snapshot.diagnostics_summary.contains("last_error=redacted"));
}

#[test]
fn local_model_status_failure_maps_io_without_leaving_cache_or_filesystem_residue() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/io-error");
    fs::create_dir_all(model_dir.join("manifest.json")).expect("create unreadable manifest path");
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");

    let error = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect_err("manifest directory is an IO failure");

    assert!(matches!(error, CoreError::Io { .. }));
    assert!(repo_config_value(repo.path(), "local_model_status:").is_none());
    assert_eq!(
        fs::read_to_string(repo.path().join("README.md")).expect("read user README"),
        "user readme\n"
    );
    assert!(!repo
        .path()
        .join(".areamatrix/generated/ai_config.json")
        .exists());
}

#[cfg(unix)]
#[test]
fn local_model_status_failure_maps_status_cache_permission_and_preserves_files() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let model_dir = repo.path().join("models/permission");
    write_manifest(
        &model_dir,
        r#"{
          "model_id": "areamatrix-local-classifier",
          "version": "1.0.3"
        }"#,
    );
    fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");

    let db_path = repo.path().join(".areamatrix/index.db");
    let original_permissions = fs::metadata(&db_path)
        .expect("read db metadata")
        .permissions();
    fs::set_permissions(&db_path, fs::Permissions::from_mode(0o444)).expect("make db read-only");

    let error = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect_err("read-only status cache is a permission failure");

    fs::set_permissions(&db_path, original_permissions).expect("restore db permissions");

    assert!(matches!(error, CoreError::PermissionDenied { .. }));
    assert!(repo_config_value(repo.path(), "local_model_status:").is_none());
    assert_eq!(
        fs::read_to_string(repo.path().join("README.md")).expect("read user README"),
        "user readme\n"
    );
}

#[test]
fn local_model_status_failure_maps_db_persistence_error_to_documented_config_error() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/db-error");
    write_manifest(
        &model_dir,
        r#"{
          "model_id": "areamatrix-local-classifier",
          "version": "1.0.3"
        }"#,
    );
    fs::write(
        repo.path().join(".areamatrix/index.db"),
        "not a sqlite database",
    )
    .expect("corrupt status cache database");

    let error = get_local_model_status(path_string(repo.path()), request(&model_dir))
        .expect_err("corrupt status cache database fails explicitly");

    assert!(matches!(error, CoreError::Config { reason } if reason.contains("persistence")));
    assert!(model_dir.join("manifest.json").is_file());
}

#[test]
fn local_model_status_failure_keeps_folder_location_read_only_for_empty_state() {
    let repo = initialized_repo();
    let model_dir = repo.path().join("models/not-installed");

    let location = locate_local_model_folder(path_string(repo.path()), folder_request(&model_dir))
        .expect("missing folder location returns structured empty state");

    assert!(!location.exists);
    assert!(!location.readable);
    assert!(!location.openable);
    assert_eq!(
        location.unavailable_reason.as_deref(),
        Some("Model folder does not exist")
    );
    assert!(!model_dir.exists());
}

#[test]
fn local_model_status_failure_errors_have_stable_ui_mappings() {
    let config =
        CoreError::config("local model status cache persistence failed").to_error_mapping();
    assert_eq!(config.kind, ErrorKind::Config);
    assert_eq!(config.severity, ErrorSeverity::Medium);
    assert_eq!(
        config.recoverability,
        ErrorRecoverability::UserActionRequired
    );

    let permission = CoreError::permission_denied("permission denied").to_error_mapping();
    assert_eq!(permission.kind, ErrorKind::PermissionDenied);
    assert_eq!(permission.severity, ErrorSeverity::High);

    let io = CoreError::io("local model metadata inspection failed").to_error_mapping();
    assert_eq!(io.kind, ErrorKind::Io);
    assert_eq!(io.recoverability, ErrorRecoverability::Retryable);
}
