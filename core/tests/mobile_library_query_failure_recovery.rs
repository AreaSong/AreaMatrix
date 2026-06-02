use std::{fs, path::Path};

use area_matrix_core::{
    get_file, init_repo, list_changes, list_files, list_tree_json, map_core_error, ChangeFilter,
    CoreError, ErrorKind, ErrorMappingInput, ErrorRecoverability, FileFilter, OverviewOutput,
    RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde_json::Value;

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

fn default_file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 50,
        offset: 0,
    }
}

fn default_change_filter() -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 50,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn write_repo_file(repo: &Path, relative_path: &str, content: &[u8]) {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create fixture parent directory");
    }
    fs::write(path, content).expect("write user fixture file");
}

fn insert_active_file(repo: &Path, path: &str, imported_at: i64) -> i64 {
    let current_name = path.rsplit('/').next().expect("test path has filename");
    write_repo_file(repo, path, format!("content-{imported_at}").as_bytes());
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'docs', 1,
                ?3, 'copied', 'imported', NULL,
                ?4, ?4, 'active'
             )",
            params![
                path,
                current_name,
                format!("{imported_at:064x}"),
                imported_at
            ],
        )
        .expect("insert active file row");
    connection.last_insert_rowid()
}

fn insert_change(repo: &Path, file_id: i64, detail_json: &str, occurred_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, 'imported', ?2, ?3)",
            params![file_id, detail_json, occurred_at],
        )
        .expect("insert change-log row");
}

fn metadata_counts(repo: &Path) -> (i64, i64) {
    let connection = open_db(repo);
    let files = connection
        .query_row("SELECT COUNT(*) FROM files", [], |row| row.get(0))
        .expect("count files");
    let changes = connection
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count changes");
    (files, changes)
}

fn relative_directory_entries(repo: &Path, dir: &Path) -> Vec<String> {
    if !dir.exists() {
        return Vec::new();
    }
    let mut entries = fs::read_dir(dir)
        .expect("read directory entries")
        .map(|entry| {
            let path = entry.expect("read directory entry").path();
            path.strip_prefix(repo)
                .expect("entry is inside repo")
                .to_string_lossy()
                .into_owned()
        })
        .collect::<Vec<_>>();
    entries.sort();
    entries
}

fn assert_db_error(error: CoreError) -> CoreError {
    assert!(
        matches!(error, CoreError::Db { .. }),
        "expected CoreError::Db, got {error:?}"
    );
    error
}

fn assert_metadata_dirs_unchanged(
    repo: &Path,
    before_staging: &[String],
    before_generated: &[String],
) {
    assert_eq!(
        relative_directory_entries(repo, &repo.join(".areamatrix/staging")),
        before_staging
    );
    assert_eq!(
        relative_directory_entries(repo, &repo.join(".areamatrix/generated")),
        before_generated
    );
}

#[test]
fn mobile_library_query_failure_empty_repo_returns_empty_pages_without_writes() {
    let repo = initialized_repo();
    let before_counts = metadata_counts(repo.path());

    let files = list_files(path_string(repo.path()), default_file_filter())
        .expect("list empty mobile library");
    let changes = list_changes(path_string(repo.path()), default_change_filter())
        .expect("list empty mobile changes");
    let tree_json =
        list_tree_json(path_string(repo.path()), "en".to_owned()).expect("list empty tree");

    let tree = serde_json::from_str::<Value>(&tree_json).expect("parse empty tree");
    assert_eq!(files, Vec::new());
    assert_eq!(changes, Vec::new());
    assert_eq!(tree["file_count"], 0);
    assert_eq!(
        tree["children"].as_array().expect("children array").len(),
        0
    );
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert!(
        relative_directory_entries(repo.path(), &repo.path().join(".areamatrix/staging"))
            .is_empty()
    );
}

#[test]
fn mobile_library_query_failure_invalid_inputs_are_explicit_and_non_mutating() {
    let repo = initialized_repo();
    let file_id = insert_active_file(repo.path(), "docs/report.pdf", 100);
    insert_change(repo.path(), file_id, r#"{"source":"failure-edge"}"#, 100);
    let before_counts = metadata_counts(repo.path());
    let before_file = fs::read(repo.path().join("docs/report.pdf")).expect("read user file");

    let mut invalid_file_filter = default_file_filter();
    invalid_file_filter.imported_after = Some(200);
    invalid_file_filter.imported_before = Some(100);
    let file_error = list_files(path_string(repo.path()), invalid_file_filter)
        .expect_err("reversed file time range must fail");

    let mut invalid_change_filter = default_change_filter();
    invalid_change_filter.file_id = Some(0);
    let change_error = list_changes(path_string(repo.path()), invalid_change_filter)
        .expect_err("non-positive file id must fail");

    let missing_file_error =
        get_file(path_string(repo.path()), 404).expect_err("missing id must fail");

    assert_db_error(file_error);
    assert_db_error(change_error);
    assert!(matches!(missing_file_error, CoreError::FileNotFound { .. }));
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert_eq!(
        fs::read(repo.path().join("docs/report.pdf")).expect("read user file after failures"),
        before_file
    );
}

#[test]
fn mobile_library_query_failure_uninitialized_repo_is_structured_and_creates_no_metadata() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");
    write_repo_file(repo.path(), "README.md", b"user readme");
    let before_readme = fs::read(repo.path().join("README.md")).expect("read README before query");

    let errors = [
        list_files(path_string(repo.path()), default_file_filter())
            .expect_err("list_files must require metadata"),
        get_file(path_string(repo.path()), 1).expect_err("get_file must require metadata"),
        list_changes(path_string(repo.path()), default_change_filter())
            .expect_err("list_changes must require metadata"),
        list_tree_json(path_string(repo.path()), "en".to_owned())
            .expect_err("list_tree_json must require metadata"),
    ];

    for error in errors {
        let mapping = error.to_error_mapping();
        assert_eq!(mapping.kind, ErrorKind::RepoNotInitialized);
        assert_eq!(
            mapping.recoverability,
            ErrorRecoverability::UserActionRequired
        );
        assert!(!mapping.user_message.is_empty());
    }
    assert_eq!(
        fs::read(repo.path().join("README.md")).expect("read README after query"),
        before_readme
    );
    assert!(!repo.path().join(".areamatrix").exists());
}

#[test]
fn mobile_library_query_failure_corrupted_metadata_is_fatal_without_half_products() {
    let repo = tempfile::tempdir().expect("create corrupted repository directory");
    let user_file = repo.path().join("docs/client.pdf");
    fs::create_dir_all(user_file.parent().expect("fixture has parent")).expect("create docs dir");
    fs::write(&user_file, b"user file bytes").expect("write user file");
    let metadata = repo.path().join(".areamatrix");
    fs::create_dir(&metadata).expect("create metadata directory");
    fs::create_dir(metadata.join("staging")).expect("create staging directory");
    fs::create_dir(metadata.join("generated")).expect("create generated directory");
    fs::write(metadata.join("index.db"), b"not a sqlite database")
        .expect("write corrupted database fixture");

    let error = list_files(path_string(repo.path()), default_file_filter())
        .expect_err("corrupted DB must fail explicitly");
    let mapping = assert_db_error(error).to_error_mapping();

    assert_eq!(mapping.kind, ErrorKind::Db);
    assert_eq!(mapping.recoverability, ErrorRecoverability::Fatal);
    assert_eq!(
        fs::read(user_file).expect("read user file after corrupted query"),
        b"user file bytes"
    );
    assert!(relative_directory_entries(repo.path(), &metadata.join("staging")).is_empty());
    assert!(relative_directory_entries(repo.path(), &metadata.join("generated")).is_empty());
}

#[cfg(unix)]
#[test]
fn mobile_library_query_failure_permission_denied_is_explicit_and_non_mutating() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let file_id = insert_active_file(repo.path(), "docs/secret.pdf", 100);
    insert_change(repo.path(), file_id, r#"{"source":"permission-edge"}"#, 100);
    let metadata_dir = repo.path().join(".areamatrix");
    let original_permissions = fs::metadata(&metadata_dir)
        .expect("read metadata directory permissions")
        .permissions();
    let before_counts = metadata_counts(repo.path());
    let before_file = fs::read(repo.path().join("docs/secret.pdf")).expect("read user file");
    let before_staging = relative_directory_entries(repo.path(), &metadata_dir.join("staging"));
    let before_generated = relative_directory_entries(repo.path(), &metadata_dir.join("generated"));

    let mut denied_permissions = original_permissions.clone();
    denied_permissions.set_mode(0o000);
    fs::set_permissions(&metadata_dir, denied_permissions)
        .expect("remove metadata directory permissions");

    let result = list_files(path_string(repo.path()), default_file_filter());

    fs::set_permissions(&metadata_dir, original_permissions)
        .expect("restore metadata directory permissions");

    let error = result.expect_err("metadata permission denial must fail explicitly");
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, ErrorKind::PermissionDenied);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert_eq!(
        fs::read(repo.path().join("docs/secret.pdf"))
            .expect("read user file after permission error"),
        before_file
    );
    assert_metadata_dirs_unchanged(repo.path(), &before_staging, &before_generated);
}

#[test]
fn mobile_library_query_failure_tree_io_error_is_explicit_and_non_mutating() {
    let repo = initialized_repo();
    insert_active_file(repo.path(), "docs/io.pdf", 100);
    let metadata_dir = repo.path().join(".areamatrix");
    let classifier_path = metadata_dir.join("classifier.yaml");
    if classifier_path.exists() {
        fs::remove_file(&classifier_path).expect("remove classifier fixture file");
    }
    fs::create_dir(&classifier_path).expect("create unreadable classifier fixture");
    let before_counts = metadata_counts(repo.path());
    let before_file = fs::read(repo.path().join("docs/io.pdf")).expect("read user file");
    let before_staging = relative_directory_entries(repo.path(), &metadata_dir.join("staging"));
    let before_generated = relative_directory_entries(repo.path(), &metadata_dir.join("generated"));

    let error = list_tree_json(path_string(repo.path()), "en".to_owned())
        .expect_err("tree classifier IO failure must not be silently defaulted");
    let mapping = error.to_error_mapping();

    assert_eq!(mapping.kind, ErrorKind::Io);
    assert_eq!(mapping.recoverability, ErrorRecoverability::Retryable);
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert_eq!(
        fs::read(repo.path().join("docs/io.pdf")).expect("read user file after IO error"),
        before_file
    );
    assert_metadata_dirs_unchanged(repo.path(), &before_staging, &before_generated);
}

#[test]
fn mobile_library_query_failure_metadata_corruption_and_bad_details_do_not_silent_default() {
    let repo = initialized_repo();
    insert_active_file(repo.path(), "docs/report.pdf", 100);

    open_db(repo.path())
        .execute_batch("DROP TABLE files;")
        .expect("drop files table to simulate metadata corruption");
    let file_error = list_files(path_string(repo.path()), default_file_filter())
        .expect_err("schema corruption must not be silently defaulted");
    assert_db_error(file_error);
    assert!(repo.path().join("docs/report.pdf").exists());

    let repo = initialized_repo();
    let file_id = insert_active_file(repo.path(), "docs/bad-log.pdf", 200);
    let before_counts = metadata_counts(repo.path());

    insert_change(repo.path(), file_id, "not-json", 200);
    let change_error = list_changes(path_string(repo.path()), default_change_filter())
        .expect_err("invalid detail_json must not be silently skipped");

    assert_db_error(change_error);
    assert_eq!(
        metadata_counts(repo.path()),
        (before_counts.0, before_counts.1 + 1)
    );
    assert!(repo.path().join("docs/bad-log.pdf").exists());
}

#[test]
fn mobile_library_query_failure_error_mapping_keeps_mobile_recovery_actions_structured() {
    let cases = [
        (
            ErrorMappingInput {
                kind: ErrorKind::RepoNotInitialized,
                path: Some("/repo".to_owned()),
                reason: None,
                message: None,
            },
            ErrorKind::RepoNotInitialized,
            ErrorRecoverability::UserActionRequired,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::FileNotFound,
                path: Some("docs/missing.pdf".to_owned()),
                reason: None,
                message: None,
            },
            ErrorKind::FileNotFound,
            ErrorRecoverability::RefreshRequired,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::Io,
                path: None,
                reason: None,
                message: Some("io error".to_owned()),
            },
            ErrorKind::Io,
            ErrorRecoverability::Retryable,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::Db,
                path: None,
                reason: None,
                message: Some("database is locked".to_owned()),
            },
            ErrorKind::Db,
            ErrorRecoverability::Retryable,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::Db,
                path: None,
                reason: None,
                message: Some("file is not a database".to_owned()),
            },
            ErrorKind::Db,
            ErrorRecoverability::Fatal,
        ),
        (
            ErrorMappingInput {
                kind: ErrorKind::PermissionDenied,
                path: Some("/repo/.areamatrix".to_owned()),
                reason: None,
                message: None,
            },
            ErrorKind::PermissionDenied,
            ErrorRecoverability::UserActionRequired,
        ),
    ];

    for (input, expected_kind, expected_recoverability) in cases {
        let mapping = map_core_error(input);
        assert_eq!(mapping.kind, expected_kind);
        assert_eq!(mapping.recoverability, expected_recoverability);
        assert!(!mapping.suggested_action.is_empty());
        assert!(!mapping.raw_context.is_empty());
    }
}
