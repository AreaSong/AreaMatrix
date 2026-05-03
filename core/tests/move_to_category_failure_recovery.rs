use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, move_to_category, CoreError, DuplicateStrategy, ImportDestination,
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

fn import_options(mode: StorageMode, category: &str, filename: &str) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some(category.to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, String, Option<String>) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category, source_path FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read file row")
}

fn moved_change_count(repo: &Path, file_id: i64) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log WHERE file_id = ?1 AND action = 'moved'",
            [file_id],
            |row| row.get(0),
        )
        .expect("count moved change_log rows")
}

#[test]
fn move_to_category_repeated_call_is_idempotent_without_extra_log() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"report bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import copied file before category move");
    let first = move_to_category(path_string(repo.path()), entry.id, "docs".to_owned())
        .expect("move copied file to docs category");
    let moved_logs = moved_change_count(repo.path(), entry.id);

    let second = move_to_category(path_string(repo.path()), entry.id, "docs".to_owned())
        .expect("repeat category move to same category");

    assert_eq!(second, first);
    assert_eq!(moved_change_count(repo.path(), entry.id), moved_logs);
    assert_eq!(
        fs::read(repo.path().join("docs/report.pdf")).expect("read moved file after retry"),
        b"report bytes"
    );
    assert!(!repo.path().join("finance/report.pdf").exists());
}

#[test]
fn move_to_category_same_category_repo_owned_missing_file_is_not_false_success() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"report bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import copied file before no-op move");
    fs::remove_file(repo.path().join("finance/report.pdf"))
        .expect("remove repo-owned file to simulate external loss");

    let result = move_to_category(path_string(repo.path()), entry.id, "finance".to_owned());

    assert!(matches!(result, Err(CoreError::FileNotFound { .. })));
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "finance".to_owned(),
            Some(path_string(&source)),
        )
    );
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[test]
fn move_to_category_target_category_file_conflict_preserves_original_state() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"report bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import copied file before target category conflict");
    fs::write(repo.path().join("docs"), b"user owned path")
        .expect("create target category path as file");

    let result = move_to_category(path_string(repo.path()), entry.id, "docs".to_owned());

    assert!(matches!(result, Err(CoreError::Conflict { .. })));
    assert_eq!(
        fs::read(repo.path().join("finance/report.pdf")).expect("read original file"),
        b"report bytes"
    );
    assert_eq!(
        fs::read(repo.path().join("docs")).expect("read conflicting target file"),
        b"user owned path"
    );
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "finance".to_owned(),
            Some(path_string(&source)),
        )
    );
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[cfg(unix)]
#[test]
fn move_to_category_permission_denied_keeps_source_and_metadata() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"report bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import copied file before permission failure");
    let docs_dir = repo.path().join("docs");
    fs::create_dir(&docs_dir).expect("create docs directory");
    let _mode_guard = ModeGuard::set(&docs_dir, 0o500);

    let result = move_to_category(path_string(repo.path()), entry.id, "docs".to_owned());

    assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
    assert_eq!(
        fs::read(repo.path().join("finance/report.pdf")).expect("read original file"),
        b"report bytes"
    );
    assert!(!docs_dir.join("report.pdf").exists());
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "finance".to_owned(),
            Some(path_string(&source)),
        )
    );
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[cfg(unix)]
struct ModeGuard {
    path: PathBuf,
    mode: u32,
}

#[cfg(unix)]
impl ModeGuard {
    fn set(path: &Path, mode: u32) -> Self {
        use std::os::unix::fs::PermissionsExt;

        let original_mode = fs::metadata(path)
            .expect("read directory permissions")
            .permissions()
            .mode();
        let mut permissions = fs::metadata(path)
            .expect("read directory permissions before update")
            .permissions();
        permissions.set_mode(mode);
        fs::set_permissions(path, permissions).expect("set directory permissions");
        Self {
            path: path.to_path_buf(),
            mode: original_mode,
        }
    }
}

#[cfg(unix)]
impl Drop for ModeGuard {
    fn drop(&mut self) {
        use std::os::unix::fs::PermissionsExt;

        if let Ok(metadata) = fs::metadata(&self.path) {
            let mut permissions = metadata.permissions();
            permissions.set_mode(self.mode);
            let _restore_result = fs::set_permissions(&self.path, permissions);
        }
    }
}
