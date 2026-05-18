use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    correct_file_category, import_file, init_repo, CoreError, DuplicateStrategy, ImportDestination,
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

fn file_row(repo: &Path, file_id: i64) -> (String, String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category, storage_mode FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read file row")
}

fn latest_moved_detail(repo: &Path, file_id: i64) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log
             WHERE file_id = ?1 AND action = 'moved'
             ORDER BY id DESC LIMIT 1",
            [file_id],
            |row| row.get(0),
        )
        .expect("read latest moved detail");
    serde_json::from_str(&detail_json).expect("parse moved detail")
}

fn moved_change_count(repo: &Path, file_id: i64) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log WHERE file_id = ?1 AND action = 'moved'",
            [file_id],
            |row| row.get(0),
        )
        .expect("count moved change rows")
}

fn undo_action_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM undo_actions", [], |row| row.get(0))
        .expect("count undo action rows")
}

fn update_file_path(repo: &Path, file_id: i64, path: &str) {
    open_db(repo)
        .execute(
            "UPDATE files SET path = ?1 WHERE id = ?2 AND status = 'active'",
            (path, file_id),
        )
        .expect("update file path fixture");
}

fn classifier_yaml(repo: &Path) -> String {
    fs::read_to_string(repo.join(".areamatrix/classifier.yaml")).expect("read classifier config")
}

fn indexed_file(repo: &Path, external_path: &Path, category: &str) -> i64 {
    let current_name = external_path
        .file_name()
        .and_then(|name| name.to_str())
        .expect("fixture has file name");
    let path = path_string(external_path);
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 13,
                ?4, 'indexed', 'adopted', NULL,
                100, 100, 'active'
             )",
            [
                path.as_str(),
                current_name,
                category,
                &format!("{:064x}", path.len()),
            ],
        )
        .expect("insert adopted indexed file row");
    connection.last_insert_rowid()
}

fn install_moved_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_moved_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'moved'
             BEGIN
               SELECT RAISE(ABORT, 'forced classifier correction change_log failure');
             END;",
        )
        .expect("install moved change-log failure trigger");
}

#[test]
fn classifier_correction_moves_repo_owned_file_and_returns_rule_draft_without_saving_rule() {
    let repo = initialized_repo();
    let initial_classifier = classifier_yaml(repo.path());
    let (_source_root, source) = source_file("Q1_contract_report.pdf", b"contract bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "Q1_contract_report.pdf"),
    )
    .expect("import copied file before correction");

    let result = correct_file_category(
        path_string(repo.path()),
        entry.id,
        "finance".to_owned(),
        true,
        true,
    )
    .expect("apply classifier correction");

    assert_eq!(result.updated_file.id, entry.id);
    assert_eq!(result.updated_file.category, "finance");
    assert_eq!(result.updated_file.path, "finance/Q1_contract_report.pdf");
    assert_eq!(result.move_file_requested, true);
    assert_eq!(result.remember_requested, true);
    assert_eq!(result.rule_confirmation_required, true);
    let draft = result
        .rule_draft
        .expect("remember returns a safe classifier rule draft");
    assert_eq!(draft.source_file_id, entry.id);
    assert_eq!(draft.target_category, "finance");
    assert!(draft
        .keyword_candidates
        .iter()
        .any(|candidate| candidate == "contract"));
    assert_eq!(draft.extension_candidates, vec!["pdf"]);

    assert!(!repo.path().join("docs/Q1_contract_report.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("finance/Q1_contract_report.pdf"))
            .expect("read corrected repo-owned file"),
        b"contract bytes"
    );
    assert_eq!(classifier_yaml(repo.path()), initial_classifier);
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/Q1_contract_report.pdf".to_owned(),
            "Q1_contract_report.pdf".to_owned(),
            "finance".to_owned(),
            "copied".to_owned(),
        )
    );

    let detail = latest_moved_detail(repo.path(), entry.id);
    assert_eq!(detail["from_category"], "docs");
    assert_eq!(detail["to_category"], "finance");
    assert_eq!(detail["from_path"], "docs/Q1_contract_report.pdf");
    assert_eq!(detail["to_path"], "finance/Q1_contract_report.pdf");
    assert_eq!(detail["index_only"], false);
    assert_eq!(undo_action_count(repo.path()), 0);
}

#[test]
fn classifier_correction_metadata_only_keeps_repo_owned_file_in_place_when_move_is_false() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("manual.pdf", b"manual bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "manual.pdf"),
    )
    .expect("import copied file before metadata-only correction");

    let result = correct_file_category(
        path_string(repo.path()),
        entry.id,
        "finance".to_owned(),
        false,
        false,
    )
    .expect("apply metadata-only classifier correction");

    assert_eq!(result.updated_file.category, "finance");
    assert_eq!(result.updated_file.path, "docs/manual.pdf");
    assert_eq!(result.rule_draft, None);
    assert_eq!(result.move_file_requested, false);
    assert_eq!(result.remember_requested, false);
    assert_eq!(result.rule_confirmation_required, false);
    assert_eq!(
        fs::read(repo.path().join("docs/manual.pdf")).expect("read unchanged repo-owned path"),
        b"manual bytes"
    );

    let detail = latest_moved_detail(repo.path(), entry.id);
    assert_eq!(detail["kind"], "classifier_correction");
    assert_eq!(detail["from_category"], "docs");
    assert_eq!(detail["to_category"], "finance");
    assert_eq!(detail["from_path"], "docs/manual.pdf");
    assert_eq!(detail["to_path"], "docs/manual.pdf");
    assert_eq!(detail["index_only"], true);
    assert_eq!(detail["remember_requested"], false);
    assert_eq!(undo_action_count(repo.path()), 0);
}

#[test]
fn classifier_correction_never_moves_adopted_indexed_user_file() {
    let repo = initialized_repo();
    let docs = repo.path().join("docs");
    fs::create_dir(&docs).expect("create docs directory");
    let adopted_path = docs.join("adopted-contract.pdf");
    fs::write(&adopted_path, b"adopted bytes").expect("write adopted user file");
    let file_id = indexed_file(repo.path(), &adopted_path, "docs");

    let result = correct_file_category(
        path_string(repo.path()),
        file_id,
        "finance".to_owned(),
        true,
        true,
    )
    .expect("apply adopted metadata-only correction");

    assert_eq!(result.updated_file.category, "finance");
    assert_eq!(result.updated_file.path, path_string(&adopted_path));
    assert_eq!(result.move_file_requested, true);
    assert!(result.rule_draft.is_some());
    assert_eq!(
        fs::read(&adopted_path).expect("read adopted source after correction"),
        b"adopted bytes"
    );
    assert!(!repo.path().join("finance/adopted-contract.pdf").exists());

    let detail = latest_moved_detail(repo.path(), file_id);
    assert_eq!(detail["kind"], "classifier_correction");
    assert_eq!(detail["origin"], "adopted");
    assert_eq!(detail["storage_mode"], "indexed");
    assert_eq!(detail["index_only"], true);
    assert_eq!(undo_action_count(repo.path()), 0);
}

#[test]
fn classifier_correction_does_not_create_c2_07_undo_actions() {
    let repo = initialized_repo();
    let (_move_source_root, move_source) = source_file("move.pdf", b"move bytes");
    let moving = import_file(
        path_string(repo.path()),
        path_string(&move_source),
        import_options(StorageMode::Copied, "docs", "move.pdf"),
    )
    .expect("import copied file before move correction");
    let (_metadata_source_root, metadata_source) = source_file("metadata.pdf", b"metadata bytes");
    let metadata_only = import_file(
        path_string(repo.path()),
        path_string(&metadata_source),
        import_options(StorageMode::Copied, "docs", "metadata.pdf"),
    )
    .expect("import copied file before metadata-only correction");

    correct_file_category(
        path_string(repo.path()),
        moving.id,
        "finance".to_owned(),
        true,
        false,
    )
    .expect("apply moving classifier correction");
    correct_file_category(
        path_string(repo.path()),
        metadata_only.id,
        "finance".to_owned(),
        false,
        true,
    )
    .expect("apply metadata-only classifier correction");

    assert_eq!(undo_action_count(repo.path()), 0);
    assert_eq!(moved_change_count(repo.path(), moving.id), 1);
    assert_eq!(moved_change_count(repo.path(), metadata_only.id), 1);
}

#[test]
fn classifier_correction_rejects_unknown_category_without_side_effects() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("manual.pdf", b"manual bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "manual.pdf"),
    )
    .expect("import copied file before rejected correction");

    let result = correct_file_category(
        path_string(repo.path()),
        entry.id,
        "unknown".to_owned(),
        true,
        true,
    );

    assert!(matches!(result, Err(CoreError::Classify { .. })));
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "docs/manual.pdf".to_owned(),
            "manual.pdf".to_owned(),
            "docs".to_owned(),
            "copied".to_owned(),
        )
    );
    assert_eq!(
        fs::read(repo.path().join("docs/manual.pdf")).expect("read original repo-owned file"),
        b"manual bytes"
    );
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[test]
fn classifier_correction_db_failure_rolls_back_metadata_only_change() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("manual.pdf", b"manual bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "manual.pdf"),
    )
    .expect("import copied file before rollback test");
    install_moved_change_log_failure(repo.path());

    let result = correct_file_category(
        path_string(repo.path()),
        entry.id,
        "finance".to_owned(),
        false,
        false,
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "docs/manual.pdf".to_owned(),
            "manual.pdf".to_owned(),
            "docs".to_owned(),
            "copied".to_owned(),
        )
    );
    assert_eq!(
        fs::read(repo.path().join("docs/manual.pdf")).expect("read file after rollback"),
        b"manual bytes"
    );
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[test]
fn classifier_correction_missing_active_row_maps_to_documented_db_error() {
    let repo = initialized_repo();

    let result = correct_file_category(
        path_string(repo.path()),
        42,
        "finance".to_owned(),
        true,
        false,
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
}

#[test]
fn classifier_correction_missing_repo_owned_file_maps_to_documented_io_error() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("missing.pdf", b"missing bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "missing.pdf"),
    )
    .expect("import copied file before missing-file correction");
    fs::remove_file(repo.path().join("docs/missing.pdf")).expect("remove repo-owned file");

    let result = correct_file_category(
        path_string(repo.path()),
        entry.id,
        "finance".to_owned(),
        true,
        false,
    );

    assert!(matches!(result, Err(CoreError::Io { .. })));
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "docs/missing.pdf".to_owned(),
            "missing.pdf".to_owned(),
            "docs".to_owned(),
            "copied".to_owned(),
        )
    );
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}

#[test]
fn classifier_correction_invalid_repo_owned_path_maps_to_documented_conflict_error() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("unsafe.pdf", b"unsafe bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "unsafe.pdf"),
    )
    .expect("import copied file before invalid-path correction");
    update_file_path(repo.path(), entry.id, "/outside/unsafe.pdf");

    let result = correct_file_category(
        path_string(repo.path()),
        entry.id,
        "finance".to_owned(),
        true,
        false,
    );

    assert!(matches!(result, Err(CoreError::Conflict { .. })));
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "/outside/unsafe.pdf".to_owned(),
            "unsafe.pdf".to_owned(),
            "docs".to_owned(),
            "copied".to_owned(),
        )
    );
    assert_eq!(
        fs::read(repo.path().join("docs/unsafe.pdf")).expect("read unchanged repo-owned file"),
        b"unsafe bytes"
    );
    assert_eq!(moved_change_count(repo.path(), entry.id), 0);
}
