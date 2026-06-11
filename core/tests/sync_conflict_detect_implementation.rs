use std::{fs, path::Path};

use area_matrix_core::{
    detect_sync_conflicts, import_file, init_repo, CoreError, ExternalEventKind, ImportDestination,
    ImportOptions, OverviewOutput, PlatformWatcherBackend, PlatformWatcherEventSample,
    PlatformWatcherHealthSignal, PlatformWatcherStatus, RepoInitMode, RepoInitOptions, StorageMode,
    SyncConflictFileRole, SyncConflictSeverity, SyncConflictStatus, SyncConflictType,
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

fn source_file(bytes: &[u8]) -> tempfile::NamedTempFile {
    let file = tempfile::NamedTempFile::new().expect("create source file");
    fs::write(file.path(), bytes).expect("write source file");
    file
}

fn import_repo_file(repo: &Path, target_directory: &str, filename: &str, bytes: &[u8]) -> i64 {
    let source = source_file(bytes);
    let result = import_file(
        path_string(repo),
        path_string(source.path()),
        ImportOptions {
            mode: StorageMode::Copied,
            destination: ImportDestination::SelectedDirectory,
            target_directory: Some(target_directory.to_owned()),
            override_category: None,
            override_filename: Some(filename.to_owned()),
            duplicate_strategy: area_matrix_core::DuplicateStrategy::Ask,
        },
    )
    .expect("import repository file");
    result.id
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

fn active_file_count(repo: &Path) -> i64 {
    Connection::open(repo.join(".areamatrix/index.db"))
        .expect("open repository database")
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active file rows")
}

fn user_files(repo: &Path) -> Vec<(String, Vec<u8>)> {
    let mut files = Vec::new();
    collect_user_files(repo, repo, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    files
}

fn collect_user_files(repo: &Path, current: &Path, files: &mut Vec<(String, Vec<u8>)>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("entry is inside repo")
            .to_string_lossy()
            .replace('\\', "/");
        if relative.starts_with(".areamatrix") {
            continue;
        }
        if path.is_dir() {
            collect_user_files(repo, &path, files);
        } else {
            files.push((relative, fs::read(&path).expect("read user file")));
        }
    }
}

fn watcher_health(repo: &Path, path: &str) -> PlatformWatcherHealthSignal {
    PlatformWatcherHealthSignal {
        backend: PlatformWatcherBackend::Inotify,
        status: PlatformWatcherStatus::Running,
        watched_path: path_string(repo),
        last_event_id: Some(100),
        last_event_at: Some(1_777_500_000),
        last_sync_event_id: Some(99),
        last_sync_at: Some(1_777_499_990),
        last_rescan_at: None,
        pending_event_count: 1,
        watch_count: Some(64),
        error_summary: None,
        health_reasons: Vec::new(),
        recent_events: vec![PlatformWatcherEventSample {
            path: path.to_owned(),
            kind: ExternalEventKind::Modified,
            fs_event_id: 100,
            occurred_at: Some(1_777_500_000),
        }],
        reported_at: 1_777_500_010,
    }
}

#[test]
fn sync_conflict_detect_implementation_empty_repo_returns_empty_state() {
    let repo = initialized_repo();

    let conflicts = detect_sync_conflicts(path_string(repo.path())).expect("detect conflicts");

    assert!(conflicts.is_empty());
    let state =
        repo_config_value(repo.path(), "sync_conflict_state").expect("stored conflict state");
    let stored: serde_json::Value =
        serde_json::from_str(&state).expect("conflict state serializes as JSON");
    assert!(stored.as_array().expect("state is array").is_empty());
}

#[test]
fn sync_conflict_detect_implementation_lists_same_name_different_content_read_only() {
    let repo = initialized_repo();
    let file_id = import_repo_file(repo.path(), "docs", "report.pdf", b"original");
    fs::write(
        repo.path()
            .join("docs/report (Alice's conflicted copy).pdf"),
        b"conflicted",
    )
    .expect("write conflicted copy");
    let before_files = user_files(repo.path());
    let before_count = active_file_count(repo.path());

    let conflicts = detect_sync_conflicts(path_string(repo.path())).expect("detect conflicts");

    assert_eq!(conflicts.len(), 1);
    let conflict = &conflicts[0];
    assert_eq!(
        conflict.conflict_type,
        SyncConflictType::SameNameDifferentContent
    );
    assert_eq!(conflict.severity, SyncConflictSeverity::High);
    assert_eq!(conflict.status, SyncConflictStatus::NeedsReview);
    assert_eq!(conflict.primary_path, "docs/report.pdf");
    assert_eq!(conflict.version_count, 2);
    assert!(conflict
        .affected_files
        .iter()
        .any(|file| file.file_id == Some(file_id) && file.role == SyncConflictFileRole::Existing));
    assert!(conflict
        .affected_files
        .iter()
        .any(|file| file.file_id.is_none() && file.role == SyncConflictFileRole::ConflictCopy));
    assert_eq!(user_files(repo.path()), before_files);
    assert_eq!(active_file_count(repo.path()), before_count);
}

#[test]
fn sync_conflict_detect_implementation_records_concurrent_modification_from_watcher_state() {
    let repo = initialized_repo();
    import_repo_file(repo.path(), "docs", "report.pdf", b"original");
    area_matrix_core::record_watcher_health(
        path_string(repo.path()),
        watcher_health(repo.path(), "docs/report.pdf"),
    )
    .expect("record watcher health");
    fs::write(repo.path().join("docs/report.pdf"), b"changed externally")
        .expect("change imported file externally");

    let conflicts = detect_sync_conflicts(path_string(repo.path())).expect("detect conflicts");

    assert_eq!(conflicts.len(), 1);
    let conflict = &conflicts[0];
    assert_eq!(
        conflict.conflict_type,
        SyncConflictType::ConcurrentModification
    );
    assert_eq!(conflict.source_provider.as_deref(), Some("Inotify"));
    assert!(conflict
        .affected_files
        .iter()
        .any(|file| file.role == SyncConflictFileRole::Incoming));

    let state =
        repo_config_value(repo.path(), "sync_conflict_state").expect("stored conflict state");
    let stored: Vec<serde_json::Value> =
        serde_json::from_str(&state).expect("stored conflict state parses");
    assert_eq!(stored.len(), 1);
    assert_eq!(stored[0]["conflict_type"], "ConcurrentModification");
    assert_eq!(stored[0]["status"], "NeedsReview");
}

#[test]
fn sync_conflict_detect_implementation_reports_missing_version_without_deleting_metadata() {
    let repo = initialized_repo();
    import_repo_file(repo.path(), "docs", "missing.pdf", b"tracked");
    fs::remove_file(repo.path().join("docs/missing.pdf")).expect("remove backing file");
    let before_count = active_file_count(repo.path());

    let conflicts = detect_sync_conflicts(path_string(repo.path())).expect("detect conflicts");

    assert_eq!(conflicts.len(), 1);
    let conflict = &conflicts[0];
    assert_eq!(conflict.conflict_type, SyncConflictType::MissingVersion);
    assert_eq!(conflict.severity, SyncConflictSeverity::High);
    assert_eq!(conflict.primary_path, "docs/missing.pdf");
    assert_eq!(
        conflict.affected_files[0].role,
        SyncConflictFileRole::Missing
    );
    assert_eq!(active_file_count(repo.path()), before_count);
}

#[test]
fn sync_conflict_detect_implementation_maps_uninitialized_repo_to_db_error() {
    let repo = tempfile::tempdir().expect("create uninitialized repo");

    let result = detect_sync_conflicts(path_string(repo.path()));

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert!(!repo.path().join(".areamatrix").exists());
}
