use std::{fs, path::Path};

use area_matrix_core::{
    get_fs_event_cursor, init_repo, record_watcher_health, set_fs_event_cursor, CoreError,
    ExternalEventKind, OverviewOutput, PlatformWatcherBackend, PlatformWatcherEventSample,
    PlatformWatcherHealthReason, PlatformWatcherHealthSignal, PlatformWatcherStatus, RepoInitMode,
    RepoInitOptions,
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
        last_event_id: Some(88),
        last_event_at: Some(1_777_400_000),
        last_sync_event_id: Some(80),
        last_sync_at: Some(1_777_400_010),
        last_rescan_at: Some(1_777_399_000),
        pending_event_count: 2,
        watch_count: Some(512),
        error_summary: Some("inotify queue is healthy".to_owned()),
        health_reasons: vec![PlatformWatcherHealthReason::NetworkMount],
        recent_events: vec![PlatformWatcherEventSample {
            path: "docs/report.pdf".to_owned(),
            kind: ExternalEventKind::Modified,
            fs_event_id: 88,
            occurred_at: Some(1_777_400_000),
        }],
        reported_at: 1_777_400_020,
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

fn user_file_bytes(repo: &Path) -> Vec<u8> {
    fs::read(repo.join("README.md")).expect("read user file bytes")
}

#[test]
fn platform_watcher_status_implementation_records_snapshot_metadata_without_advancing_cursor() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user owned\n").expect("write user file");
    set_fs_event_cursor(path_string(repo.path()), 41).expect("seed fs event cursor");
    let before_user_file = user_file_bytes(repo.path());

    let snapshot = record_watcher_health(path_string(repo.path()), watcher_signal(repo.path()))
        .expect("record watcher health");

    assert_eq!(snapshot.repo_path, path_string(repo.path()));
    assert_eq!(snapshot.backend, PlatformWatcherBackend::Inotify);
    assert_eq!(snapshot.status, PlatformWatcherStatus::Running);
    assert_eq!(snapshot.last_event_id, Some(88));
    assert_eq!(snapshot.last_sync_event_id, Some(80));
    assert_eq!(snapshot.pending_event_count, 2);
    assert_eq!(snapshot.watch_count, Some(512));
    assert_eq!(
        snapshot.health_reasons,
        vec![PlatformWatcherHealthReason::NetworkMount]
    );
    assert_eq!(snapshot.recent_events.len(), 1);
    assert_eq!(snapshot.recent_events[0].path, "docs/report.pdf");
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read cursor after health record"),
        Some(41)
    );
    assert_eq!(user_file_bytes(repo.path()), before_user_file);

    let stored =
        repo_config_value(repo.path(), "platform_watcher_health").expect("stored watcher health");
    let stored: serde_json::Value =
        serde_json::from_str(&stored).expect("stored watcher health is JSON");
    assert_eq!(stored["repo_path"], path_string(repo.path()));
    assert_eq!(stored["backend"], "Inotify");
    assert_eq!(stored["last_event_id"], 88);
    assert_eq!(stored["last_sync_event_id"], 80);
    assert_eq!(stored["recent_events"][0]["kind"], "Modified");
}

#[test]
fn platform_watcher_status_implementation_updates_existing_health_metadata_only() {
    let repo = initialized_repo();
    let mut first = watcher_signal(repo.path());
    first.status = PlatformWatcherStatus::Starting;
    first.pending_event_count = 0;
    record_watcher_health(path_string(repo.path()), first).expect("record first health signal");

    let mut second = watcher_signal(repo.path());
    second.status = PlatformWatcherStatus::Error;
    second.pending_event_count = 7;
    second.error_summary = Some("watch limit exceeded".to_owned());
    second.health_reasons = vec![PlatformWatcherHealthReason::LimitExceeded];

    let snapshot =
        record_watcher_health(path_string(repo.path()), second).expect("record updated signal");

    assert_eq!(snapshot.status, PlatformWatcherStatus::Error);
    assert_eq!(snapshot.pending_event_count, 7);
    assert_eq!(
        snapshot.health_reasons,
        vec![PlatformWatcherHealthReason::LimitExceeded]
    );
    let stored =
        repo_config_value(repo.path(), "platform_watcher_health").expect("stored watcher health");
    let stored: serde_json::Value =
        serde_json::from_str(&stored).expect("stored watcher health is JSON");
    assert_eq!(stored["status"], "Error");
    assert_eq!(stored["pending_event_count"], 7);
    assert_eq!(stored["health_reasons"][0], "LimitExceeded");
}

#[test]
fn platform_watcher_status_implementation_rejects_invalid_signal_without_persistence() {
    let repo = initialized_repo();
    let mut invalid = watcher_signal(repo.path());
    invalid.recent_events = vec![
        PlatformWatcherEventSample {
            path: "a.txt".to_owned(),
            kind: ExternalEventKind::Modified,
            fs_event_id: 1,
            occurred_at: None,
        };
        6
    ];

    let result = record_watcher_health(path_string(repo.path()), invalid);

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert!(repo_config_value(repo.path(), "platform_watcher_health").is_none());
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("cursor remains readable"),
        None
    );
}

#[test]
fn platform_watcher_status_implementation_maps_missing_metadata_to_db_error() {
    let repo = tempfile::tempdir().expect("create uninitialized repo");

    let result = record_watcher_health(path_string(repo.path()), watcher_signal(repo.path()));

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert!(!repo.path().join(".areamatrix").exists());
}
