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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
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

fn count_rows(repo: &Path, status: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = ?1",
            [status],
            |row| row.get(0),
        )
        .expect("count rows by status")
}

fn staging_path(repo: &Path, name: &str) -> PathBuf {
    repo.join(".areamatrix/staging").join(name)
}

fn remove_if_exists(path: PathBuf) {
    if path.exists() {
        fs::remove_file(path).expect("remove sqlite sidecar");
    }
}

#[test]
fn recover_on_startup_validation_proves_report_db_and_filesystem_cleanup() {
    let repo = initialized_repo();
    let active_path = repo.path().join("finance/active.pdf");
    fs::create_dir_all(active_path.parent().expect("active file has parent"))
        .expect("create active category directory");
    fs::write(&active_path, b"user active bytes").expect("write active user file");
    insert_file_row(repo.path(), "finance/active.pdf", "active");

    let staged = staging_path(repo.path(), "interrupted-import");
    let orphan = staging_path(repo.path(), "orphan-staging-file");
    fs::write(&staged, b"staged bytes").expect("write interrupted staging file");
    fs::write(&orphan, b"orphan bytes").expect("write orphan staging file");
    insert_file_row(
        repo.path(),
        ".areamatrix/staging/interrupted-import",
        "staging",
    );

    let report =
        recover_on_startup(path_string(repo.path())).expect("recover startup staging residue");

    assert_eq!(report.cleaned_staging_files, 2);
    assert_eq!(report.reverted_staging_db_rows, 1);
    assert!(report.warnings.is_empty());
    assert!(!staged.exists());
    assert!(!orphan.exists());
    assert_eq!(
        fs::read(&active_path).expect("active user file must remain readable"),
        b"user active bytes"
    );
    assert_eq!(count_rows(repo.path(), "active"), 1);
    assert_eq!(count_rows(repo.path(), "staging"), 0);
}

#[test]
fn recover_on_startup_validation_requires_initialized_repo_without_metadata_side_effects() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");

    let result = recover_on_startup(path_string(repo.path()));

    assert_eq!(result, Err(CoreError::RepoNotInitialized));
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn recover_on_startup_validation_db_error_keeps_staging_retryable() {
    let repo = initialized_repo();
    let orphan = staging_path(repo.path(), "retry-after-db-repair");
    fs::write(&orphan, b"retryable staging bytes").expect("write retryable staging file");
    fs::write(repo.path().join(".areamatrix/index.db"), b"not sqlite")
        .expect("corrupt repository database fixture");
    remove_if_exists(repo.path().join(".areamatrix/index.db-wal"));
    remove_if_exists(repo.path().join(".areamatrix/index.db-shm"));

    let result = recover_on_startup(path_string(repo.path()));

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(
        fs::read(&orphan).expect("staging file should remain retryable after DB error"),
        b"retryable staging bytes"
    );
}
