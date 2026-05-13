use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, rename_file, CoreError, DuplicateStrategy, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository");
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

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn import_options(mode: StorageMode, filename: &str) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, status FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read file row")
}

fn change_count(repo: &Path, action: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log WHERE action = ?1",
            [action],
            |row| row.get(0),
        )
        .expect("count change-log rows")
}

fn install_rename_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_rename_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'renamed'
             BEGIN
               SELECT RAISE(ABORT, 'forced rename change-log failure');
             END;",
        )
        .expect("install rename change-log failure trigger");
}

fn drop_rename_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch("DROP TRIGGER fail_rename_change_log;")
        .expect("drop rename change-log failure trigger");
}

fn install_rename_rollback_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_rename_rollback
             BEFORE UPDATE ON files
             WHEN OLD.path = 'finance/final.pdf' AND NEW.path = 'finance/draft.pdf'
             BEGIN
               SELECT RAISE(ABORT, 'forced rename rollback failure');
             END;",
        )
        .expect("install rename rollback failure trigger");
}

fn block_generated_node_overview(repo: &Path) {
    let generated_nodes = repo.join(".areamatrix/generated/nodes");
    fs::remove_dir_all(&generated_nodes).expect("remove generated node directory");
    fs::write(&generated_nodes, b"not a directory").expect("block generated node output path");
}

#[test]
fn rename_file_failure_recovery_db_failure_rolls_back_and_retry_succeeds() {
    let repo = initialized_repo();
    let (_existing_root, existing_source) = source_file("existing.pdf", b"existing bytes");
    let (_draft_root, draft_source) = source_file("draft.pdf", b"draft bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&existing_source),
        import_options(StorageMode::Copied, "same.pdf"),
    )
    .expect("import existing same-name target");
    let draft = import_file(
        path_string(repo.path()),
        path_string(&draft_source),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import file to rename");
    install_rename_change_log_failure(repo.path());

    let failed = rename_file(path_string(repo.path()), draft.id, "same.pdf".to_owned());

    assert!(matches!(failed, Err(CoreError::Db { .. })));
    assert_eq!(
        fs::read(repo.path().join("finance/same.pdf")).expect("read existing target"),
        b"existing bytes"
    );
    assert_eq!(
        fs::read(repo.path().join("finance/draft.pdf")).expect("read restored draft"),
        b"draft bytes"
    );
    assert!(!repo.path().join("finance/same_1.pdf").exists());
    assert_eq!(
        file_row(repo.path(), draft.id),
        (
            "finance/draft.pdf".to_owned(),
            "draft.pdf".to_owned(),
            "active".to_owned(),
        )
    );

    drop_rename_change_log_failure(repo.path());
    let retried = rename_file(path_string(repo.path()), draft.id, "same.pdf".to_owned())
        .expect("retry rename after rollback");

    assert_eq!(retried.path, "finance/same_1.pdf");
    assert_eq!(
        fs::read(repo.path().join(&retried.path)).expect("read retried rename target"),
        b"draft bytes"
    );
    assert_eq!(
        file_row(repo.path(), existing.id),
        (
            "finance/same.pdf".to_owned(),
            "same.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(change_count(repo.path(), "renamed"), 1);
}

#[test]
fn rename_file_failure_recovery_indexed_db_failure_keeps_external_source() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("external.pdf", b"external bytes");
    let source_path = path_string(&source);
    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        import_options(StorageMode::Indexed, "shown.pdf"),
    )
    .expect("index external file");
    install_rename_change_log_failure(repo.path());

    let failed = rename_file(path_string(repo.path()), entry.id, "display.pdf".to_owned());

    assert!(matches!(failed, Err(CoreError::Db { .. })));
    assert_eq!(
        fs::read(&source).expect("read external source after failed indexed rename"),
        b"external bytes"
    );
    assert!(!repo.path().join("finance").exists());
    assert_eq!(
        file_row(repo.path(), entry.id),
        (source_path, "shown.pdf".to_owned(), "active".to_owned())
    );
    assert_eq!(change_count(repo.path(), "renamed"), 0);
}

#[test]
fn rename_file_failure_recovery_rollback_failure_keeps_db_and_filesystem_consistent() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("draft.pdf", b"draft bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import file to rename");
    block_generated_node_overview(repo.path());
    install_rename_rollback_failure(repo.path());

    let failed = rename_file(path_string(repo.path()), entry.id, "final.pdf".to_owned());

    assert!(matches!(failed, Err(CoreError::Db { .. })));
    assert!(!repo.path().join("finance/draft.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("finance/final.pdf"))
            .expect("read committed path after rollback failure"),
        b"draft bytes"
    );
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/final.pdf".to_owned(),
            "final.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(change_count(repo.path(), "renamed"), 1);

    let repeated = rename_file(path_string(repo.path()), entry.id, "final.pdf".to_owned())
        .expect("repeating committed rename is a no-op");
    assert_eq!(repeated.path, "finance/final.pdf");
    assert_eq!(repeated.current_name, "final.pdf");
}

#[cfg(unix)]
#[test]
fn rename_file_failure_recovery_permission_denied_keeps_original_and_existing_files() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (_existing_root, existing_source) = source_file("existing.pdf", b"existing bytes");
    let (_draft_root, draft_source) = source_file("draft.pdf", b"draft bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&existing_source),
        import_options(StorageMode::Copied, "same.pdf"),
    )
    .expect("import existing same-name target");
    let draft = import_file(
        path_string(repo.path()),
        path_string(&draft_source),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import file to rename");
    let finance_dir = repo.path().join("finance");
    let original_permissions = fs::metadata(&finance_dir)
        .expect("read finance directory metadata")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o500);
    fs::set_permissions(&finance_dir, blocked_permissions).expect("make target directory readonly");

    let failed = rename_file(path_string(repo.path()), draft.id, "same.pdf".to_owned());

    fs::set_permissions(&finance_dir, original_permissions).expect("restore target permissions");

    assert_eq!(
        failed,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert_eq!(
        fs::read(repo.path().join("finance/same.pdf")).expect("read existing target"),
        b"existing bytes"
    );
    assert_eq!(
        fs::read(repo.path().join("finance/draft.pdf")).expect("read original draft"),
        b"draft bytes"
    );
    assert!(!repo.path().join("finance/same_1.pdf").exists());
    assert_eq!(
        file_row(repo.path(), existing.id),
        (
            "finance/same.pdf".to_owned(),
            "same.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(
        file_row(repo.path(), draft.id),
        (
            "finance/draft.pdf".to_owned(),
            "draft.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(change_count(repo.path(), "renamed"), 0);
}
