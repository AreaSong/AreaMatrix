use std::{fs, path::Path};

use area_matrix_core::{
    get_latest_scan_session, init_repo, list_files, reindex_from_filesystem, resume_scan_session,
    CoreError, ErrorKind, ErrorRecoverability, ErrorSeverity, FileFilter, OverviewOutput,
    RepoInitMode, RepoInitOptions, ScanSessionKind, ScanSessionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn empty_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn indexed_paths(repo: &Path) -> Vec<String> {
    let mut paths = list_files(path_string(repo), empty_filter())
        .expect("list indexed files")
        .into_iter()
        .map(|file| file.path)
        .collect::<Vec<_>>();
    paths.sort();
    paths
}

fn user_file_snapshot(paths: &[&Path]) -> Vec<(String, Vec<u8>)> {
    paths
        .iter()
        .map(|path| {
            (
                path.to_string_lossy().into_owned(),
                fs::read(path).expect("read user file snapshot"),
            )
        })
        .collect()
}

fn install_reindex_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_reindex_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'external_modified'
             BEGIN
               SELECT RAISE(ABORT, 'forced reindex change log failure');
             END;",
        )
        .expect("install reindex change-log failure trigger");
}

fn install_scan_session_failure_update(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_scan_session_failed_update
             BEFORE UPDATE OF status ON scan_sessions
             WHEN NEW.status = 'failed'
             BEGIN
               SELECT RAISE(ABORT, 'forced failed scan-session persistence failure');
             END;",
        )
        .expect("install scan-session failure trigger");
}

#[test]
fn manual_rescan_failure_recovery_empty_repo_returns_completed_empty_report() {
    let repo = initialized_repo();

    let report = reindex_from_filesystem(path_string(repo.path())).expect("rescan empty repo");

    assert!(report.scan_session_id.is_some());
    assert_eq!(report.inserted, 0);
    assert_eq!(report.updated, 0);
    assert_eq!(report.skipped, 0);
    assert_eq!(report.errors, Vec::<String>::new());
    assert_eq!(indexed_paths(repo.path()), Vec::<String>::new());

    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session")
        .expect("empty rescan should persist a session");
    assert_eq!(session.kind, ScanSessionKind::Reindex);
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert_eq!(Some(session.id), report.scan_session_id);
}

#[test]
fn manual_rescan_failure_recovery_rejects_invalid_and_uninitialized_paths_without_side_effects() {
    assert_eq!(
        reindex_from_filesystem("   ".to_owned()),
        Err(CoreError::invalid_path("invalid path"))
    );

    let repo = tempfile::tempdir().expect("create uninitialized repository directory");
    let readme = repo.path().join("README.md");
    fs::write(&readme, "# User project\n").expect("write user README");
    let before = user_file_snapshot(&[&readme]);

    assert_eq!(
        reindex_from_filesystem(path_string(repo.path())),
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );
    assert_eq!(user_file_snapshot(&[&readme]), before);
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn manual_rescan_failure_recovery_db_error_preserves_user_files_and_records_failed_session() {
    let repo = initialized_repo();
    let document = repo.path().join("docs/spec.txt");
    fs::create_dir_all(document.parent().expect("document should have parent"))
        .expect("create docs directory");
    fs::write(&document, "db failure content\n").expect("write user document");
    let before = user_file_snapshot(&[&document]);
    install_reindex_change_log_failure(repo.path());

    let result = reindex_from_filesystem(path_string(repo.path()));

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(user_file_snapshot(&[&document]), before);
    assert_eq!(indexed_paths(repo.path()), Vec::<String>::new());

    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read failed scan session")
        .expect("failed rescan should persist a session");
    assert_eq!(session.kind, ScanSessionKind::Reindex);
    assert_eq!(session.status, ScanSessionStatus::Failed);
    assert_eq!(session.inserted, 0);
    assert_eq!(session.updated, 0);
    assert_eq!(session.last_path, None);
    assert_eq!(session.errors.len(), 1);
    assert!(session.errors[0].contains("docs/spec.txt"));
    assert!(session.errors[0].contains("forced reindex change log failure"));
}

#[test]
fn manual_rescan_failure_recovery_db_failure_while_marking_failed_returns_original_context() {
    let repo = initialized_repo();
    let document = repo.path().join("docs/spec.txt");
    fs::create_dir_all(document.parent().expect("document should have parent"))
        .expect("create docs directory");
    fs::write(&document, "dual failure content\n").expect("write user document");
    let before = user_file_snapshot(&[&document]);
    install_reindex_change_log_failure(repo.path());
    install_scan_session_failure_update(repo.path());

    let result = reindex_from_filesystem(path_string(repo.path()));

    let message = match result {
        Err(CoreError::Db { message }) => message,
        other => panic!("expected Db error with original scan context, got {other:?}"),
    };
    assert!(message.contains("docs/spec.txt"));
    assert!(message.contains("forced reindex change log failure"));
    assert!(message.contains("forced failed scan-session persistence failure"));
    assert_eq!(user_file_snapshot(&[&document]), before);
    assert_eq!(indexed_paths(repo.path()), Vec::<String>::new());
}

#[cfg(unix)]
#[test]
fn manual_rescan_failure_recovery_permission_denied_is_resumable_without_user_file_mutation() {
    let repo = initialized_repo();
    let readable = repo.path().join("a-readable.txt");
    let blocked = repo.path().join("b-blocked.txt");
    fs::write(&readable, "readable content\n").expect("write readable user file");
    fs::write(&blocked, "blocked content\n").expect("write blocked user file");
    let before = user_file_snapshot(&[&readable, &blocked]);

    let Some(original_permissions) = block_file_reads(&blocked) else {
        return;
    };

    let result = reindex_from_filesystem(path_string(repo.path()));

    fs::set_permissions(&blocked, original_permissions).expect("restore blocked permissions");
    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert_eq!(user_file_snapshot(&[&readable, &blocked]), before);
    assert_eq!(indexed_paths(repo.path()), vec!["a-readable.txt"]);

    let failed_session = get_latest_scan_session(path_string(repo.path()))
        .expect("read failed scan session")
        .expect("failed rescan should persist a session");
    assert_eq!(failed_session.kind, ScanSessionKind::Reindex);
    assert_eq!(failed_session.status, ScanSessionStatus::Failed);
    assert_eq!(failed_session.last_path, Some("a-readable.txt".to_owned()));
    assert_eq!(failed_session.inserted, 1);
    assert_eq!(failed_session.errors.len(), 1);
    assert!(failed_session.errors[0].contains("b-blocked.txt"));

    let report = resume_scan_session(path_string(repo.path()), failed_session.id)
        .expect("resume failed manual rescan after restoring permissions");
    assert_eq!(report.scan_session_id, Some(failed_session.id));
    assert_eq!(report.errors, Vec::<String>::new());
    assert_eq!(
        indexed_paths(repo.path()),
        vec!["a-readable.txt", "b-blocked.txt"]
    );
    assert_eq!(user_file_snapshot(&[&readable, &blocked]), before);
}

#[test]
fn manual_rescan_failure_recovery_error_mapping_stays_structured() {
    let permission = CoreError::permission_denied("/repo/docs/blocked.pdf").to_error_mapping();
    assert_eq!(permission.kind, ErrorKind::PermissionDenied);
    assert_eq!(permission.severity, ErrorSeverity::High);
    assert_eq!(
        permission.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(permission.raw_context, "/repo/docs/blocked.pdf");

    let db_locked = CoreError::db("database is locked").to_error_mapping();
    assert_eq!(db_locked.kind, ErrorKind::Db);
    assert_eq!(db_locked.recoverability, ErrorRecoverability::Retryable);

    let io = CoreError::io("io error").to_error_mapping();
    assert_eq!(io.kind, ErrorKind::Io);
    assert_eq!(io.recoverability, ErrorRecoverability::Retryable);
}

#[cfg(unix)]
fn block_file_reads(path: &Path) -> Option<fs::Permissions> {
    let original_permissions = fs::metadata(path)
        .expect("read blocked file permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(path, blocked_permissions).expect("block file reads");
    if fs::read(path).is_ok() {
        fs::set_permissions(path, original_permissions).expect("restore blocked permissions");
        None
    } else {
        Some(original_permissions)
    }
}
