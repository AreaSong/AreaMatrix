use std::{fs, path::Path};

use area_matrix_core::{
    get_latest_scan_session, init_repo, list_files, reindex_from_filesystem, repair_metadata,
    resume_scan_session, CoreError, FileFilter, FileOrigin, OverviewOutput, RepairOptions,
    RepoInitMode, RepoInitOptions, ScanSession, ScanSessionKind, ScanSessionStatus, StorageMode,
};
use pretty_assertions::assert_eq;

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

#[test]
fn repair_reindex_metadata_failure_recovery_repeated_reindex_is_idempotent() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    let docs = repo.path().join("docs");
    let spec = docs.join("spec.txt");
    fs::create_dir(&docs).expect("create docs directory");
    fs::write(&spec, "stable content\n").expect("write user document");
    let before = user_file_snapshot(&[&spec]);

    let first = reindex_from_filesystem(path_string(repo.path())).expect("run first reindex");
    assert_eq!(first.inserted, 1);
    assert_eq!(first.updated, 0);
    assert_eq!(first.errors, Vec::<String>::new());
    let first_entry = list_files(path_string(repo.path()), empty_filter())
        .expect("list first indexed files")
        .remove(0);

    let second = reindex_from_filesystem(path_string(repo.path())).expect("run repeated reindex");
    assert_eq!(second.inserted, 0);
    assert_eq!(second.updated, 0);
    assert!(second.skipped >= 1);
    assert_eq!(second.errors, Vec::<String>::new());
    assert_eq!(user_file_snapshot(&[&spec]), before);

    let second_entry = list_files(path_string(repo.path()), empty_filter())
        .expect("list repeated indexed files")
        .remove(0);
    assert_eq!(second_entry.id, first_entry.id);
    assert_eq!(second_entry.path, "docs/spec.txt");
    assert_eq!(second_entry.hash_sha256, first_entry.hash_sha256);
    assert_eq!(second_entry.origin, FileOrigin::External);
    assert_eq!(second_entry.storage_mode, StorageMode::Indexed);
}

#[test]
fn repair_reindex_metadata_failure_recovery_preserves_snapshot_when_repair_fails() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    let readme = repo.path().join("README.md");
    fs::write(&readme, "# User project\n").expect("write user README");
    let before = user_file_snapshot(&[&readme]);
    let db_path = repo.path().join(".areamatrix/index.db");
    fs::write(&db_path, b"not a sqlite database").expect("corrupt AreaMatrix metadata");

    let result = repair_metadata(
        path_string(repo.path()),
        RepairOptions {
            full_rescan: true,
            preserve_diagnostics_snapshot: true,
        },
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(user_file_snapshot(&[&readme]), before);
    let snapshots = diagnostics_snapshots(repo.path());
    assert_eq!(snapshots.len(), 1);
    assert_eq!(
        fs::read(&snapshots[0]).expect("read preserved diagnostics snapshot"),
        b"not a sqlite database"
    );
}

#[cfg(unix)]
#[test]
fn repair_reindex_metadata_failure_recovery_permission_denied_records_resumable_session() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
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

    let failed_session = assert_failed_reindex_session(repo.path());

    let indexed_before_resume = indexed_paths(repo.path());
    assert_eq!(indexed_before_resume, vec!["a-readable.txt"]);

    let report = resume_scan_session(path_string(repo.path()), failed_session.id)
        .expect("resume failed reindex session");
    assert_eq!(report.scan_session_id, Some(failed_session.id));
    assert_eq!(report.inserted, 2);
    assert_eq!(report.updated, 0);
    assert_eq!(report.errors, Vec::<String>::new());

    let resumed_session = get_latest_scan_session(path_string(repo.path()))
        .expect("read resumed reindex session")
        .expect("resumed reindex session should exist");
    assert_eq!(resumed_session.status, ScanSessionStatus::Completed);
    assert_eq!(resumed_session.last_path, Some("b-blocked.txt".to_owned()));
    assert_eq!(
        indexed_paths(repo.path()),
        vec!["a-readable.txt", "b-blocked.txt"]
    );
    assert_eq!(user_file_snapshot(&[&readable, &blocked]), before);
}

#[cfg(unix)]
fn block_file_reads(path: &Path) -> Option<fs::Permissions> {
    use std::os::unix::fs::PermissionsExt;

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

fn assert_failed_reindex_session(repo_path: &Path) -> ScanSession {
    let failed_session = get_latest_scan_session(path_string(repo_path))
        .expect("read failed reindex session")
        .expect("failed reindex session should exist");
    assert_eq!(failed_session.kind, ScanSessionKind::Reindex);
    assert_eq!(failed_session.status, ScanSessionStatus::Failed);
    assert_eq!(failed_session.last_path, Some("a-readable.txt".to_owned()));
    assert_eq!(failed_session.inserted, 1);
    assert_eq!(failed_session.errors.len(), 1);
    assert!(failed_session.errors[0].contains("b-blocked.txt"));
    assert!(failed_session.errors[0].contains("permission denied"));
    failed_session
}

fn indexed_paths(repo_path: &Path) -> Vec<String> {
    let mut paths = list_files(path_string(repo_path), empty_filter())
        .expect("list indexed files")
        .into_iter()
        .map(|file| {
            assert_eq!(file.origin, FileOrigin::External);
            assert_eq!(file.storage_mode, StorageMode::Indexed);
            file.path
        })
        .collect::<Vec<_>>();
    paths.sort();
    paths
}

fn diagnostics_snapshots(repo_path: &Path) -> Vec<std::path::PathBuf> {
    let diagnostics_dir = repo_path.join(".areamatrix/diagnostics");
    let mut snapshots = fs::read_dir(diagnostics_dir)
        .expect("read diagnostics directory")
        .map(|entry| entry.expect("read diagnostics entry").path())
        .filter(|path| path.is_file())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("index-") && name.ends_with(".db"))
        })
        .collect::<Vec<_>>();
    snapshots.sort();
    snapshots
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
