use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_missing_file_state, init_repo, relink_missing_file, remove_missing_file_record, CoreError,
    ErrorKind, MissingFileRecoveryStatus, MissingFileRelinkRequest, MissingFileRemoveRecordRequest,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use sha2::{Digest, Sha256};

#[derive(Debug, Eq, PartialEq)]
struct RecoverySnapshot {
    files: Vec<(i64, String, String, i64, String, Option<String>)>,
    change_log_count: i64,
    staging_entries: Vec<String>,
    generated_entries: Vec<String>,
    user_visible_paths: Vec<String>,
}

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

fn sha256_hex(content: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content);
    format!("{:x}", hasher.finalize())
}

fn insert_missing_repo_file(repo: &Path, relative_path: &str, content: &[u8]) -> i64 {
    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture path has file name");
    let category = relative_path
        .split_once('/')
        .map(|(category, _)| category)
        .unwrap_or("__root__");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, ?4,
                ?5, 'copied', 'imported', ?6,
                100, 200, 'active'
             )",
            params![
                relative_path,
                current_name,
                category,
                content.len() as i64,
                sha256_hex(content),
                Option::<&str>::None,
            ],
        )
        .expect("insert missing file row");
    connection.last_insert_rowid()
}

fn write_repo_file(repo: &Path, relative_path: &str, content: &[u8]) -> PathBuf {
    let path = repo.join(relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create fixture parent directory");
    }
    fs::write(&path, content).expect("write fixture file");
    path
}

fn snapshot(repo: &Path) -> RecoverySnapshot {
    RecoverySnapshot {
        files: file_rows(repo),
        change_log_count: table_count(repo, "change_log"),
        staging_entries: relative_entries(repo, &repo.join(".areamatrix/staging")),
        generated_entries: relative_entries(repo, &repo.join(".areamatrix/generated")),
        user_visible_paths: user_visible_paths(repo),
    }
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, i64, String, Option<String>)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT id, path, current_name, size_bytes, status, source_path
             FROM files ORDER BY id",
        )
        .expect("prepare file rows query");
    statement
        .query_map([], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
            ))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn table_count(repo: &Path, table: &str) -> i64 {
    let query = format!("SELECT COUNT(*) FROM {table}");
    open_db(repo)
        .query_row(&query, [], |row| row.get(0))
        .expect("count table rows")
}

fn relative_entries(repo: &Path, root: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    if root.exists() {
        collect_visible_paths(repo, root, &mut entries, false);
    }
    entries.sort();
    entries
}

fn user_visible_paths(repo: &Path) -> Vec<String> {
    let mut paths = Vec::new();
    collect_visible_paths(repo, repo, &mut paths, true);
    paths.sort();
    paths
}

fn collect_visible_paths(repo: &Path, current: &Path, paths: &mut Vec<String>, skip_meta: bool) {
    for entry in fs::read_dir(current).expect("read directory") {
        let entry = entry.expect("read directory entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("path is inside repository")
            .to_string_lossy()
            .into_owned();
        if skip_meta && (relative == ".areamatrix" || relative.starts_with(".areamatrix/")) {
            continue;
        }
        paths.push(relative);
        if path.is_dir() {
            collect_visible_paths(repo, &path, paths, skip_meta);
        }
    }
}

fn table_exists(repo: &Path, table: &str) -> bool {
    open_db(repo)
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            [table],
            |_| Ok(()),
        )
        .is_ok()
}

fn install_change_log_failure(repo: &Path, action: &str) {
    open_db(repo)
        .execute_batch(&format!(
            "CREATE TRIGGER fail_missing_recovery_{action}
             BEFORE INSERT ON change_log
             WHEN NEW.action = '{action}'
             BEGIN
               SELECT RAISE(ABORT, 'forced missing-file recovery change-log failure');
             END;"
        ))
        .expect("install missing-file recovery change-log failure trigger");
}

fn assert_file_not_found(error: CoreError) {
    assert!(matches!(error, CoreError::FileNotFound { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::FileNotFound);
}

fn assert_permission_denied(error: CoreError) {
    assert!(matches!(error, CoreError::PermissionDenied { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::PermissionDenied);
}

fn assert_db_error(error: CoreError) {
    assert!(matches!(error, CoreError::Db { .. }));
    assert_eq!(error.to_error_mapping().kind, ErrorKind::Db);
}

#[test]
fn missing_file_recovery_failure_empty_state_and_invalid_inputs_are_explicit() {
    let repo = initialized_repo();
    let before = snapshot(repo.path());

    assert_file_not_found(
        get_missing_file_state(path_string(repo.path()), 99)
            .expect_err("empty repository has no missing record"),
    );
    assert_file_not_found(
        get_missing_file_state(path_string(repo.path()), 0)
            .expect_err("invalid file id is rejected before DB lookup"),
    );
    assert_file_not_found(
        relink_missing_file(
            path_string(repo.path()),
            MissingFileRelinkRequest {
                file_id: 0,
                new_path: path_string(&repo.path().join("docs/restored.pdf")),
                confirmed: true,
            },
        )
        .expect_err("invalid relink file id is explicit"),
    );
    assert_file_not_found(
        relink_missing_file(
            path_string(repo.path()),
            MissingFileRelinkRequest {
                file_id: 1,
                new_path: String::new(),
                confirmed: true,
            },
        )
        .expect_err("empty relink path is explicit"),
    );
    assert_file_not_found(
        remove_missing_file_record(
            path_string(repo.path()),
            MissingFileRemoveRecordRequest {
                file_id: 0,
                confirmed: true,
            },
        )
        .expect_err("invalid remove-record file id is explicit"),
    );
    assert_db_error(
        get_missing_file_state(String::new(), 1)
            .expect_err("empty repository path maps to documented metadata error"),
    );

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn missing_file_recovery_failure_unconfirmed_actions_do_not_read_or_mutate_metadata() {
    let repo = initialized_repo();
    let file_id = insert_missing_repo_file(repo.path(), "docs/missing.pdf", b"missing");
    let before = snapshot(repo.path());

    assert_permission_denied(
        remove_missing_file_record(
            path_string(repo.path()),
            MissingFileRemoveRecordRequest {
                file_id,
                confirmed: false,
            },
        )
        .expect_err("remove record requires explicit confirmation"),
    );
    assert_permission_denied(
        relink_missing_file(
            path_string(repo.path()),
            MissingFileRelinkRequest {
                file_id,
                new_path: path_string(&repo.path().join("docs/restored.pdf")),
                confirmed: false,
            },
        )
        .expect_err("relink requires explicit confirmation"),
    );

    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn missing_file_recovery_failure_hash_mismatch_keeps_record_and_candidate_unchanged() {
    let repo = initialized_repo();
    let file_id = insert_missing_repo_file(repo.path(), "docs/missing.pdf", b"original");
    let candidate = write_repo_file(repo.path(), "docs/wrong.pdf", b"different");
    let before = snapshot(repo.path());

    let report = relink_missing_file(
        path_string(repo.path()),
        MissingFileRelinkRequest {
            file_id,
            new_path: path_string(&candidate),
            confirmed: true,
        },
    )
    .expect("hash mismatch is a user-visible report");

    assert_eq!(report.status, MissingFileRecoveryStatus::HashMismatch);
    assert!(!report.hash_matched);
    assert!(!report.record_removed);
    assert!(!report.file_deleted);
    assert_eq!(report.change_log_action, None);
    assert_eq!(
        fs::read(&candidate).expect("read candidate after hash mismatch"),
        b"different"
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn missing_file_recovery_failure_relink_db_error_rolls_back_metadata_without_half_products() {
    let repo = initialized_repo();
    let content = b"restored report";
    let file_id = insert_missing_repo_file(repo.path(), "docs/missing.pdf", content);
    let candidate = write_repo_file(repo.path(), "docs/restored.pdf", content);
    let before = snapshot(repo.path());
    install_change_log_failure(repo.path(), "external_modified");

    let error = relink_missing_file(
        path_string(repo.path()),
        MissingFileRelinkRequest {
            file_id,
            new_path: path_string(&candidate),
            confirmed: true,
        },
    )
    .expect_err("change-log failure must abort relink");

    assert_db_error(error);
    assert_eq!(
        fs::read(&candidate).expect("read candidate after relink rollback"),
        content
    );
    assert!(!repo.path().join("docs/missing.pdf").exists());
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn missing_file_recovery_failure_remove_record_db_error_rolls_back_soft_delete() {
    let repo = initialized_repo();
    let file_id = insert_missing_repo_file(repo.path(), "docs/gone.pdf", b"gone");
    let unrelated = write_repo_file(repo.path(), "docs/unrelated.txt", b"keep me");
    let before = snapshot(repo.path());
    install_change_log_failure(repo.path(), "removed_from_index");

    let error = remove_missing_file_record(
        path_string(repo.path()),
        MissingFileRemoveRecordRequest {
            file_id,
            confirmed: true,
        },
    )
    .expect_err("change-log failure must abort remove record");

    assert_db_error(error);
    assert_eq!(
        fs::read(&unrelated).expect("read unrelated user file after rollback"),
        b"keep me"
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn missing_file_recovery_failure_corrupted_db_is_db_error_and_preserves_user_files() {
    let repo = initialized_repo();
    let user_file = write_repo_file(repo.path(), "docs/user.pdf", b"user content");
    fs::write(repo.path().join(".areamatrix/index.db"), b"not sqlite")
        .expect("corrupt repository database fixture");

    assert_db_error(
        get_missing_file_state(path_string(repo.path()), 1)
            .expect_err("corrupted metadata is explicit Db"),
    );

    assert_eq!(
        fs::read(&user_file).expect("read user file after corrupted DB failure"),
        b"user content"
    );
    assert!(!repo.path().join(".areamatrix/staging/docs").exists());
}

#[cfg(unix)]
#[test]
fn missing_file_recovery_failure_permission_denied_old_path_keeps_metadata() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let blocked_dir = repo.path().join("blocked");
    fs::create_dir_all(&blocked_dir).expect("create blocked directory");
    let file_id = insert_missing_repo_file(repo.path(), "blocked/secret.pdf", b"secret");
    let before = snapshot(repo.path());
    let original_permissions = fs::metadata(&blocked_dir)
        .expect("read blocked directory permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&blocked_dir, blocked_permissions).expect("block directory lookup");

    if blocked_dir.join("secret.pdf").try_exists().is_ok() {
        fs::set_permissions(&blocked_dir, original_permissions)
            .expect("restore blocked directory permissions");
        return;
    }

    let error = get_missing_file_state(path_string(repo.path()), file_id)
        .expect_err("blocked missing path must be permission denied");

    fs::set_permissions(&blocked_dir, original_permissions)
        .expect("restore blocked directory permissions");
    assert_permission_denied(error);
    assert_eq!(snapshot(repo.path()), before);
}

#[cfg(unix)]
#[test]
fn missing_file_recovery_failure_permission_denied_candidate_keeps_state() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let content = b"restored secret";
    let file_id = insert_missing_repo_file(repo.path(), "docs/missing.pdf", content);
    let candidate = write_repo_file(repo.path(), "docs/restored.pdf", content);
    let before = snapshot(repo.path());
    let original_permissions = fs::metadata(&candidate)
        .expect("read candidate permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&candidate, blocked_permissions).expect("block candidate read");

    if fs::File::open(&candidate).is_ok() {
        fs::set_permissions(&candidate, original_permissions)
            .expect("restore candidate permissions");
        return;
    }

    let error = relink_missing_file(
        path_string(repo.path()),
        MissingFileRelinkRequest {
            file_id,
            new_path: path_string(&candidate),
            confirmed: true,
        },
    )
    .expect_err("unreadable candidate must be permission denied");

    fs::set_permissions(&candidate, original_permissions).expect("restore candidate permissions");
    assert_permission_denied(error);
    assert_eq!(
        fs::read(&candidate).expect("read candidate after permission restore"),
        content
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn missing_file_recovery_failure_has_no_ai_remote_secret_or_generated_side_effects() {
    let repo = initialized_repo();
    let content = b"restored locally";
    let file_id = insert_missing_repo_file(repo.path(), "docs/missing.pdf", content);
    let candidate = write_repo_file(repo.path(), "docs/restored.pdf", content);
    let before_generated =
        relative_entries(repo.path(), &repo.path().join(".areamatrix/generated"));

    relink_missing_file(
        path_string(repo.path()),
        MissingFileRelinkRequest {
            file_id,
            new_path: path_string(&candidate),
            confirmed: true,
        },
    )
    .expect("relink local missing file");

    assert!(!repo.path().join(".areamatrix/ai").exists());
    assert!(!repo.path().join(".areamatrix/remote").exists());
    assert!(!repo.path().join(".areamatrix/secrets").exists());
    assert!(!table_exists(repo.path(), "ai_call_log"));
    assert_eq!(
        relative_entries(repo.path(), &repo.path().join(".areamatrix/generated")),
        before_generated
    );
    assert_eq!(
        fs::read(&candidate).expect("read relink candidate after successful metadata update"),
        content
    );
}
