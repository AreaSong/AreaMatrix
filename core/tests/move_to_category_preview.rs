use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, move_to_category, preview_move_to_category, CoreError,
    DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
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
fn move_to_category_preview_resolves_numbered_target_without_writes() {
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
    let before_row = file_row(repo.path(), moving.id);

    let preview = preview_move_to_category(path_string(repo.path()), moving.id, "docs".to_owned())
        .expect("preview move to docs");

    assert_eq!(preview.file_id, moving.id);
    assert_eq!(preview.from_category, "finance");
    assert_eq!(preview.to_category, "docs");
    assert_eq!(preview.current_path, "finance/same.pdf");
    assert_eq!(preview.target_path, "docs/same_1.pdf");
    assert_eq!(preview.target_name, "same_1.pdf");
    assert_eq!(preview.storage_mode, StorageMode::Copied);
    assert!(!preview.index_only);
    assert!(preview.name_conflict_resolved);
    assert!(preview.will_move_file);
    assert_eq!(file_row(repo.path(), moving.id), before_row);
    assert_eq!(moved_change_count(repo.path(), moving.id), 0);
    assert_eq!(
        fs::read(repo.path().join(&existing.path)).expect("read existing target after preview"),
        b"existing bytes"
    );
    assert_eq!(
        fs::read(repo.path().join("finance/same.pdf")).expect("read source after preview"),
        b"moving bytes"
    );
    assert!(!repo.path().join("docs/same_1.pdf").exists());

    let moved = move_to_category(path_string(repo.path()), moving.id, "docs".to_owned())
        .expect("confirm category move");
    assert_eq!(moved.path, preview.target_path);
    assert_eq!(moved.current_name, preview.target_name);
}

#[test]
fn move_to_category_preview_does_not_create_missing_category_directory() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"report bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import copied file before preview");
    assert!(!repo.path().join("docs").exists());

    let preview = preview_move_to_category(path_string(repo.path()), entry.id, "docs".to_owned())
        .expect("preview move into missing docs category");

    assert_eq!(preview.target_path, "docs/report.pdf");
    assert_eq!(preview.target_name, "report.pdf");
    assert!(!preview.name_conflict_resolved);
    assert!(preview.will_move_file);
    assert!(!repo.path().join("docs").exists());
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
fn move_to_category_preview_indexed_file_is_metadata_only() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("external.pdf", b"external bytes");
    let source_path = path_string(&source);
    let source_bytes = fs::read(&source).expect("read indexed source before preview");
    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        import_options(StorageMode::Indexed, "finance", "shown.pdf"),
    )
    .expect("index external file before preview");

    let preview = preview_move_to_category(path_string(repo.path()), entry.id, "docs".to_owned())
        .expect("preview indexed metadata move");

    assert_eq!(preview.current_path, source_path);
    assert_eq!(preview.target_path, source_path);
    assert_eq!(preview.target_name, "shown.pdf");
    assert_eq!(preview.storage_mode, StorageMode::Indexed);
    assert!(preview.index_only);
    assert!(!preview.name_conflict_resolved);
    assert!(!preview.will_move_file);
    assert_eq!(
        fs::read(&source).expect("read indexed source after preview"),
        source_bytes
    );
    assert!(!repo.path().join("docs/shown.pdf").exists());
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[test]
fn move_to_category_preview_unknown_category_preserves_state() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"report bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import copied file before rejected preview");

    let result = preview_move_to_category(
        path_string(repo.path()),
        entry.id,
        "missing-category".to_owned(),
    );

    assert!(matches!(result, Err(CoreError::Classify { .. })));
    assert_eq!(
        fs::read(repo.path().join("finance/report.pdf")).expect("read source after preview error"),
        b"report bytes"
    );
    assert!(!repo.path().join("missing-category").exists());
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}
