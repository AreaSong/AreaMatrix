use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_changes, list_files, move_to_category, read_note, write_note,
    ChangeFilter, CoreError, DuplicateStrategy, FileFilter, ImportDestination, ImportOptions,
    OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

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

fn moved_detail(repo: &Path, file_id: i64) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log
             WHERE file_id = ?1 AND action = 'moved'
             ORDER BY id DESC LIMIT 1",
            [file_id],
            |row| row.get(0),
        )
        .expect("read moved change detail");
    serde_json::from_str(&detail_json).expect("parse moved change detail")
}

fn empty_file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn moved_change_filter(file_id: i64) -> ChangeFilter {
    ChangeFilter {
        file_id: Some(file_id),
        category: Some("docs".to_owned()),
        action: Some("moved".to_owned()),
        since: None,
        until: None,
        limit: 10,
        offset: 0,
    }
}

fn install_moved_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_moved_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'moved'
             BEGIN
               SELECT RAISE(ABORT, 'moved change log failure');
             END;",
        )
        .expect("install moved change_log failure trigger");
}

#[test]
fn move_to_category_moves_repo_owned_file_and_logs_change() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"report bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import copied file before category move");

    let moved = move_to_category(path_string(repo.path()), entry.id, "docs".to_owned())
        .expect("move copied file to docs category");

    assert_eq!(moved.id, entry.id);
    assert_eq!(moved.path, "docs/report.pdf");
    assert_eq!(moved.current_name, "report.pdf");
    assert_eq!(moved.category, "docs");
    assert_eq!(moved.original_name, entry.original_name);
    assert_eq!(moved.hash_sha256, entry.hash_sha256);
    assert_eq!(moved.storage_mode, StorageMode::Copied);
    assert!(moved.updated_at >= entry.updated_at);
    assert!(!repo.path().join("finance/report.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("docs/report.pdf")).expect("read moved file"),
        b"report bytes"
    );
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "docs/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "docs".to_owned(),
            Some(path_string(&source)),
        )
    );

    let listed = list_files(path_string(repo.path()), empty_file_filter()).expect("list files");
    assert_eq!(listed, vec![moved.clone()]);
    assert_eq!(
        list_changes(path_string(repo.path()), moved_change_filter(entry.id))
            .expect("list moved changes")
            .len(),
        1
    );

    let detail = moved_detail(repo.path(), entry.id);
    assert_eq!(detail["from_category"], "finance");
    assert_eq!(detail["to_category"], "docs");
    assert_eq!(detail["from_path"], "finance/report.pdf");
    assert_eq!(detail["to_path"], "docs/report.pdf");
    assert_eq!(detail["name_conflict_resolved"], false);
    assert_eq!(detail["index_only"], false);
    assert_eq!(detail["by"], "user");
}

#[test]
fn move_to_category_resolves_target_name_conflict_without_overwrite() {
    let repo = initialized_repo();
    let (_existing_root, existing_source) = source_file("existing.pdf", b"existing bytes");
    let (_moving_root, moving_source) = source_file("moving.pdf", b"moving bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&existing_source),
        import_options(StorageMode::Copied, "docs", "same.pdf"),
    )
    .expect("import existing target file");
    let moving = import_file(
        path_string(repo.path()),
        path_string(&moving_source),
        import_options(StorageMode::Copied, "finance", "same.pdf"),
    )
    .expect("import moving file");

    let moved = move_to_category(path_string(repo.path()), moving.id, "docs".to_owned())
        .expect("move with conflict-free numbering");

    assert_eq!(moved.path, "docs/same_1.pdf");
    assert_eq!(moved.current_name, "same_1.pdf");
    assert_eq!(
        fs::read(repo.path().join(&existing.path)).expect("read existing target"),
        b"existing bytes"
    );
    assert_eq!(
        fs::read(repo.path().join(&moved.path)).expect("read numbered moved file"),
        b"moving bytes"
    );
    assert!(!repo.path().join("finance/same.pdf").exists());

    let detail = moved_detail(repo.path(), moving.id);
    assert_eq!(detail["renamed_to"], "same_1.pdf");
    assert_eq!(detail["name_conflict_resolved"], true);
}

#[test]
fn move_to_category_indexed_file_updates_metadata_only() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("external.pdf", b"external bytes");
    let source_path = path_string(&source);
    let source_bytes = fs::read(&source).expect("read indexed source before move");
    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        import_options(StorageMode::Indexed, "finance", "shown.pdf"),
    )
    .expect("index external file before category move");

    let moved = move_to_category(path_string(repo.path()), entry.id, "docs".to_owned())
        .expect("move indexed file metadata to docs");

    assert_eq!(moved.path, source_path);
    assert_eq!(moved.current_name, "shown.pdf");
    assert_eq!(moved.category, "docs");
    assert_eq!(moved.source_path.as_deref(), Some(source_path.as_str()));
    assert_eq!(
        fs::read(&source).expect("read external source after metadata-only move"),
        source_bytes
    );
    assert!(!repo.path().join("docs/shown.pdf").exists());
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            source_path.clone(),
            "shown.pdf".to_owned(),
            "docs".to_owned(),
            Some(source_path),
        )
    );

    let detail = moved_detail(repo.path(), entry.id);
    assert_eq!(detail["from_path"], entry.path);
    assert_eq!(detail["to_path"], moved.path);
    assert_eq!(detail["index_only"], true);
}

#[test]
fn move_to_category_rejects_unknown_category_without_side_effects() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"report bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import copied file before rejected category move");

    let result = move_to_category(
        path_string(repo.path()),
        entry.id,
        "missing-category".to_owned(),
    );

    assert!(matches!(result, Err(CoreError::Classify { .. })));
    assert_eq!(
        fs::read(repo.path().join("finance/report.pdf")).expect("read original file"),
        b"report bytes"
    );
    assert!(!repo.path().join("missing-category").exists());
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/report.pdf".to_owned(),
            "report.pdf".to_owned(),
            "finance".to_owned(),
            Some(path_string(&source)),
        )
    );
}

#[test]
fn move_to_category_rolls_back_filesystem_when_db_log_fails() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"report bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import copied file before failed category move");
    write_note(
        path_string(repo.path()),
        entry.id,
        "important note".to_owned(),
    )
    .expect("write note before category move");
    install_moved_change_log_failure(repo.path());

    let result = move_to_category(path_string(repo.path()), entry.id, "docs".to_owned());

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        fs::read(repo.path().join("finance/report.pdf")).expect("read restored file"),
        b"report bytes"
    );
    assert!(repo.path().join("finance/report.pdf.md").exists());
    assert!(!repo.path().join("docs/report.pdf").exists());
    assert!(!repo.path().join("docs/report.pdf.md").exists());
    assert!(!repo.path().join("docs").exists());
    assert_eq!(
        read_note(path_string(repo.path()), entry.id).expect("read restored note"),
        Some("important note".to_owned())
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
}
