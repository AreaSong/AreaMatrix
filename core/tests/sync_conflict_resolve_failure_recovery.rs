use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    detect_sync_conflicts, import_file, init_repo, preview_sync_conflict_resolution,
    resolve_sync_conflict, CoreError, ImportDestination, ImportOptions, OverviewOutput,
    RepoInitMode, RepoInitOptions, StorageMode, SyncConflict, SyncConflictResolutionRequest,
    SyncConflictResolutionStrategy, SyncConflictStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

mod support;

use support::system_trash_home::with_test_system_trash;

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

fn import_repo_file(repo: &Path, target_directory: &str, filename: &str, bytes: &[u8]) -> i64 {
    let source = tempfile::NamedTempFile::new().expect("create source file");
    fs::write(source.path(), bytes).expect("write source file");
    import_file(
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
    .expect("import repository file")
    .id
}

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) {
    let path = repo.join(relative_path);
    fs::create_dir_all(path.parent().expect("fixture has parent directory"))
        .expect("create fixture parent");
    fs::write(path, bytes).expect("write repository file");
}

fn setup_same_name_conflict() -> (tempfile::TempDir, String, i64) {
    let repo = initialized_repo();
    let file_id = import_repo_file(repo.path(), "docs", "report.pdf", b"original");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );
    let conflicts = detect_sync_conflicts(path_string(repo.path())).expect("detect conflicts");
    assert_eq!(conflicts.len(), 1);
    (repo, conflicts[0].conflict_id.clone(), file_id)
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn conflict_state(repo: &Path) -> Vec<SyncConflict> {
    let value: String = open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = 'sync_conflict_state'",
            [],
            |row| row.get(0),
        )
        .expect("read sync conflict state");
    serde_json::from_str(&value).expect("sync conflict state parses")
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

fn active_file_snapshot(repo: &Path, file_id: i64) -> (String, i64, String) {
    open_db(repo)
        .query_row(
            "SELECT path, size_bytes, hash_sha256
             FROM files
             WHERE id = ?1 AND status = 'active'",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read active file row")
}

fn sync_resolution_change_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*)
             FROM change_log
             WHERE action = 'external_modified'
               AND json_extract(detail_json, '$.kind') = 'sync_conflict_resolved'",
            [],
            |row| row.get(0),
        )
        .expect("count sync conflict resolution changes")
}

fn set_database_readonly(repo: &Path) -> DatabasePermissionGuard {
    let path = repo.join(".areamatrix/index.db");
    let original_permissions = fs::metadata(&path)
        .expect("read database permissions")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_readonly(true);
    fs::set_permissions(&path, readonly_permissions).expect("make database read-only");
    DatabasePermissionGuard {
        path,
        original_permissions,
    }
}

struct DatabasePermissionGuard {
    path: PathBuf,
    original_permissions: fs::Permissions,
}

impl Drop for DatabasePermissionGuard {
    fn drop(&mut self) {
        let _restore_result = fs::set_permissions(&self.path, self.original_permissions.clone());
    }
}

fn install_sync_resolution_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_sync_resolution_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'external_modified'
              AND json_extract(NEW.detail_json, '$.kind') = 'sync_conflict_resolved'
             BEGIN
               SELECT RAISE(ABORT, 'forced sync conflict resolution log failure');
             END;",
        )
        .expect("install sync conflict resolution log failure trigger");
}

fn preview_token(repo: &Path, conflict_id: &str) -> String {
    preview_sync_conflict_resolution(
        path_string(repo),
        conflict_id.to_owned(),
        SyncConflictResolutionStrategy::UseIncoming,
    )
    .expect("preview use incoming")
    .preview_token
    .expect("preview token is available")
}

#[test]
fn sync_conflict_resolve_failure_recovery_preview_rejects_unwritable_metadata_read_only() {
    with_test_system_trash(|_trash_dir| {
        let (repo, conflict_id, file_id) = setup_same_name_conflict();
        let before_files = user_files(repo.path());
        let before_file_row = active_file_snapshot(repo.path(), file_id);

        let permissions = set_database_readonly(repo.path());
        let result = preview_sync_conflict_resolution(
            path_string(repo.path()),
            conflict_id,
            SyncConflictResolutionStrategy::KeepBoth,
        );
        drop(permissions);

        assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
        assert_eq!(user_files(repo.path()), before_files);
        assert_eq!(active_file_snapshot(repo.path(), file_id), before_file_row);
        assert_eq!(
            conflict_state(repo.path())[0].status,
            SyncConflictStatus::NeedsReview
        );
        assert_eq!(sync_resolution_change_count(repo.path()), 0);
    });
}

#[test]
fn sync_conflict_resolve_failure_recovery_preflights_db_before_file_moves() {
    with_test_system_trash(|trash_dir| {
        let (repo, conflict_id, file_id) = setup_same_name_conflict();
        let token = preview_token(repo.path(), &conflict_id);
        let before_files = user_files(repo.path());
        let before_file_row = active_file_snapshot(repo.path(), file_id);

        let permissions = set_database_readonly(repo.path());
        let result = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id,
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::UseIncoming,
                preview_token: token,
                replace_confirmed: true,
                replace_confirmation_id: Some("replace-confirmed".to_owned()),
            },
        );
        drop(permissions);

        assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
        assert_eq!(user_files(repo.path()), before_files);
        assert_eq!(active_file_snapshot(repo.path(), file_id), before_file_row);
        assert_eq!(
            conflict_state(repo.path())[0].status,
            SyncConflictStatus::NeedsReview
        );
        assert_eq!(sync_resolution_change_count(repo.path()), 0);
        assert!(!trash_dir.join("report.pdf").exists());
    });
}

#[test]
fn sync_conflict_resolve_failure_recovery_rolls_back_files_when_db_write_fails() {
    with_test_system_trash(|trash_dir| {
        let (repo, conflict_id, file_id) = setup_same_name_conflict();
        let token = preview_token(repo.path(), &conflict_id);
        let before_files = user_files(repo.path());
        let before_file_row = active_file_snapshot(repo.path(), file_id);
        install_sync_resolution_change_log_failure(repo.path());

        let result = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id,
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::UseIncoming,
                preview_token: token,
                replace_confirmed: true,
                replace_confirmation_id: Some("replace-confirmed".to_owned()),
            },
        );

        assert!(matches!(result, Err(CoreError::Db { .. })));
        assert_eq!(user_files(repo.path()), before_files);
        assert_eq!(active_file_snapshot(repo.path(), file_id), before_file_row);
        assert_eq!(
            conflict_state(repo.path())[0].status,
            SyncConflictStatus::NeedsReview
        );
        assert_eq!(sync_resolution_change_count(repo.path()), 0);
        assert!(!trash_dir.join("report.pdf").exists());
    });
}

#[test]
fn sync_conflict_resolve_failure_recovery_rejects_stale_preview_token_read_only() {
    with_test_system_trash(|_trash_dir| {
        let (repo, conflict_id, file_id) = setup_same_name_conflict();
        let before_files = user_files(repo.path());
        let before_file_row = active_file_snapshot(repo.path(), file_id);

        let result = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id,
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::KeepBoth,
                preview_token: "stale-preview-token".to_owned(),
                replace_confirmed: false,
                replace_confirmation_id: None,
            },
        );

        assert!(matches!(result, Err(CoreError::Conflict { .. })));
        assert_eq!(user_files(repo.path()), before_files);
        assert_eq!(active_file_snapshot(repo.path(), file_id), before_file_row);
        assert_eq!(
            conflict_state(repo.path())[0].status,
            SyncConflictStatus::NeedsReview
        );
        assert_eq!(sync_resolution_change_count(repo.path()), 0);
    });
}
