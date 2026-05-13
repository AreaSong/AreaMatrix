use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_file, import_file, init_repo, list_changes, list_files, rename_file, ChangeFilter,
    CoreError, DuplicateStrategy, FileFilter, ImportDestination, ImportOptions, OverviewOutput,
    RepoInitMode, RepoInitOptions, StorageMode,
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

fn renamed_change_filter(file_id: i64) -> ChangeFilter {
    ChangeFilter {
        file_id: Some(file_id),
        category: None,
        action: Some("renamed".to_owned()),
        since: None,
        until: None,
        limit: 10,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category, status FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
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

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn sqlite_integrity_check(repo: &Path) -> String {
    open_db(repo)
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .expect("run SQLite integrity_check")
}

fn foreign_key_violations(repo: &Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("PRAGMA foreign_key_check")
        .expect("prepare foreign_key_check");
    let rows = statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("run foreign_key_check");

    rows.map(|row| row.expect("read foreign_key_check row"))
        .collect()
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected `{needle}` in:\n{haystack}"
    );
}

fn assert_clean_metadata(repo: &Path, expected_renamed_changes: i64) {
    assert_eq!(change_count(repo, "renamed"), expected_renamed_changes);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
    assert_eq!(sqlite_integrity_check(repo), "ok");
    assert!(foreign_key_violations(repo).is_empty());
}

#[test]
fn rename_file_validation_success_updates_queries_db_filesystem_and_overview() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    let (_source_root, source) = source_file("draft.pdf", b"validation bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("draft.pdf"),
    )
    .expect("import copied file before rename validation");

    let generated_node = repo.path().join(".areamatrix/generated/nodes/finance.md");
    let generated_before =
        fs::read_to_string(&generated_node).expect("read generated node before rename");
    assert_contains(&generated_before, "draft.pdf");

    let renamed = rename_file(path_string(repo.path()), entry.id, "final.pdf".to_owned())
        .expect("rename copied file during validation");

    assert_eq!(renamed.id, entry.id);
    assert_eq!(renamed.path, "finance/final.pdf");
    assert_eq!(renamed.current_name, "final.pdf");
    assert_eq!(renamed.category, entry.category);
    assert_eq!(renamed.hash_sha256, entry.hash_sha256);
    assert_eq!(renamed.storage_mode, entry.storage_mode);
    assert_eq!(
        get_file(path_string(repo.path()), entry.id),
        Ok(renamed.clone())
    );
    assert_eq!(
        list_files(path_string(repo.path()), file_filter()).expect("list active files"),
        vec![renamed.clone()]
    );
    assert!(!repo.path().join("finance/draft.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("finance/final.pdf")).expect("read renamed file"),
        b"validation bytes"
    );
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/final.pdf".to_owned(),
            "final.pdf".to_owned(),
            "finance".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(
        fs::read_to_string(&readme_path).expect("read user README after rename"),
        "user readme\n"
    );
    let generated_after =
        fs::read_to_string(&generated_node).expect("read generated node after rename");
    assert_contains(&generated_after, "final.pdf");
    assert!(
        !generated_after.contains("draft.pdf"),
        "generated node overview should not keep the old file name"
    );

    let changes = list_changes(path_string(repo.path()), renamed_change_filter(entry.id))
        .expect("list rename changes");
    assert_eq!(changes.len(), 1);
    let detail: Value =
        serde_json::from_str(&changes[0].detail_json).expect("parse rename detail json");
    assert_eq!(detail["from_path"], "finance/draft.pdf");
    assert_eq!(detail["to_path"], "finance/final.pdf");
    assert_eq!(detail["requested_name"], "final.pdf");
    assert_eq!(detail["name_conflict_resolved"], false);
    assert_clean_metadata(repo.path(), 1);
}

#[test]
fn rename_file_validation_rejects_invalid_names_and_missing_ids_without_side_effects() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("draft.pdf", b"draft bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("draft.pdf"),
    )
    .expect("import copied file before rejected rename validation");

    for invalid in [
        "",
        ".",
        "..",
        "bad/name.pdf",
        "bad\\name.pdf",
        "bad:name.pdf",
        "bad\nname.pdf",
    ] {
        let result = rename_file(path_string(repo.path()), entry.id, invalid.to_owned());
        assert!(
            matches!(result, Err(CoreError::InvalidPath { .. })),
            "expected InvalidPath for `{invalid:?}`, got {result:?}"
        );
    }

    let missing = rename_file(path_string(repo.path()), 999_999, "missing.pdf".to_owned());
    assert!(matches!(missing, Err(CoreError::FileNotFound { .. })));

    assert_eq!(
        fs::read(repo.path().join("finance/draft.pdf")).expect("read original file"),
        b"draft bytes"
    );
    assert!(!repo.path().join("finance/missing.pdf").exists());
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/draft.pdf".to_owned(),
            "draft.pdf".to_owned(),
            "finance".to_owned(),
            "active".to_owned(),
        )
    );
    assert_clean_metadata(repo.path(), 0);
}

#[test]
fn rename_file_validation_same_name_call_is_noop_without_db_or_filesystem_writes() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("draft.pdf", b"draft bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("draft.pdf"),
    )
    .expect("import copied file before no-op rename validation");
    let generated_before =
        fs::read_to_string(repo.path().join(".areamatrix/generated/nodes/finance.md"))
            .expect("read generated node before no-op rename");

    let result = rename_file(path_string(repo.path()), entry.id, "draft.pdf".to_owned())
        .expect("same-name rename should be a no-op");

    assert_eq!(result, entry);
    assert_eq!(
        fs::read(repo.path().join("finance/draft.pdf")).expect("read original file"),
        b"draft bytes"
    );
    assert_eq!(
        fs::read_to_string(repo.path().join(".areamatrix/generated/nodes/finance.md"))
            .expect("read generated node after no-op rename"),
        generated_before
    );
    assert_eq!(
        file_row(repo.path(), result.id),
        (
            "finance/draft.pdf".to_owned(),
            "draft.pdf".to_owned(),
            "finance".to_owned(),
            "active".to_owned(),
        )
    );
    assert_clean_metadata(repo.path(), 0);
}
