use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, predict_category, CoreError, DuplicateStrategy, FileFilter,
    FileOrigin, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions,
    StorageMode,
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

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source fixture");
    (source_root, source_path)
}

fn desktop_options(mode: StorageMode, duplicate_strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("desktop/imports".to_owned()),
        override_category: None,
        override_filename: None,
        duplicate_strategy,
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
        .expect("count active files")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

#[test]
fn desktop_import_flow_implementation_previews_category_then_commits_copy() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("Desktop Report.pdf", b"desktop copy bytes");

    let preview = predict_category(path_string(repo.path()), "Desktop Report.pdf".to_owned())
        .expect("predict desktop import category");
    assert_eq!(preview.category, "docs");
    assert_eq!(preview.suggested_name, "Desktop Report.pdf");

    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        desktop_options(StorageMode::Copied, DuplicateStrategy::KeepBoth),
    )
    .expect("commit desktop copied import");

    assert_eq!(entry.path, "desktop/imports/Desktop Report.pdf");
    assert_eq!(entry.category, "desktop");
    assert_eq!(entry.storage_mode, StorageMode::Copied);
    assert_eq!(entry.origin, FileOrigin::Imported);
    assert_eq!(
        entry.source_path.as_deref(),
        Some(path_string(&source).as_str())
    );
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read copied repo file"),
        b"desktop copy bytes"
    );
    assert_eq!(
        fs::read(&source).expect("read original picker file"),
        b"desktop copy bytes"
    );

    let files = list_files(path_string(repo.path()), empty_filter()).expect("list desktop imports");
    assert_eq!(files, vec![entry]);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn desktop_import_flow_implementation_commits_move_and_index_modes() {
    let repo = initialized_repo();
    let (_move_root, move_source) = source_file("move.txt", b"move bytes");
    let move_source_path = path_string(&move_source);
    let (_index_root, index_source) = source_file("index.txt", b"index bytes");
    let index_source_path = path_string(&index_source);

    let moved = import_file(
        path_string(repo.path()),
        move_source_path.clone(),
        desktop_options(StorageMode::Moved, DuplicateStrategy::KeepBoth),
    )
    .expect("commit desktop moved import");
    let indexed = import_file(
        path_string(repo.path()),
        index_source_path.clone(),
        desktop_options(StorageMode::Indexed, DuplicateStrategy::KeepBoth),
    )
    .expect("commit desktop indexed import");

    assert_eq!(moved.path, "desktop/imports/move.txt");
    assert_eq!(moved.storage_mode, StorageMode::Moved);
    assert_eq!(
        moved.source_path.as_deref(),
        Some(move_source_path.as_str())
    );
    assert!(
        !move_source.exists(),
        "desktop moved import consumes the picker source path"
    );
    assert_eq!(
        fs::read(repo.path().join(&moved.path)).expect("read moved repo file"),
        b"move bytes"
    );

    assert_eq!(indexed.path, index_source_path);
    assert_eq!(indexed.storage_mode, StorageMode::Indexed);
    assert_eq!(
        indexed.source_path.as_deref(),
        Some(index_source_path.as_str())
    );
    assert_eq!(
        fs::read(&index_source).expect("read indexed external source"),
        b"index bytes"
    );
    assert!(!repo.path().join("desktop/imports/index.txt").exists());

    let mut files = list_files(path_string(repo.path()), empty_filter()).expect("list imports");
    files.sort_by_key(|entry| entry.id);
    assert_eq!(files, vec![moved, indexed]);
    assert_eq!(active_file_count(repo.path()), 2);
    assert_eq!(change_log_count(repo.path()), 2);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn desktop_import_flow_implementation_duplicate_ask_surfaces_error_without_success_state() {
    let repo = initialized_repo();
    let (_first_root, first_source) = source_file("first.pdf", b"same desktop bytes");
    let (_duplicate_root, duplicate_source) = source_file("duplicate.pdf", b"same desktop bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&first_source),
        desktop_options(StorageMode::Copied, DuplicateStrategy::KeepBoth),
    )
    .expect("commit first desktop import");

    let result = import_file(
        path_string(repo.path()),
        path_string(&duplicate_source),
        desktop_options(StorageMode::Copied, DuplicateStrategy::Ask),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::DuplicateFile { existing_path }) if existing_path == first.path
        ),
        "duplicate Ask must return a structured conflict state instead of success"
    );
    assert_eq!(
        fs::read(&duplicate_source).expect("read rejected duplicate source"),
        b"same desktop bytes"
    );
    assert!(!repo.path().join("desktop/imports/duplicate.pdf").exists());
    assert_eq!(active_file_count(repo.path()), 1);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}
