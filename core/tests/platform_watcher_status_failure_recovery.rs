use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_fs_event_cursor, init_repo, record_watcher_health, set_fs_event_cursor, CoreError,
    ErrorKind, ErrorRecoverability, ExternalEventKind, OverviewOutput, PlatformWatcherBackend,
    PlatformWatcherEventSample, PlatformWatcherHealthReason, PlatformWatcherHealthSignal,
    PlatformWatcherStatus, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{Connection, OptionalExtension};

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

fn watcher_signal(repo: &Path) -> PlatformWatcherHealthSignal {
    PlatformWatcherHealthSignal {
        backend: PlatformWatcherBackend::Inotify,
        status: PlatformWatcherStatus::Running,
        watched_path: path_string(repo),
        last_event_id: Some(90),
        last_event_at: Some(1_777_500_000),
        last_sync_event_id: Some(81),
        last_sync_at: Some(1_777_500_010),
        last_rescan_at: None,
        pending_event_count: 1,
        watch_count: Some(64),
        error_summary: None,
        health_reasons: Vec::new(),
        recent_events: vec![PlatformWatcherEventSample {
            path: "docs/report.pdf".to_owned(),
            kind: ExternalEventKind::Modified,
            fs_event_id: 90,
            occurred_at: Some(1_777_500_000),
        }],
        reported_at: 1_777_500_020,
    }
}

fn empty_state_signal(repo: &Path) -> PlatformWatcherHealthSignal {
    PlatformWatcherHealthSignal {
        backend: PlatformWatcherBackend::Unknown,
        status: PlatformWatcherStatus::Unavailable,
        watched_path: path_string(repo),
        last_event_id: None,
        last_event_at: None,
        last_sync_event_id: None,
        last_sync_at: None,
        last_rescan_at: None,
        pending_event_count: 0,
        watch_count: None,
        error_summary: None,
        health_reasons: Vec::new(),
        recent_events: Vec::new(),
        reported_at: 0,
    }
}

fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    Connection::open(repo.join(".areamatrix/index.db"))
        .expect("open repository database")
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            [key],
            |row| row.get(0),
        )
        .optional()
        .expect("query repo_config value")
}

fn user_visible_root_entries(repo: &Path) -> Vec<String> {
    let mut entries = fs::read_dir(repo)
        .expect("read repository root")
        .map(|entry| {
            entry
                .expect("read root entry")
                .file_name()
                .to_string_lossy()
                .into_owned()
        })
        .filter(|name| name != ".areamatrix")
        .collect::<Vec<_>>();
    entries.sort();
    entries
}

fn staging_entries(repo: &Path) -> Vec<String> {
    let staging = repo.join(".areamatrix/staging");
    if !staging.exists() {
        return Vec::new();
    }
    let mut entries = fs::read_dir(staging)
        .expect("read staging directory")
        .map(|entry| {
            entry
                .expect("read staging entry")
                .file_name()
                .to_string_lossy()
                .into_owned()
        })
        .collect::<Vec<_>>();
    entries.sort();
    entries
}

fn user_file_bytes(repo: &Path) -> Vec<u8> {
    fs::read(repo.join("README.md")).expect("read user file bytes")
}

fn drop_repo_config_table(repo: &Path) {
    Connection::open(repo.join(".areamatrix/index.db"))
        .expect("open repository database")
        .execute("DROP TABLE repo_config", [])
        .expect("drop repo_config table for DB failure test");
}

struct MetadataWriteGuard {
    original: Vec<(PathBuf, fs::Permissions)>,
}

impl MetadataWriteGuard {
    fn readonly(repo: &Path) -> Self {
        let targets = [repo.join(".areamatrix"), repo.join(".areamatrix/index.db")];
        let original = targets
            .iter()
            .map(|path| {
                let permissions = fs::metadata(path)
                    .expect("read metadata permissions")
                    .permissions();
                make_readonly(path);
                (path.clone(), permissions)
            })
            .collect();
        Self { original }
    }
}

impl Drop for MetadataWriteGuard {
    fn drop(&mut self) {
        for (path, permissions) in self.original.drain(..) {
            // Best-effort restore keeps TempDir cleanup reliable after assertion failures.
            if fs::set_permissions(path, permissions).is_err() {}
        }
    }
}

#[cfg(unix)]
fn make_readonly(path: &Path) {
    use std::os::unix::fs::PermissionsExt;

    let mut permissions = fs::metadata(path)
        .expect("read permissions before readonly update")
        .permissions();
    permissions.set_mode(permissions.mode() & !0o222);
    fs::set_permissions(path, permissions).expect("set readonly permissions");
}

#[cfg(not(unix))]
fn make_readonly(path: &Path) {
    let mut permissions = fs::metadata(path)
        .expect("read permissions before readonly update")
        .permissions();
    permissions.set_readonly(true);
    fs::set_permissions(path, permissions).expect("set readonly permissions");
}

#[test]
fn platform_watcher_status_accepts_empty_state_without_side_effects() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user owned\n").expect("write user file");
    set_fs_event_cursor(path_string(repo.path()), 55).expect("seed fs event cursor");
    let before_user_file = user_file_bytes(repo.path());
    let before_root_entries = user_visible_root_entries(repo.path());
    let before_staging_entries = staging_entries(repo.path());

    let snapshot = record_watcher_health(path_string(repo.path()), empty_state_signal(repo.path()))
        .expect("record empty watcher health");

    assert_eq!(snapshot.status, PlatformWatcherStatus::Unavailable);
    assert_eq!(snapshot.backend, PlatformWatcherBackend::Unknown);
    assert_eq!(snapshot.last_event_id, None);
    assert_eq!(snapshot.pending_event_count, 0);
    assert!(snapshot.health_reasons.is_empty());
    assert!(snapshot.recent_events.is_empty());
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read cursor after empty health"),
        Some(55)
    );
    assert_eq!(user_file_bytes(repo.path()), before_user_file);
    assert_eq!(user_visible_root_entries(repo.path()), before_root_entries);
    assert_eq!(staging_entries(repo.path()), before_staging_entries);
}

#[test]
fn platform_watcher_status_rejects_illegal_input_without_partial_metadata() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user owned\n").expect("write user file");
    set_fs_event_cursor(path_string(repo.path()), 12).expect("seed fs event cursor");
    record_watcher_health(path_string(repo.path()), watcher_signal(repo.path()))
        .expect("record baseline watcher health");
    let before_user_file = user_file_bytes(repo.path());
    let before_metadata = repo_config_value(repo.path(), "platform_watcher_health");

    let mut invalid = watcher_signal(repo.path());
    invalid.pending_event_count = -1;
    let result = record_watcher_health(path_string(repo.path()), invalid);

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        record_watcher_health(String::new(), watcher_signal(repo.path()))
            .expect_err("empty repo path must be rejected")
            .kind(),
        ErrorKind::Db
    );
    assert_eq!(
        repo_config_value(repo.path(), "platform_watcher_health"),
        before_metadata
    );
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read cursor after invalid input"),
        Some(12)
    );
    assert_eq!(user_file_bytes(repo.path()), before_user_file);
}

#[test]
fn platform_watcher_status_records_permission_reason_as_structured_health_state() {
    let repo = initialized_repo();
    let mut signal = watcher_signal(repo.path());
    signal.status = PlatformWatcherStatus::Error;
    signal.error_summary = Some("watcher cannot read the selected folder".to_owned());
    signal.health_reasons = vec![PlatformWatcherHealthReason::PermissionDenied];

    let snapshot =
        record_watcher_health(path_string(repo.path()), signal).expect("record permission state");

    assert_eq!(snapshot.status, PlatformWatcherStatus::Error);
    assert_eq!(
        snapshot.health_reasons,
        vec![PlatformWatcherHealthReason::PermissionDenied]
    );
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read cursor after permission state"),
        None
    );
}

#[test]
fn platform_watcher_status_maps_metadata_permission_to_io_without_overwriting_snapshot() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user owned\n").expect("write user file");
    set_fs_event_cursor(path_string(repo.path()), 90).expect("seed fs event cursor");
    record_watcher_health(path_string(repo.path()), watcher_signal(repo.path()))
        .expect("record baseline watcher health");
    let before_user_file = user_file_bytes(repo.path());
    let before_metadata = repo_config_value(repo.path(), "platform_watcher_health");

    let guard = MetadataWriteGuard::readonly(repo.path());
    let mut updated = watcher_signal(repo.path());
    updated.status = PlatformWatcherStatus::Paused;
    let error = record_watcher_health(path_string(repo.path()), updated)
        .expect_err("readonly metadata must fail");
    drop(guard);

    assert_eq!(error.kind(), ErrorKind::Io);
    assert!(error.raw_context().contains("permission denied"));
    assert_eq!(
        error.to_error_mapping().recoverability,
        ErrorRecoverability::Retryable
    );
    assert_eq!(
        repo_config_value(repo.path(), "platform_watcher_health"),
        before_metadata
    );
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read cursor after permission error"),
        Some(90)
    );
    assert_eq!(user_file_bytes(repo.path()), before_user_file);
}

#[test]
fn platform_watcher_status_maps_db_schema_failure_without_user_file_or_cursor_changes() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user owned\n").expect("write user file");
    set_fs_event_cursor(path_string(repo.path()), 66).expect("seed fs event cursor");
    let before_user_file = user_file_bytes(repo.path());
    drop_repo_config_table(repo.path());

    let error = record_watcher_health(path_string(repo.path()), watcher_signal(repo.path()))
        .expect_err("missing repo_config table must fail");

    assert_eq!(error.kind(), ErrorKind::Db);
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read cursor after DB error"),
        Some(66)
    );
    assert_eq!(user_file_bytes(repo.path()), before_user_file);
}
