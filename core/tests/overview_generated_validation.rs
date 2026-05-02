use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_changes, list_files, load_config, update_config, ChangeFilter,
    CoreError, DuplicateStrategy, FileEntry, FileFilter, ImportDestination, ImportOptions,
    OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options(overview_output: OverviewOutput) -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output,
    }
}

fn initialized_repo(overview_output: OverviewOutput) -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository");
    init_repo(
        path_string(repo.path()),
        create_empty_options(overview_output),
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

fn copied_options(category: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some(category.to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn change_filter() -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

fn import_doc(repo: &Path, name: &str, content: &[u8]) -> FileEntry {
    let (_source_root, source) = source_file(name, content);
    import_file(
        path_string(repo),
        path_string(&source),
        copied_options("docs"),
    )
    .expect("import file and regenerate overview")
}

fn read_file(path: &Path) -> String {
    fs::read_to_string(path).expect("read file")
}

fn db_connection(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository db")
}

fn active_file_count(repo: &Path) -> i64 {
    db_connection(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active files")
}

fn sqlite_integrity_check(repo: &Path) -> String {
    db_connection(repo)
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .expect("run SQLite integrity_check")
}

fn foreign_key_violations(repo: &Path) -> Vec<String> {
    let connection = db_connection(repo);
    let mut statement = connection
        .prepare("PRAGMA foreign_key_check")
        .expect("prepare foreign_key_check");
    let rows = statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("run foreign_key_check");

    rows.map(|row| row.expect("read foreign_key_check row"))
        .collect()
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected `{needle}` in:\n{haystack}"
    );
}

fn assert_clean_db(repo: &Path, expected_active_files: i64, expected_changes: usize) {
    assert_eq!(active_file_count(repo), expected_active_files);
    assert_eq!(
        list_files(path_string(repo), file_filter())
            .expect("list files")
            .len() as i64,
        expected_active_files
    );
    assert_eq!(
        list_changes(path_string(repo), change_filter())
            .expect("list changes")
            .len(),
        expected_changes
    );
    assert_eq!(sqlite_integrity_check(repo), "ok");
    assert!(foreign_key_violations(repo).is_empty());
}

#[test]
fn overview_generated_validation_default_import_updates_generated_outputs_only() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");

    let entry = import_doc(repo.path(), "validation.pdf", b"validation bytes");

    assert_eq!(entry.path, "docs/validation.pdf");
    assert_eq!(entry.category, "docs");
    assert_eq!(read_file(&readme_path), "user readme\n");
    assert!(!repo.path().join("AREAMATRIX.md").exists());

    let generated_root = read_file(&repo.path().join(".areamatrix/generated/root.md"));
    let generated_node = read_file(&repo.path().join(".areamatrix/generated/nodes/docs.md"));
    assert_contains(&generated_root, "AREAMATRIX:BEGIN");
    assert_contains(&generated_root, "docs");
    assert_contains(&generated_root, "1 个文件");
    assert_contains(&generated_node, "validation.pdf");
    assert_contains(&generated_node, "16 B");
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
    assert_clean_db(repo.path(), 1, 1);
}

#[test]
fn overview_generated_validation_policy_switch_applies_on_next_regeneration() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let readme_path = repo.path().join("README.md");
    let root_entry = repo.path().join("AREAMATRIX.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");

    let mut config = load_config(path_string(repo.path())).expect("load config");
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    update_config(path_string(repo.path()), config).expect("enable root overview policy");
    assert!(!root_entry.exists());
    assert_eq!(read_file(&readme_path), "user readme\n");

    import_doc(repo.path(), "root-enabled.pdf", b"root enabled");
    let enabled_root = read_file(&root_entry);
    assert_contains(&enabled_root, "AREAMATRIX:BEGIN");
    assert_contains(&enabled_root, "root-enabled.pdf");

    let mut config = load_config(path_string(repo.path())).expect("reload config");
    config.overview_output = OverviewOutput::GeneratedOnly;
    update_config(path_string(repo.path()), config).expect("disable root overview policy");
    import_doc(repo.path(), "generated-only.pdf", b"generated only");

    assert_eq!(read_file(&root_entry), enabled_root);
    let generated_root = read_file(&repo.path().join(".areamatrix/generated/root.md"));
    assert_contains(&generated_root, "root-enabled.pdf");
    assert_contains(&generated_root, "generated-only.pdf");
    assert_eq!(read_file(&readme_path), "user readme\n");
    assert_clean_db(repo.path(), 2, 2);
}

#[test]
fn overview_generated_validation_root_entry_failure_restores_previous_generated_outputs() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let readme_path = repo.path().join("README.md");
    let root_entry = repo.path().join("AREAMATRIX.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    let existing = import_doc(repo.path(), "existing.pdf", b"existing bytes");
    let generated_root_path = repo.path().join(".areamatrix/generated/root.md");
    let generated_node_path = repo.path().join(".areamatrix/generated/nodes/docs.md");
    let generated_root_before = read_file(&generated_root_path);
    let generated_node_before = read_file(&generated_node_path);

    fs::create_dir(&root_entry).expect("create root AREAMATRIX.md directory blocker");
    let mut config = load_config(path_string(repo.path())).expect("load config");
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    update_config(path_string(repo.path()), config).expect("enable root overview policy");
    let (_source_root, source) = source_file("blocked.pdf", b"blocked bytes");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("docs"),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::Io { .. }
                | CoreError::Config { .. }
                | CoreError::PermissionDenied { .. })
        ),
        "expected root overview write failure, got {result:?}"
    );
    assert!(root_entry.is_dir());
    assert_eq!(read_file(&readme_path), "user readme\n");
    assert_eq!(
        fs::read(&source).expect("read source after failure"),
        b"blocked bytes"
    );
    assert!(!repo.path().join("docs/blocked.pdf").exists());
    assert_eq!(read_file(&generated_root_path), generated_root_before);
    assert_eq!(read_file(&generated_node_path), generated_node_before);
    assert_eq!(
        list_files(path_string(repo.path()), file_filter()).expect("list files"),
        vec![existing]
    );
    assert_clean_db(repo.path(), 1, 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[cfg(unix)]
#[test]
fn overview_generated_validation_root_entry_symlink_is_rejected_without_replacement() {
    use std::os::unix::fs::symlink;

    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let existing = import_doc(repo.path(), "existing.pdf", b"existing bytes");
    let root_entry = repo.path().join("AREAMATRIX.md");
    let outside_root = tempfile::NamedTempFile::new().expect("create external root target");
    fs::write(outside_root.path(), b"external overview\n").expect("write external root target");
    symlink(outside_root.path(), &root_entry).expect("create root AREAMATRIX.md symlink");
    let generated_root_path = repo.path().join(".areamatrix/generated/root.md");
    let generated_node_path = repo.path().join(".areamatrix/generated/nodes/docs.md");
    let generated_root_before = read_file(&generated_root_path);
    let generated_node_before = read_file(&generated_node_path);

    let mut config = load_config(path_string(repo.path())).expect("load config");
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    update_config(path_string(repo.path()), config).expect("enable root overview policy");
    let (_source_root, source) = source_file("symlink-blocked.pdf", b"symlink blocked");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("docs"),
    );

    assert!(matches!(result, Err(CoreError::Config { .. })));

    assert!(fs::symlink_metadata(&root_entry)
        .expect("read root symlink metadata")
        .file_type()
        .is_symlink());
    assert_eq!(
        fs::read(outside_root.path()).expect("read external root target"),
        b"external overview\n"
    );
    assert!(!repo.path().join("docs/symlink-blocked.pdf").exists());
    assert_eq!(read_file(&generated_root_path), generated_root_before);
    assert_eq!(read_file(&generated_node_path), generated_node_before);
    assert_eq!(
        list_files(path_string(repo.path()), file_filter()).expect("list files"),
        vec![existing]
    );
    assert_clean_db(repo.path(), 1, 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}
