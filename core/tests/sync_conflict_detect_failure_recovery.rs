use std::{fs, path::Path};

use area_matrix_core::{
    detect_sync_conflicts, import_file, init_repo, CoreError, ErrorKind, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode, SyncConflictType,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection, OptionalExtension};

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

fn import_repo_file(repo: &Path, target_directory: &str, filename: &str, bytes: &[u8]) {
    let source = source_file(bytes);
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
    .expect("import repository file");
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            [key],
            |row| row.get(0),
        )
        .optional()
        .expect("query repo_config value")
}

fn active_file_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active file rows")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
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

fn insert_previous_conflict_state(repo: &Path, value: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO repo_config (key, value, updated_at)
             VALUES ('sync_conflict_state', ?1, 1)",
            params![value],
        )
        .expect("insert previous sync conflict state");
}

fn block_sync_conflict_state_writes(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER block_sync_conflict_state_insert
             BEFORE INSERT ON repo_config
             WHEN NEW.key = 'sync_conflict_state'
             BEGIN
                 SELECT RAISE(ABORT, 'blocked sync conflict state insert');
             END;
             CREATE TRIGGER block_sync_conflict_state_update
             BEFORE UPDATE OF value, updated_at ON repo_config
             WHEN NEW.key = 'sync_conflict_state'
             BEGIN
                 SELECT RAISE(ABORT, 'blocked sync conflict state update');
             END;",
        )
        .expect("install sync conflict state write blocker");
}

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) {
    let path = repo.join(relative_path);
    let parent = path.parent().expect("test file has parent directory");
    fs::create_dir_all(parent).expect("create parent directory");
    fs::write(path, bytes).expect("write repository file");
}

#[test]
fn sync_conflict_detect_failure_edge_maps_invalid_input_to_documented_io() {
    let result = detect_sync_conflicts(String::new());

    let error = result.expect_err("empty repo path should be rejected");
    assert_eq!(error.kind(), ErrorKind::Io);
    assert!(matches!(error, CoreError::Io { .. }));
}

#[test]
fn sync_conflict_detect_failure_edge_keeps_prior_state_when_db_write_fails() {
    let repo = initialized_repo();
    import_repo_file(repo.path(), "docs", "report.pdf", b"original");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );
    let previous_state = r#"[{"conflict_id":"sentinel","status":"NeedsReview"}]"#;
    insert_previous_conflict_state(repo.path(), previous_state);
    block_sync_conflict_state_writes(repo.path());
    let before_files = user_files(repo.path());
    let before_active = active_file_count(repo.path());
    let before_log = change_log_count(repo.path());

    let result = detect_sync_conflicts(path_string(repo.path()));

    let error = result.expect_err("blocked state write should fail");
    assert_eq!(error.kind(), ErrorKind::Db);
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(
        repo_config_value(repo.path(), "sync_conflict_state").as_deref(),
        Some(previous_state)
    );
    assert_eq!(user_files(repo.path()), before_files);
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);
}

#[test]
fn sync_conflict_detect_failure_edge_ambiguous_copy_returns_conflict_without_state() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/report conflicted copy.pdf", b"ambiguous");
    let before_files = user_files(repo.path());

    let result = detect_sync_conflicts(path_string(repo.path()));

    let error = result.expect_err("ambiguous conflicted copy should require review");
    assert_eq!(error.kind(), ErrorKind::Conflict);
    assert!(matches!(error, CoreError::Conflict { .. }));
    assert_eq!(repo_config_value(repo.path(), "sync_conflict_state"), None);
    assert_eq!(user_files(repo.path()), before_files);
}

#[cfg(unix)]
#[test]
fn sync_conflict_detect_failure_edge_permission_error_is_io_and_retryable() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    import_repo_file(repo.path(), "docs", "report.pdf", b"original");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );
    write_repo_file(repo.path(), "blocked/secret.pdf", b"secret");
    let before_files = user_files(repo.path());
    let before_active = active_file_count(repo.path());
    let before_log = change_log_count(repo.path());
    let blocked_dir = repo.path().join("blocked");
    let original_permissions = fs::metadata(&blocked_dir)
        .expect("read blocked directory permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&blocked_dir, blocked_permissions)
        .expect("remove blocked directory permissions");

    if fs::read_dir(&blocked_dir).is_ok() {
        fs::set_permissions(&blocked_dir, original_permissions)
            .expect("restore blocked directory permissions");
        return;
    }

    let result = detect_sync_conflicts(path_string(repo.path()));
    fs::set_permissions(&blocked_dir, original_permissions)
        .expect("restore blocked directory permissions");

    let error = result.expect_err("blocked directory should fail metadata inspection");
    assert_eq!(error.kind(), ErrorKind::Io);
    assert_eq!(user_files(repo.path()), before_files);
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);

    let retry =
        detect_sync_conflicts(path_string(repo.path())).expect("retry after permission fix");
    assert_eq!(retry.len(), 1);
    assert_eq!(
        retry[0].conflict_type,
        SyncConflictType::SameNameDifferentContent
    );
}
