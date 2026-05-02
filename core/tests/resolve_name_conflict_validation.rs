use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, rename_file, CoreError, DuplicateStrategy, FileFilter,
    ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

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
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn copied_options(filename: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
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

fn count_file_rows(repo: &Path, status: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = ?1",
            [status],
            |row| row.get(0),
        )
        .expect("count file rows")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows")
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

fn change_detail(repo: &Path, file_id: i64, action: &str) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log WHERE file_id = ?1 AND action = ?2",
            (file_id, action),
            |row| row.get(0),
        )
        .expect("read change detail");
    serde_json::from_str(&detail_json).expect("parse change detail")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn fill_numbered_conflicts(directory: &Path) {
    fs::create_dir_all(directory).expect("create conflict directory");
    fs::write(directory.join("same.pdf"), b"existing-base").expect("write base conflict file");
    for index in 1..1000 {
        fs::write(
            directory.join(format!("same_{index}.pdf")),
            format!("existing-{index}"),
        )
        .expect("write numbered conflict file");
    }
}

fn assert_no_staging_residue(repo: &Path) {
    assert_eq!(count_file_rows(repo, "staging"), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

#[test]
fn resolve_name_conflict_validation_import_returns_fs_and_db_consistent_numbered_name() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"first bytes");
    let (_source_root_b, source_b) = source_file("second.pdf", b"second bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options("same.pdf"),
    )
    .expect("import first same-name file");
    let second = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options("same.pdf"),
    )
    .expect("import second same-name file with numbered resolution");

    assert_eq!(first.path, "finance/same.pdf");
    assert_eq!(second.path, "finance/same_1.pdf");
    assert_eq!(second.current_name, "same_1.pdf");
    assert_eq!(
        fs::read(repo.path().join("finance/same.pdf")).expect("read original final file"),
        b"first bytes"
    );
    assert_eq!(
        fs::read(repo.path().join("finance/same_1.pdf")).expect("read numbered final file"),
        b"second bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read copied source after import"),
        b"second bytes"
    );
    assert_eq!(
        file_row(repo.path(), second.id),
        (
            "finance/same_1.pdf".to_owned(),
            "same_1.pdf".to_owned(),
            "active".to_owned(),
        )
    );

    let listed = list_files(path_string(repo.path()), empty_filter()).expect("list active files");
    assert_eq!(listed.len(), 2);
    assert_eq!(count_file_rows(repo.path(), "active"), 2);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 0);
    assert_eq!(change_log_count(repo.path()), 2);
    assert_no_staging_residue(repo.path());

    let detail = change_detail(repo.path(), second.id, "imported");
    assert_eq!(detail["requested_name"], "same.pdf");
    assert_eq!(detail["final_name"], "same_1.pdf");
    assert_eq!(detail["final_path"], "finance/same_1.pdf");
    assert_eq!(detail["name_conflict_resolved"], true);
}

#[test]
fn resolve_name_conflict_validation_rename_keeps_existing_target_and_logs_resolution() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"first bytes");
    let (_source_root_b, source_b) = source_file("draft.pdf", b"draft bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options("same.pdf"),
    )
    .expect("import existing same-name target");
    let draft = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options("draft.pdf"),
    )
    .expect("import draft file before rename");

    let renamed = rename_file(path_string(repo.path()), draft.id, "same.pdf".to_owned())
        .expect("rename draft with safe numbered resolution");

    assert_eq!(renamed.path, "finance/same_1.pdf");
    assert_eq!(renamed.current_name, "same_1.pdf");
    assert_eq!(
        fs::read(repo.path().join(&existing.path)).expect("read existing target"),
        b"first bytes"
    );
    assert_eq!(
        fs::read(repo.path().join(&renamed.path)).expect("read renamed target"),
        b"draft bytes"
    );
    assert!(!repo.path().join("finance/draft.pdf").exists());
    assert_eq!(
        file_row(repo.path(), draft.id),
        (
            "finance/same_1.pdf".to_owned(),
            "same_1.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 2);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 0);
    assert_eq!(change_log_count(repo.path()), 3);

    let detail = change_detail(repo.path(), draft.id, "renamed");
    assert_eq!(detail["from_path"], "finance/draft.pdf");
    assert_eq!(detail["to_path"], "finance/same_1.pdf");
    assert_eq!(detail["requested_name"], "same.pdf");
    assert_eq!(detail["final_name"], "same_1.pdf");
    assert_eq!(detail["name_conflict_resolved"], true);
}

#[test]
fn resolve_name_conflict_validation_invalid_filename_does_not_change_repo() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"first bytes");
    let (_source_root_b, source_b) = source_file("invalid.pdf", b"invalid bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options("same.pdf"),
    )
    .expect("import existing file");
    let mut invalid_import_options = copied_options("same.pdf");
    invalid_import_options.override_filename = Some("bad/name.pdf".to_owned());

    let import_result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        invalid_import_options,
    );
    let rename_result = rename_file(
        path_string(repo.path()),
        existing.id,
        "bad/name.pdf".to_owned(),
    );

    assert!(matches!(import_result, Err(CoreError::InvalidPath { .. })));

    assert!(matches!(rename_result, Err(CoreError::InvalidPath { .. })));
    assert_eq!(
        fs::read(repo.path().join("finance/same.pdf")).expect("read existing final file"),
        b"first bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read source after rejected import"),
        b"invalid bytes"
    );
    assert_eq!(
        file_row(repo.path(), existing.id),
        (
            "finance/same.pdf".to_owned(),
            "same.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 0);
    assert_eq!(change_log_count(repo.path()), 1);
    assert_no_staging_residue(repo.path());
}

#[test]
fn resolve_name_conflict_validation_exhausted_numbering_returns_conflict_without_writes() {
    let repo = initialized_repo();
    let conflict_dir = repo.path().join("finance");
    fill_numbered_conflicts(&conflict_dir);
    let (_source_root, source) = source_file("source.pdf", b"new bytes");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("same.pdf"),
    );

    assert!(matches!(result, Err(CoreError::Conflict { .. })));

    assert_eq!(
        fs::read(conflict_dir.join("same.pdf")).expect("read existing base conflict"),
        b"existing-base"
    );
    assert_eq!(
        fs::read(&source).expect("read copied source after conflict exhaustion"),
        b"new bytes"
    );
    assert!(!conflict_dir.join("same_1000.pdf").exists());
    assert_eq!(count_file_rows(repo.path(), "active"), 0);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 0);
    assert_eq!(change_log_count(repo.path()), 0);
    assert_no_staging_residue(repo.path());
}
