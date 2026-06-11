use std::{fs, path::Path};

use area_matrix_core::{
    import_file, init_repo, ExternalEventKind, ImportDestination, ImportOptions, OverviewOutput,
    PlatformWatcherBackend, PlatformWatcherEventSample, PlatformWatcherHealthSignal,
    PlatformWatcherStatus, RepoInitMode, RepoInitOptions, StorageMode, SyncConflict,
    SyncConflictType,
};
use rusqlite::{params, Connection, OptionalExtension};

pub(crate) fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub(crate) fn initialized_repo() -> tempfile::TempDir {
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

pub(crate) fn import_repo_file(
    repo: &Path,
    target_directory: &str,
    filename: &str,
    bytes: &[u8],
) -> i64 {
    let source = tempfile::NamedTempFile::new().expect("create source file");
    fs::write(source.path(), bytes).expect("write source file");
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

pub(crate) fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) {
    let path = repo.join(relative_path);
    let parent = path.parent().expect("fixture path has parent directory");
    fs::create_dir_all(parent).expect("create fixture parent");
    fs::write(path, bytes).expect("write repository file");
}

pub(crate) fn watcher_signal(repo: &Path, path: &str) -> PlatformWatcherHealthSignal {
    PlatformWatcherHealthSignal {
        backend: PlatformWatcherBackend::Inotify,
        status: PlatformWatcherStatus::Running,
        watched_path: path_string(repo),
        last_event_id: Some(700),
        last_event_at: Some(1_777_700_000),
        last_sync_event_id: Some(699),
        last_sync_at: Some(1_777_699_990),
        last_rescan_at: None,
        pending_event_count: 1,
        watch_count: Some(128),
        error_summary: None,
        health_reasons: Vec::new(),
        recent_events: vec![PlatformWatcherEventSample {
            path: path.to_owned(),
            kind: ExternalEventKind::Modified,
            fs_event_id: 700,
            occurred_at: Some(1_777_700_000),
        }],
        reported_at: 1_777_700_010,
    }
}

pub(crate) fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            [key],
            |row| row.get(0),
        )
        .optional()
        .expect("query repo_config value")
}

pub(crate) fn active_file_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active file rows")
}

pub(crate) fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
}

pub(crate) fn user_files(repo: &Path) -> Vec<(String, Vec<u8>)> {
    let mut files = Vec::new();
    collect_user_files(repo, repo, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    files
}

pub(crate) fn conflict<'a>(
    conflicts: &'a [SyncConflict],
    conflict_type: SyncConflictType,
    primary_path: &str,
) -> &'a SyncConflict {
    conflicts
        .iter()
        .find(|conflict| {
            conflict.conflict_type == conflict_type && conflict.primary_path == primary_path
        })
        .expect("expected sync conflict")
}

pub(crate) fn insert_previous_conflict_state(repo: &Path, value: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO repo_config (key, value, updated_at)
             VALUES ('sync_conflict_state', ?1, 1)",
            params![value],
        )
        .expect("insert previous sync conflict state");
}

pub(crate) fn block_sync_conflict_state_writes(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER block_sync_conflict_validation_insert
             BEFORE INSERT ON repo_config
             WHEN NEW.key = 'sync_conflict_state'
             BEGIN
                 SELECT RAISE(ABORT, 'blocked sync conflict validation insert');
             END;
             CREATE TRIGGER block_sync_conflict_validation_update
             BEFORE UPDATE OF value, updated_at ON repo_config
             WHEN NEW.key = 'sync_conflict_state'
             BEGIN
                 SELECT RAISE(ABORT, 'blocked sync conflict validation update');
             END;",
        )
        .expect("install sync conflict state write blocker");
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
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
