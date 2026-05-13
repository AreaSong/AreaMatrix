use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_icloud_conflicts, CoreError, ICloudConflictStatus, OverviewOutput,
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

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) -> PathBuf {
    let path = repo.join(relative_path);
    let parent = path.parent().expect("test file has parent directory");
    fs::create_dir_all(parent).expect("create parent directory");
    fs::write(&path, bytes).expect("write repository file");
    path
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
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

fn conflict_paths(repo: &Path) -> Vec<String> {
    let mut paths = list_icloud_conflicts(path_string(repo))
        .expect("list iCloud conflicts")
        .into_iter()
        .map(|conflict| conflict.conflicted_copy_path)
        .collect::<Vec<_>>();
    paths.sort();
    paths
}

#[test]
fn list_icloud_conflicts_failure_recovery_repeated_scans_are_idempotent_and_read_only() {
    let repo = initialized_repo();
    let original = write_repo_file(repo.path(), "docs/report.pdf", b"original");
    let conflicted = write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );

    let before_active = active_file_count(repo.path());
    let before_log = change_log_count(repo.path());
    let first = list_icloud_conflicts(path_string(repo.path())).expect("first list conflicts");
    let second = list_icloud_conflicts(path_string(repo.path())).expect("second list conflicts");

    assert_eq!(first, second);
    assert_eq!(first.len(), 1);
    assert_eq!(first[0].status, ICloudConflictStatus::NeedsReview);
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);
    assert_eq!(
        fs::read(&original).expect("read original after repeated scans"),
        b"original"
    );
    assert_eq!(
        fs::read(&conflicted).expect("read conflicted copy after repeated scans"),
        b"conflicted"
    );
}

#[test]
fn list_icloud_conflicts_failure_recovery_placeholder_error_keeps_files_and_retries() {
    let repo = initialized_repo();
    let original = write_repo_file(repo.path(), "docs/report.pdf", b"original");
    let placeholder = write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf.icloud",
        b"placeholder marker",
    );

    let before_active = active_file_count(repo.path());
    let before_log = change_log_count(repo.path());
    let result = list_icloud_conflicts(path_string(repo.path()));

    assert!(matches!(result, Err(CoreError::ICloudPlaceholder { .. })));
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);
    assert_eq!(
        fs::read(&original).expect("read original after placeholder failure"),
        b"original"
    );
    assert_eq!(
        fs::read(&placeholder).expect("read placeholder marker after failure"),
        b"placeholder marker"
    );

    fs::remove_file(&placeholder).expect("remove test placeholder before retry");
    let conflicted = write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );
    let conflicts = list_icloud_conflicts(path_string(repo.path())).expect("retry list conflicts");

    assert_eq!(conflicts.len(), 1);
    assert_eq!(
        conflicts[0].conflicted_copy_path,
        "docs/report (Alice's conflicted copy).pdf"
    );
    assert_eq!(
        fs::read(&conflicted).expect("read conflicted copy after retry"),
        b"conflicted"
    );
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);
}

#[test]
fn list_icloud_conflicts_failure_recovery_repo_placeholder_path_is_rejected_before_scan() {
    let parent = tempfile::tempdir().expect("create temporary parent directory");
    let repo = parent.path().join("Library.icloud");
    fs::create_dir(&repo).expect("create placeholder-shaped repository path");

    let result = list_icloud_conflicts(path_string(&repo));

    assert!(matches!(result, Err(CoreError::ICloudPlaceholder { .. })));
}

#[cfg(unix)]
#[test]
fn list_icloud_conflicts_failure_recovery_permission_denied_keeps_state_and_retries() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let accessible_original = write_repo_file(repo.path(), "docs/report.pdf", b"original");
    let accessible_conflict = write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );
    let blocked_original = write_repo_file(repo.path(), "blocked/secret.pdf", b"secret");
    let blocked_conflict = write_repo_file(
        repo.path(),
        "blocked/secret (Alice's conflicted copy).pdf",
        b"blocked conflict",
    );
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

    let before_active = active_file_count(repo.path());
    let before_log = change_log_count(repo.path());
    let result = list_icloud_conflicts(path_string(repo.path()));

    fs::set_permissions(&blocked_dir, original_permissions)
        .expect("restore blocked directory permissions");

    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);
    assert_eq!(
        fs::read(&accessible_original).expect("read accessible original after failure"),
        b"original"
    );
    assert_eq!(
        fs::read(&accessible_conflict).expect("read accessible conflict after failure"),
        b"conflicted"
    );
    assert_eq!(
        fs::read(&blocked_original).expect("read blocked original after permission restore"),
        b"secret"
    );
    assert_eq!(
        fs::read(&blocked_conflict).expect("read blocked conflict after permission restore"),
        b"blocked conflict"
    );
    assert_eq!(
        conflict_paths(repo.path()),
        vec![
            "blocked/secret (Alice's conflicted copy).pdf",
            "docs/report (Alice's conflicted copy).pdf",
        ]
    );
}
