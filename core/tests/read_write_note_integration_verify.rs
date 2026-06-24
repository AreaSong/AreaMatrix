use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_file, import_file, init_repo, list_changes, read_note, write_note, ChangeFilter, CoreError,
    DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde_json::Value;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const DB_NOTE_RS: &str = include_str!("../src/db/note.rs");
const NOTE_RS: &str = include_str!("../src/note.rs");
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

fn copied_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("finance/2026".to_owned()),
        override_category: None,
        override_filename: Some("q1-contract.pdf".to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn edited_note_filter(file_id: i64) -> ChangeFilter {
    ChangeFilter {
        file_id: Some(file_id),
        category: None,
        action: Some("edited_note".to_owned()),
        since: None,
        until: None,
        limit: 10,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn note_content(repo: &Path, file_id: i64) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT content_md FROM notes WHERE file_id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .ok()
}

fn sidecar_path(repo: &Path, relative_path: &str) -> PathBuf {
    repo.join(format!("{relative_path}.md"))
}

fn edited_note_count(repo: &Path, file_id: i64) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log
             WHERE file_id = ?1 AND action = 'edited_note'",
            params![file_id],
            |row| row.get(0),
        )
        .expect("count edited_note change-log rows")
}

#[test]
fn read_write_note_integration_verify_docs_api_udl_and_file_note_consumer_stay_aligned() {
    for fragment in [
        "string? read_note(string repo_path, i64 file_id);",
        "void write_note(string repo_path, i64 file_id, string content_md);",
        "FileNotFound(string path);",
        "PermissionDenied(string path);",
        "Io(string message);",
        "Db(string message);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `read_note(repoPath, fileId) throws -> String?`",
        "### `write_note(repoPath, fileId, contentMd) throws`",
        "DB `notes` 表",
        "物理文件 `<filename>.md`",
        "`InFlightTracker` 标记避免 watcher",
        "当前先用 `get_file` + `list_changes` + `read_note` 组合",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "file note contract exposes this read-only query",
        "This API must not create note rows",
        "file note contract writes exactly one note",
        "The app layer owns `InFlightTracker`",
        "Failed writes must preserve the previous note",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "validate_previous_sidecar",
        "SidecarRollback::capture",
        "write_sidecar_atomically",
        "SidecarWritePolicy::CreateNew",
        "persist_temp_without_replace",
        "rollback.restore()?",
    ] {
        assert_contains(NOTE_RS, fragment);
    }

    for fragment in [
        "INSERT INTO notes",
        "ON CONFLICT(file_id) DO UPDATE",
        "INSERT INTO change_log",
        "'edited_note'",
        "tx.commit()",
    ] {
        assert_contains(DB_NOTE_RS, fragment);
    }
}

#[test]
fn read_write_note_integration_verify_real_detail_note_round_trip_has_no_mock_gap() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("contract.pdf", b"contract bytes");
    let source_before = fs::read(&source).expect("read source before note flow");

    let imported = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("import file for detail-note integration");
    let target_before =
        fs::read(repo.path().join(&imported.path)).expect("read target before note");
    let content = "# 客户A 2026 Q1 合同\n\n- 处理状态：已核对金额".to_owned();

    assert_eq!(read_note(path_string(repo.path()), imported.id), Ok(None));
    let detail = get_file(path_string(repo.path()), imported.id).expect("get detail context");
    assert_eq!(detail.id, imported.id);

    write_note(path_string(repo.path()), imported.id, content.clone()).expect("write note");

    assert_eq!(
        read_note(path_string(repo.path()), imported.id),
        Ok(Some(content.clone()))
    );
    assert_eq!(
        fs::read_to_string(sidecar_path(repo.path(), &imported.path)).expect("read sidecar note"),
        content
    );
    assert_eq!(
        note_content(repo.path(), imported.id).as_deref(),
        Some(content.as_str())
    );

    let changes = list_changes(path_string(repo.path()), edited_note_filter(imported.id))
        .expect("list notes");
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].file_id, Some(imported.id));
    assert_eq!(changes[0].action, "edited_note");
    let detail_json: Value =
        serde_json::from_str(&changes[0].detail_json).expect("parse edited_note detail");
    assert_eq!(detail_json["length_before"], 0);
    assert_eq!(detail_json["length_after"], content.chars().count() as i64);
    assert_eq!(detail_json["by"], "user");

    assert_eq!(
        fs::read(&source).expect("read source after note flow"),
        source_before
    );
    assert_eq!(
        fs::read(repo.path().join(&imported.path)).expect("read target after note flow"),
        target_before
    );
}

#[test]
fn read_write_note_integration_verify_missing_file_allows_read_but_rejects_write() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("contract.pdf", b"contract bytes");
    let imported = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("import file for missing-file note flow");
    let content = "saved note".to_owned();

    write_note(path_string(repo.path()), imported.id, content.clone()).expect("write note");
    fs::remove_file(repo.path().join(&imported.path)).expect("remove target file");

    assert_eq!(
        read_note(path_string(repo.path()), imported.id),
        Ok(Some(content.clone()))
    );
    assert!(matches!(
        write_note(
            path_string(repo.path()),
            imported.id,
            "new draft".to_owned()
        ),
        Err(CoreError::FileNotFound { .. })
    ));

    assert_eq!(
        read_note(path_string(repo.path()), imported.id),
        Ok(Some(content.clone()))
    );
    assert_eq!(
        fs::read_to_string(sidecar_path(repo.path(), &imported.path))
            .expect("read preserved sidecar note"),
        content
    );
    assert_eq!(
        note_content(repo.path(), imported.id).as_deref(),
        Some(content.as_str())
    );
    assert_eq!(edited_note_count(repo.path(), imported.id), 1);
}

#[test]
fn read_write_note_integration_verify_unconfirmed_sidecar_is_not_overwritten() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("contract.pdf", b"contract bytes");
    let imported = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("import file for unconfirmed sidecar check");
    let sidecar = sidecar_path(repo.path(), &imported.path);
    fs::write(&sidecar, "user-authored sidecar").expect("write unconfirmed sidecar");

    let result = write_note(path_string(repo.path()), imported.id, "new note".to_owned());

    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert_eq!(
        fs::read_to_string(&sidecar).expect("read preserved user sidecar"),
        "user-authored sidecar"
    );
    assert_eq!(read_note(path_string(repo.path()), imported.id), Ok(None));
    assert_eq!(note_content(repo.path(), imported.id), None);
    assert_eq!(edited_note_count(repo.path(), imported.id), 0);
}
