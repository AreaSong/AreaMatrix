use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, CoreError, DuplicateStrategy, FileEntry, FileFilter,
    ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const S1_22: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-22-conflict-duplicate.md");
const S1_24: &str = include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-24-replace-confirm.md");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document or source to contain `{needle}`"
    );
}

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

fn copied_options(strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: None,
        duplicate_strategy: strategy,
    }
}

fn indexed_options(strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Indexed,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: None,
        duplicate_strategy: strategy,
    }
}

fn all_active_files_filter() -> FileFilter {
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
        .expect("count file rows by status")
}

fn change_log_actions(repo: &Path) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT action FROM change_log ORDER BY id ASC")
        .expect("prepare change log action query");
    statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query change log actions")
        .map(|row| row.expect("read change log action"))
        .collect()
}

fn file_status_and_path(repo: &Path, file_id: i64) -> (String, String) {
    open_db(repo)
        .query_row(
            "SELECT status, path FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read file status and path")
}

fn change_log_detail(repo: &Path, file_id: i64, action: &str) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log WHERE file_id = ?1 AND action = ?2",
            (file_id, action),
            |row| row.get(0),
        )
        .expect("read change log detail json");
    serde_json::from_str(&detail_json).expect("parse change log detail")
}

fn install_deleted_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_deleted_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'deleted'
             BEGIN
                 SELECT RAISE(FAIL, 'forced deleted change log failure');
             END;",
        )
        .expect("install deleted change log failure trigger");
}

fn import_copied_duplicate_fixture(repo: &Path, source: &Path) -> FileEntry {
    import_file(
        path_string(repo),
        path_string(source),
        copied_options(DuplicateStrategy::Skip),
    )
    .expect("import first repo-owned duplicate file")
}

fn import_indexed_overwrite(repo: &Path, source: &Path) -> FileEntry {
    import_file(
        path_string(repo),
        path_string(source),
        indexed_options(DuplicateStrategy::Overwrite),
    )
    .expect("overwrite repo-owned duplicate with indexed import after confirmation")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn assert_no_staging_residue(repo: &Path) {
    assert_eq!(count_file_rows(repo, "staging"), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

fn assert_archived_repo_owned_duplicate(repo: &Path, first: &FileEntry) -> String {
    let (old_status, archived_path) = file_status_and_path(repo, first.id);
    assert_eq!(old_status, "deleted");
    assert!(archived_path.starts_with(".areamatrix/trash/replace-"));
    assert_eq!(
        fs::read(repo.join(&archived_path)).expect("read archived repo-owned duplicate"),
        b"same bytes"
    );

    let deleted_detail = change_log_detail(repo, first.id, "deleted");
    assert_eq!(deleted_detail["reason"], "duplicate_overwrite");
    assert_eq!(deleted_detail["from_path"], first.path);
    assert_eq!(deleted_detail["archived_path"], archived_path);
    assert_eq!(deleted_detail["storage_mode"], "copied");
    archived_path
}

#[test]
fn detect_duplicate_integration_verify_docs_control_map_udl_and_api_are_aligned() {
    for fragment in [
        "C1-09 detect-duplicate",
        "S1-22 conflict-duplicate",
        "S1-24 replace-confirm",
        "`import_file(repo_path, source_path, options)` 内部 hash 检测。",
        "`DuplicateFile { existing_path }`",
        "同 hash 文件默认 `Skip`，UI 能得到 existing path。",
        "`KeepBoth` 产生两个 active entry",
        "`Overwrite` 必须有二次确认 UI 才能接入。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-22 | conflict-duplicate | C1-09 | `import_file`",
        "| S1-24 | replace-confirm | C1-09, C1-10 | `import_file`, `delete_file`",
        "不可 mock：路径校验、init/adopt、导入、重复检测",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "默认选择 Skip。",
        "Keep both 只在最终点击 Import 后创建自动编号副本",
        "Replace 不得直接执行。",
        "Replace 选中后底部主按钮文案改为 `Continue`",
    ] {
        assert_contains(S1_22, fragment);
    }

    for fragment in [
        "Replace 每次必须二次确认。",
        "确认复选框未勾选时不能 Replace。",
        "confirmation sheet itself never calls it",
        "final import uses Core `import_file(..., duplicate_strategy=Overwrite)`",
    ] {
        assert_contains(S1_24, fragment);
    }

    for fragment in [
        "FileEntry import_file(",
        "DuplicateStrategy duplicate_strategy;",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
        "DuplicateFile(string existing_path);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "C1-09 owns duplicate detection",
        "`Skip` and `Ask` return",
        "`KeepBoth` allows a",
        "`Overwrite` is accepted only after the UI",
    ] {
        assert_contains(API_RS, fragment);
    }
}

#[test]
fn detect_duplicate_integration_verify_skip_ask_and_keep_both_match_ui_consumers() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("report.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("report.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(DuplicateStrategy::Skip),
    )
    .expect("import first copied file");

    for strategy in [DuplicateStrategy::Skip, DuplicateStrategy::Ask] {
        let result = import_file(
            path_string(repo.path()),
            path_string(&source_b),
            copied_options(strategy),
        );
        assert_eq!(
            result,
            Err(CoreError::DuplicateFile {
                existing_path: first.path.clone()
            })
        );
    }

    let kept = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options(DuplicateStrategy::KeepBoth),
    )
    .expect("keep both after duplicate conflict selection");

    assert_eq!(first.hash_sha256, kept.hash_sha256);
    assert_eq!(first.path, "finance/report.pdf");
    assert_eq!(kept.path, "finance/report_1.pdf");
    assert_eq!(
        fs::read(repo.path().join(&kept.path)).expect("read kept duplicate final file"),
        b"same bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read duplicate source after keep both"),
        b"same bytes"
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 2);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 0);
    assert_no_staging_residue(repo.path());

    let mut listed = list_files(path_string(repo.path()), all_active_files_filter())
        .expect("list active duplicate files")
        .into_iter()
        .map(|entry| entry.path)
        .collect::<Vec<_>>();
    listed.sort();
    assert_eq!(listed, vec!["finance/report.pdf", "finance/report_1.pdf"]);
}

#[test]
fn detect_duplicate_integration_verify_overwrite_only_runs_for_explicit_strategy() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("report.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("replacement.pdf", b"same bytes");

    let first = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        copied_options(DuplicateStrategy::Skip),
    )
    .expect("import first copied file");

    let blocked = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options(DuplicateStrategy::Ask),
    );
    assert_eq!(
        blocked,
        Err(CoreError::DuplicateFile {
            existing_path: first.path.clone()
        })
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 0);
    assert_eq!(change_log_actions(repo.path()), vec!["imported"]);

    let replacement = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        copied_options(DuplicateStrategy::Overwrite),
    )
    .expect("overwrite duplicate after caller-provided confirmation strategy");

    assert_eq!(replacement.path, first.path);
    assert_ne!(replacement.id, first.id);
    let (old_status, archived_path) = file_status_and_path(repo.path(), first.id);
    assert_eq!(old_status, "deleted");
    assert!(archived_path.starts_with(".areamatrix/trash/replace-"));
    assert_eq!(
        fs::read(repo.path().join(&archived_path)).expect("read archived old file"),
        b"same bytes"
    );
    assert_eq!(
        fs::read(repo.path().join(&replacement.path)).expect("read replacement final file"),
        b"same bytes"
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 1);
    assert_no_staging_residue(repo.path());
    assert_eq!(
        change_log_actions(repo.path()),
        vec!["imported", "deleted", "imported"]
    );
}

#[test]
fn detect_duplicate_integration_verify_indexed_overwrite_archives_repo_owned_duplicate() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("report.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("external.pdf", b"same bytes");

    let first = import_copied_duplicate_fixture(repo.path(), &source_a);
    let original_repo_path = repo.path().join(&first.path);
    assert!(original_repo_path.exists());

    let replacement = import_indexed_overwrite(repo.path(), &source_b);
    let indexed_source_path = path_string(&source_b);
    assert_eq!(replacement.path, indexed_source_path);
    assert_eq!(replacement.storage_mode, StorageMode::Indexed);
    assert_eq!(
        replacement.source_path.as_deref(),
        Some(indexed_source_path.as_str())
    );
    assert_ne!(replacement.id, first.id);
    assert!(!original_repo_path.exists());
    assert_eq!(
        fs::read(&source_b).expect("read indexed source after overwrite"),
        b"same bytes"
    );

    assert_archived_repo_owned_duplicate(repo.path(), &first);
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 1);
    assert_no_staging_residue(repo.path());
    assert_eq!(
        change_log_actions(repo.path()),
        vec!["imported", "deleted", "imported"]
    );

    let imported_detail = change_log_detail(repo.path(), replacement.id, "imported");
    assert_eq!(imported_detail["duplicate_strategy"], "overwrite");
    assert_eq!(imported_detail["replaced_file_id"], first.id);
    assert_eq!(imported_detail["replaced_path"], "finance/report.pdf");

    let listed = list_files(path_string(repo.path()), all_active_files_filter())
        .expect("list active indexed replacement")
        .into_iter()
        .map(|entry| entry.path)
        .collect::<Vec<_>>();
    assert_eq!(listed, vec![indexed_source_path]);
}

#[test]
fn detect_duplicate_integration_verify_indexed_overwrite_restores_archive_on_db_failure() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("report.pdf", b"same bytes");
    let (_source_root_b, source_b) = source_file("external.pdf", b"same bytes");

    let first = import_copied_duplicate_fixture(repo.path(), &source_a);
    let original_repo_path = repo.path().join(&first.path);
    install_deleted_change_log_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        indexed_options(DuplicateStrategy::Overwrite),
    );

    assert_eq!(result, Err(CoreError::Db));
    assert_eq!(
        fs::read(&original_repo_path).expect("read restored original repo-owned file"),
        b"same bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("read indexed source after rollback"),
        b"same bytes"
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 1);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 0);
    assert_no_staging_residue(repo.path());
    assert_eq!(change_log_actions(repo.path()), vec!["imported"]);
}
