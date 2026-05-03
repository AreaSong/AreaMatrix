use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_file, import_file, init_repo, list_changes, list_files, list_tree_json, move_to_category,
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

fn file_filter(category: &str) -> FileFilter {
    FileFilter {
        category: Some(category.to_owned()),
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

fn moved_change_detail(repo: &Path, file_id: i64) -> Value {
    let changes = list_changes(path_string(repo), moved_change_filter(file_id))
        .expect("list moved changes through Core API");
    assert_eq!(changes.len(), 1);
    serde_json::from_str(&changes[0].detail_json).expect("parse moved change detail JSON")
}

fn parse_tree(repo: &Path) -> Value {
    let tree_json =
        list_tree_json(path_string(repo), "en".to_owned()).expect("list repository tree JSON");
    serde_json::from_str(&tree_json).expect("parse list_tree_json output")
}

fn child_by_slug<'a>(node: &'a Value, slug: &str) -> &'a Value {
    node["children"]
        .as_array()
        .expect("TreeNode children should be an array")
        .iter()
        .find(|child| child["slug"] == slug)
        .unwrap_or_else(|| panic!("expected child slug `{slug}`"))
}

fn list_paths(repo: &Path, category: &str) -> Vec<String> {
    let mut paths: Vec<String> = list_files(path_string(repo), file_filter(category))
        .expect("list files by category through Core API")
        .into_iter()
        .map(|entry| entry.path)
        .collect();
    paths.sort();
    paths
}

#[test]
fn move_to_category_validation_success_is_visible_in_tree_list_detail_and_log() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"report bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import copied file before validation move");

    let moved = move_to_category(path_string(repo.path()), entry.id, "docs".to_owned())
        .expect("move copied file to docs category");

    assert_eq!(moved.path, "docs/report.pdf");
    assert_eq!(moved.category, "docs");
    assert_eq!(
        get_file(path_string(repo.path()), entry.id),
        Ok(moved.clone())
    );
    assert_eq!(list_paths(repo.path(), "docs"), vec!["docs/report.pdf"]);
    assert!(list_paths(repo.path(), "finance").is_empty());

    let tree = parse_tree(repo.path());
    assert_eq!(tree["file_count"], 1);
    assert_eq!(child_by_slug(&tree, "docs")["file_count"], 1);
    assert_eq!(
        fs::read(repo.path().join(&moved.path)).expect("read moved repo-owned file"),
        b"report bytes"
    );

    let detail = moved_change_detail(repo.path(), entry.id);
    assert_eq!(detail["from_category"], "finance");
    assert_eq!(detail["to_category"], "docs");
    assert_eq!(detail["from_path"], "finance/report.pdf");
    assert_eq!(detail["to_path"], "docs/report.pdf");
    assert_eq!(detail["index_only"], false);
}

#[test]
fn move_to_category_validation_target_conflict_is_numbered_without_overwrite() {
    let repo = initialized_repo();
    let (_existing_root, existing_source) = source_file("existing.pdf", b"existing bytes");
    let (_moving_root, moving_source) = source_file("moving.pdf", b"moving bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&existing_source),
        import_options(StorageMode::Copied, "docs", "same.pdf"),
    )
    .expect("import existing docs file");
    let moving = import_file(
        path_string(repo.path()),
        path_string(&moving_source),
        import_options(StorageMode::Copied, "finance", "same.pdf"),
    )
    .expect("import moving finance file");

    let moved = move_to_category(path_string(repo.path()), moving.id, "docs".to_owned())
        .expect("move with safe numbered target");

    assert_eq!(moved.path, "docs/same_1.pdf");
    assert_eq!(moved.current_name, "same_1.pdf");
    assert_eq!(
        fs::read(repo.path().join(&existing.path)).expect("read existing target after move"),
        b"existing bytes"
    );
    assert_eq!(
        fs::read(repo.path().join(&moved.path)).expect("read numbered moved target"),
        b"moving bytes"
    );
    assert_eq!(
        list_paths(repo.path(), "docs"),
        vec!["docs/same.pdf", "docs/same_1.pdf"]
    );

    let detail = moved_change_detail(repo.path(), moving.id);
    assert_eq!(detail["name_conflict_resolved"], true);
    assert_eq!(detail["renamed_to"], "same_1.pdf");
}

#[test]
fn move_to_category_validation_indexed_file_updates_metadata_only() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("external.pdf", b"external bytes");
    let source_path = path_string(&source);
    let source_bytes = fs::read(&source).expect("read indexed source before move");
    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        import_options(StorageMode::Indexed, "finance", "shown.pdf"),
    )
    .expect("index external file before validation move");

    let moved = move_to_category(path_string(repo.path()), entry.id, "docs".to_owned())
        .expect("move indexed metadata to docs category");

    assert_eq!(moved.path, source_path);
    assert_eq!(moved.category, "docs");
    assert_eq!(moved.current_name, "shown.pdf");
    assert_eq!(
        get_file(path_string(repo.path()), entry.id),
        Ok(moved.clone())
    );
    assert_eq!(list_paths(repo.path(), "docs"), vec![moved.path.clone()]);
    assert_eq!(
        fs::read(&source).expect("read indexed external source after move"),
        source_bytes
    );
    assert!(!repo.path().join("docs/shown.pdf").exists());

    let detail = moved_change_detail(repo.path(), entry.id);
    assert_eq!(detail["index_only"], true);
    assert_eq!(detail["to_path"], moved.path);
}

#[test]
fn move_to_category_validation_classifier_failure_preserves_state() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("report.pdf", b"report bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "finance", "report.pdf"),
    )
    .expect("import copied file before classifier failure");
    fs::write(
        repo.path().join(".areamatrix/classifier.yaml"),
        "not: [valid",
    )
    .expect("corrupt classifier rules");

    let result = move_to_category(path_string(repo.path()), entry.id, "docs".to_owned());

    assert!(matches!(result, Err(CoreError::Classify { .. })));
    assert_eq!(
        fs::read(repo.path().join("finance/report.pdf")).expect("read original file"),
        b"report bytes"
    );
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
fn move_to_category_validation_missing_active_file_returns_file_not_found() {
    let repo = initialized_repo();

    let result = move_to_category(path_string(repo.path()), 9_999, "docs".to_owned());

    assert!(matches!(result, Err(CoreError::FileNotFound { .. })));
    assert_eq!(moved_change_count(repo.path(), 9_999), 0);
}
