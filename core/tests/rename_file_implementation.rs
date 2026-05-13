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

fn file_row(repo: &Path, file_id: i64) -> (String, String, String, Option<String>) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category, source_path FROM files WHERE id = ?1",
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

fn renamed_detail(repo: &Path, file_id: i64) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log WHERE file_id = ?1 AND action = 'renamed'",
            [file_id],
            |row| row.get(0),
        )
        .expect("read renamed change detail");
    serde_json::from_str(&detail_json).expect("parse renamed change detail")
}

#[test]
fn rename_file_implementation_rolls_back_repo_owned_rename_when_overview_fails() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("draft.pdf", b"draft bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import copied file before rename");

    let generated_nodes = repo.path().join(".areamatrix/generated/nodes");
    fs::remove_dir_all(&generated_nodes).expect("remove generated nodes directory");
    fs::write(&generated_nodes, b"not a directory").expect("block generated node output path");

    let result = rename_file(path_string(repo.path()), entry.id, "final.pdf".to_owned());

    assert!(
        matches!(
            result,
            Err(CoreError::Io { .. }
                | CoreError::Config { .. }
                | CoreError::PermissionDenied { .. })
        ),
        "expected generated-overview failure, got {result:?}"
    );
    assert_eq!(
        fs::read(repo.path().join("finance/draft.pdf")).expect("read restored original file"),
        b"draft bytes"
    );
    assert!(!repo.path().join("finance/final.pdf").exists());
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/draft.pdf".to_owned(),
            "draft.pdf".to_owned(),
            "finance".to_owned(),
            Some(path_string(&source)),
        )
    );
    assert_eq!(change_count(repo.path(), "imported"), 1);
    assert_eq!(change_count(repo.path(), "renamed"), 0);
}

#[test]
fn rename_file_implementation_records_module_schema_and_safe_numbered_name() {
    let repo = initialized_repo();
    let (_existing_root, existing_source) = source_file("first.pdf", b"first bytes");
    let (_draft_root, draft_source) = source_file("draft.pdf", b"draft bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&existing_source),
        import_options(StorageMode::Copied, "same.pdf"),
    )
    .expect("import existing same-name file");
    let draft = import_file(
        path_string(repo.path()),
        path_string(&draft_source),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import draft file");

    let renamed = rename_file(path_string(repo.path()), draft.id, "same.pdf".to_owned())
        .expect("rename with conflict-free numbering");

    assert_eq!(renamed.path, "finance/same_1.pdf");
    assert_eq!(renamed.current_name, "same_1.pdf");
    assert_eq!(
        fs::read(repo.path().join(&existing.path)).expect("read existing same-name file"),
        b"first bytes"
    );
    assert_eq!(
        fs::read(repo.path().join(&renamed.path)).expect("read renamed numbered file"),
        b"draft bytes"
    );

    let detail = renamed_detail(repo.path(), draft.id);
    assert_eq!(detail["from"], "draft.pdf");
    assert_eq!(detail["to"], "same_1.pdf");
    assert_eq!(detail["from_path"], "finance/draft.pdf");
    assert_eq!(detail["to_path"], "finance/same_1.pdf");
    assert_eq!(detail["requested_name"], "same.pdf");
    assert_eq!(detail["final_name"], "same_1.pdf");
    assert_eq!(detail["name_conflict_resolved"], true);
    assert_eq!(detail["index_only"], false);
}

#[test]
fn rename_file_implementation_indexed_rename_never_moves_external_source() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("external.pdf", b"external bytes");
    let source_path = path_string(&source);
    let source_bytes = fs::read(&source).expect("read external source before indexed import");
    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        import_options(StorageMode::Indexed, "shown.pdf"),
    )
    .expect("index external file");

    let renamed = rename_file(path_string(repo.path()), entry.id, "display.pdf".to_owned())
        .expect("rename indexed display name");

    assert_eq!(renamed.path, source_path);
    assert_eq!(renamed.source_path.as_deref(), Some(source_path.as_str()));
    assert_eq!(renamed.current_name, "display.pdf");
    assert_eq!(
        fs::read(&source).expect("read external source after indexed rename"),
        source_bytes
    );
    assert!(!repo.path().join("finance").exists());
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            source_path.clone(),
            "display.pdf".to_owned(),
            "finance".to_owned(),
            Some(source_path.clone()),
        )
    );

    let detail = renamed_detail(repo.path(), entry.id);
    assert_eq!(detail["from"], "shown.pdf");
    assert_eq!(detail["to"], "display.pdf");
    assert_eq!(detail["from_path"], source_path);
    assert_eq!(detail["to_path"], renamed.path);
    assert_eq!(detail["index_only"], true);
}
