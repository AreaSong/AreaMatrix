use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, recover_on_startup, CoreError, FileOrigin, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
#[cfg(unix)]
use std::os::unix::fs as unix_fs;

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

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn count_rows(repo: &Path, status: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = ?1",
            [status],
            |row| row.get(0),
        )
        .expect("count rows by status")
}

fn insert_file_row(repo: &Path, relative_path: &str, status: &str) -> i64 {
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, ?4, ?5, ?6, ?7, NULL,
                1, 1, ?8
             )",
            params![
                relative_path,
                file_name(relative_path),
                "finance",
                12_i64,
                format!("hash-{relative_path}"),
                storage_mode_value(&StorageMode::Copied),
                origin_value(&FileOrigin::Imported),
                status,
            ],
        )
        .expect("insert file row");
    connection.last_insert_rowid()
}

fn file_name(path: &str) -> String {
    Path::new(path)
        .file_name()
        .and_then(|value| value.to_str())
        .expect("path should have a UTF-8 file name")
        .to_owned()
}

fn storage_mode_value(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

fn origin_value(origin: &FileOrigin) -> &'static str {
    match origin {
        FileOrigin::Imported => "imported",
        FileOrigin::Adopted => "adopted",
        FileOrigin::External => "external",
    }
}

fn staging_path(repo: &Path, name: &str) -> PathBuf {
    repo.join(".areamatrix/staging").join(name)
}

#[test]
fn recover_on_startup_implementation_cleans_staging_row_and_preserves_active_file() {
    let repo = initialized_repo();
    let active_path = repo.path().join("finance/active.pdf");
    fs::create_dir_all(active_path.parent().expect("active file has parent"))
        .expect("create active category directory");
    fs::write(&active_path, b"active bytes").expect("write active file");
    insert_file_row(repo.path(), "finance/active.pdf", "active");

    let staged = staging_path(repo.path(), "import-crash");
    fs::write(&staged, b"staged bytes").expect("write staged crash residue");
    insert_file_row(repo.path(), ".areamatrix/staging/import-crash", "staging");

    let report =
        recover_on_startup(path_string(repo.path())).expect("recover startup staging residue");

    assert_eq!(report.cleaned_staging_files, 1);
    assert_eq!(report.reverted_staging_db_rows, 1);
    assert!(report.warnings.is_empty());
    assert!(!staged.exists());
    assert_eq!(
        fs::read(&active_path).expect("active file should remain readable"),
        b"active bytes"
    );
    assert_eq!(count_rows(repo.path(), "active"), 1);
    assert_eq!(count_rows(repo.path(), "staging"), 0);
}

#[test]
fn recover_on_startup_implementation_removes_orphan_staging_file() {
    let repo = initialized_repo();
    let orphan = staging_path(repo.path(), "orphan");
    fs::write(&orphan, b"orphan bytes").expect("write orphan staging file");

    let report = recover_on_startup(path_string(repo.path())).expect("recover orphan staging file");

    assert_eq!(report.cleaned_staging_files, 1);
    assert_eq!(report.reverted_staging_db_rows, 0);
    assert!(report.warnings.is_empty());
    assert!(!orphan.exists());
    assert_eq!(count_rows(repo.path(), "staging"), 0);
}

#[cfg(unix)]
#[test]
fn recover_on_startup_implementation_rejects_staging_directory_symlink_without_deleting_target() {
    let repo = initialized_repo();
    let external = tempfile::tempdir().expect("create external user directory");
    let user_file = external.path().join("user-owned.txt");
    fs::write(&user_file, b"user bytes").expect("write external user file");

    let staging_dir = repo.path().join(".areamatrix/staging");
    fs::remove_dir(&staging_dir).expect("remove real staging directory");
    unix_fs::symlink(external.path(), &staging_dir).expect("replace staging with symlink");
    insert_file_row(repo.path(), ".areamatrix/staging/user-owned.txt", "staging");

    let result = recover_on_startup(path_string(repo.path()));

    assert_eq!(result, Err(CoreError::Io));
    assert_eq!(
        fs::read(&user_file).expect("external user file must remain readable"),
        b"user bytes"
    );
    assert!(fs::symlink_metadata(&staging_dir)
        .expect("staging symlink should remain inspectable")
        .file_type()
        .is_symlink());
    assert_eq!(count_rows(repo.path(), "staging"), 1);
}

#[cfg(unix)]
#[test]
fn recover_on_startup_implementation_does_not_follow_nested_staging_symlink_parent() {
    let repo = initialized_repo();
    let external = tempfile::tempdir().expect("create external user directory");
    let user_file = external.path().join("user-owned.txt");
    fs::write(&user_file, b"user bytes").expect("write external user file");

    let symlink_parent = staging_path(repo.path(), "linked-parent");
    unix_fs::symlink(external.path(), &symlink_parent).expect("create staging child symlink");
    insert_file_row(
        repo.path(),
        ".areamatrix/staging/linked-parent/user-owned.txt",
        "staging",
    );

    let report = recover_on_startup(path_string(repo.path()))
        .expect("recover should skip unsafe nested symlink target");

    assert_eq!(report.cleaned_staging_files, 1);
    assert_eq!(report.reverted_staging_db_rows, 1);
    assert_eq!(
        fs::read(&user_file).expect("external user file must remain readable"),
        b"user bytes"
    );
    assert!(
        report.warnings[0].contains("parent")
            && report.warnings[0].contains("is not an owned staging directory")
    );
    assert!(!symlink_parent.exists());
    assert_eq!(count_rows(repo.path(), "staging"), 0);
}

#[test]
fn recover_on_startup_implementation_reverts_missing_staging_row() {
    let repo = initialized_repo();
    insert_file_row(repo.path(), ".areamatrix/staging/missing", "staging");

    let report = recover_on_startup(path_string(repo.path())).expect("recover missing staging row");

    assert_eq!(report.cleaned_staging_files, 0);
    assert_eq!(report.reverted_staging_db_rows, 1);
    assert!(report.warnings.is_empty());
    assert_eq!(count_rows(repo.path(), "staging"), 0);
}

#[test]
fn recover_on_startup_implementation_is_idempotent_after_cleanup() {
    let repo = initialized_repo();
    let orphan = staging_path(repo.path(), "orphan");
    fs::write(&orphan, b"orphan bytes").expect("write orphan staging file");
    recover_on_startup(path_string(repo.path())).expect("first recovery");

    let report = recover_on_startup(path_string(repo.path())).expect("second recovery");

    assert_eq!(report.cleaned_staging_files, 0);
    assert_eq!(report.reverted_staging_db_rows, 0);
    assert!(report.warnings.is_empty());
    assert_eq!(count_rows(repo.path(), "staging"), 0);
}

#[test]
fn recover_on_startup_implementation_preserves_non_staging_row_path() {
    let repo = initialized_repo();
    let final_path = repo.path().join("finance/not-staging.pdf");
    fs::create_dir_all(final_path.parent().expect("final file has parent"))
        .expect("create final directory");
    fs::write(&final_path, b"user final bytes").expect("write final user file");
    let row_id = insert_file_row(repo.path(), "finance/not-staging.pdf", "staging");

    let report =
        recover_on_startup(path_string(repo.path())).expect("recover malformed staging row");

    assert_eq!(report.cleaned_staging_files, 0);
    assert_eq!(report.reverted_staging_db_rows, 1);
    assert_eq!(
        report.warnings,
        vec![format!(
            "Skipped filesystem cleanup for non-staging row {row_id} at finance/not-staging.pdf"
        )]
    );
    assert_eq!(
        fs::read(&final_path).expect("final file should not be deleted"),
        b"user final bytes"
    );
    assert_eq!(count_rows(repo.path(), "staging"), 0);
}

#[test]
fn recover_on_startup_implementation_uninitialized_repo_does_not_create_metadata() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");

    let result = recover_on_startup(path_string(repo.path()));

    assert_eq!(result, Err(CoreError::RepoNotInitialized));
    assert!(!repo.path().join(".areamatrix").exists());
}
