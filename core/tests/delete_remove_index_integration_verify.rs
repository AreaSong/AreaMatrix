use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    delete_file, get_file, import_file, init_repo, list_changes, list_files, remove_index_entry,
    write_note, ChangeFilter, CoreError, DuplicateStrategy, FileFilter, ImportDestination,
    ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

mod support;

use support::system_trash_home::with_test_system_trash;

const API_RS: &str = include_str!("../src/api.rs");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-23-delete-remove-index.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const DB_DELETE_RS: &str = include_str!("../src/db/delete.rs");
const S1_34_DELETE_CONFIRM: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-34-file-delete-confirm.md");
const STORAGE_DELETE_RS: &str = include_str!("../src/storage/delete.rs");
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

fn active_file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn include_deleted_filter() -> FileFilter {
    FileFilter {
        include_deleted: Some(true),
        ..active_file_filter()
    }
}

fn change_filter(file_id: i64, action: &str) -> ChangeFilter {
    ChangeFilter {
        file_id: Some(file_id),
        category: None,
        action: Some(action.to_owned()),
        since: None,
        until: None,
        limit: 10,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_status(repo: &Path, file_id: i64) -> (String, Option<i64>) {
    open_db(repo)
        .query_row(
            "SELECT status, deleted_at FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read file status")
}

fn action_count(repo: &Path, file_id: i64, action: &str) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log WHERE file_id = ?1 AND action = ?2",
            rusqlite::params![file_id, action],
            |row| row.get(0),
        )
        .expect("count change-log action")
}

fn note_content(repo: &Path, file_id: i64) -> String {
    open_db(repo)
        .query_row(
            "SELECT content_md FROM notes WHERE file_id = ?1",
            [file_id],
            |row| row.get(0),
        )
        .expect("read retained note content")
}

fn latest_change_detail(repo: &Path, file_id: i64, action: &str) -> Value {
    let changes = list_changes(path_string(repo), change_filter(file_id, action))
        .expect("list filtered changes");
    assert_eq!(changes.len(), 1);
    serde_json::from_str(&changes[0].detail_json).expect("parse change detail")
}

fn trash_entries(trash_dir: &Path) -> Vec<PathBuf> {
    fs::read_dir(trash_dir)
        .expect("read trash directory")
        .map(|entry| entry.expect("read trash entry").path())
        .collect()
}

fn archive_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/archives"))
        .expect("read archives directory")
        .map(|entry| entry.expect("read archive entry").path())
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

fn assert_metadata_consistent(repo: &Path) {
    assert_eq!(sqlite_integrity_check(repo), "ok");
    assert!(foreign_key_violations(repo).is_empty());
}

#[test]
fn delete_remove_index_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    for fragment in [
        "# C1-23 delete-remove-index",
        "- S1-34 file-delete-confirm",
        "- S1-12 detail-meta",
        "- S1-09 main-list",
        "`delete_file(repo_path, file_id)`",
        "`remove_index_entry(repo_path, file_id)`",
        "Delete 必须能证明走 Trash，不直接物理删除。",
        "Remove from Index 不删除任何用户原文件。",
        "失败时不清空笔记、不误删其他文件。",
        "批量删除和 Undo 属于 Stage 2。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-34 | file-delete-confirm | C1-23 | `delete_file`, `remove_index_entry`",
        "Trash or index-only removal",
        "FileNotFound, PermissionDenied, Io",
        "| C1-22..C1-26 | `1-5/task-01` 到 `1-5/task-25`",
        "标记为 Real Core 的页面，最终验收不得用 mock、fixture 或静态占位通过。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "入口：`S1-09 main-list`",
        "`S1-12 detail-meta` 缺失文件 banner 的 `Remove from index`",
        "Delete 必须走系统 Trash",
        "Missing / Index-only 条目默认走 `Remove from index`",
        "`Cancel` 关闭 sheet，不写文件、不写 DB。",
        "Remove from index 只移除 AreaMatrix 索引条目",
        "任何失败都不得删除索引以外的其他文件，不得清空用户笔记内容。",
        "Stage 1 不出现永久删除入口。",
    ] {
        assert_contains(S1_34_DELETE_CONFIRM, fragment);
    }

    for fragment in [
        "void delete_file(string repo_path, i64 file_id);",
        "void remove_index_entry(string repo_path, i64 file_id);",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "FileNotFound(string path);",
        "PermissionDenied(string path);",
        "Io(string message);",
        "Db(string message);",
        "Internal(string message);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "`delete_file` 是用户确认后的 repo-owned 删除入口",
        "不提供永久删除参数",
        "Indexed、Adopted、External 或 Missing 条目的索引移除必须使用",
        "`remove_index_entry` 是 index-only 删除入口",
        "`change_log.action = removed_from_index`",
        "不触发 iCloud placeholder 下载。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "pub fn delete_file(repo_path: String, file_id: i64) -> CoreResult<()>",
        "pub fn remove_index_entry(repo_path: String, file_id: i64) -> CoreResult<()>",
        "no `hard` or permanent-delete flag",
        "external source files are never deleted",
        "must not move anything to Trash",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "send_to_system_trash",
        "DeleteArchiveGuard",
        "ensure_repo_owned_entry",
        "ensure_index_removable_entry",
        "db::soft_delete_repo_owned_file",
        "db::remove_index_entry_row",
    ] {
        assert_contains(STORAGE_DELETE_RS, fragment);
    }

    for fragment in [
        "transaction()",
        "status = 'deleted'",
        "INSERT INTO change_log",
        "removed_from_index",
        "rollback_deleted_repo_owned_file",
        "tx.commit()",
    ] {
        assert_contains(DB_DELETE_RS, fragment);
    }
}

#[test]
fn delete_remove_index_integration_verify_delete_reaches_trash_list_detail_and_log() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        fs::write(repo.path().join("README.md"), "user readme\n").expect("write user README");
        fs::create_dir_all(repo.path().join("finance")).expect("create finance directory");
        fs::write(repo.path().join("finance/keep.txt"), b"keep").expect("write unrelated file");
        let (_source_root, source) = source_file("report.pdf", b"report bytes");
        let entry = import_file(
            path_string(repo.path()),
            path_string(&source),
            import_options(StorageMode::Copied, "report.pdf"),
        )
        .expect("import copied file");
        write_note(
            path_string(repo.path()),
            entry.id,
            "metadata survives delete".to_owned(),
        )
        .expect("write note before delete");

        delete_file(path_string(repo.path()), entry.id).expect("delete repo-owned file");

        assert!(!repo.path().join(&entry.path).exists());
        assert_eq!(
            fs::read(trash_dir.join("report.pdf")).expect("read file from system Trash"),
            b"report bytes"
        );
        assert_eq!(
            fs::read(&source).expect("read copied source after delete"),
            b"report bytes"
        );
        assert_eq!(
            fs::read_to_string(repo.path().join("README.md")).expect("read user README"),
            "user readme\n"
        );
        assert_eq!(
            fs::read(repo.path().join("finance/keep.txt")).expect("read unrelated file"),
            b"keep"
        );
        assert_eq!(
            note_content(repo.path(), entry.id),
            "metadata survives delete"
        );
        assert_eq!(file_status(repo.path(), entry.id).0, "deleted");
        assert!(file_status(repo.path(), entry.id).1.is_some());
        assert!(matches!(
            get_file(path_string(repo.path()), entry.id),
            Err(CoreError::FileNotFound { .. })
        ));
        assert_eq!(
            list_files(path_string(repo.path()), active_file_filter())
                .expect("list active files after delete"),
            Vec::new()
        );
        assert_eq!(
            list_files(path_string(repo.path()), include_deleted_filter())
                .expect("list deleted metadata after delete")
                .len(),
            1
        );

        let detail = latest_change_detail(repo.path(), entry.id, "deleted");
        assert_eq!(detail["hard"], false);
        assert_eq!(detail["by"], "user");
        assert_eq!(detail["from_path"], "finance/report.pdf");
        assert_eq!(detail["trash_location"], "system");
        assert_eq!(detail["trashed"], true);
        assert_eq!(archive_entries(repo.path()), Vec::<PathBuf>::new());
        assert_metadata_consistent(repo.path());
    });
}

#[test]
fn delete_remove_index_integration_verify_remove_index_preserves_sources_and_hides_detail() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_present_root, present_source) = source_file("present.pdf", b"present bytes");
        let present = import_file(
            path_string(repo.path()),
            path_string(&present_source),
            import_options(StorageMode::Indexed, "present.pdf"),
        )
        .expect("index present external file");
        let (_missing_root, missing_source) = source_file("missing.pdf", b"missing bytes");
        let missing = import_file(
            path_string(repo.path()),
            path_string(&missing_source),
            import_options(StorageMode::Indexed, "missing.pdf"),
        )
        .expect("index soon-missing external file");
        fs::remove_file(&missing_source).expect("simulate missing external source");

        remove_index_entry(path_string(repo.path()), present.id).expect("remove present index");
        remove_index_entry(path_string(repo.path()), missing.id).expect("remove missing index");

        assert_eq!(
            fs::read(&present_source).expect("read present source after remove-index"),
            b"present bytes"
        );
        assert!(!missing_source.exists());
        assert_eq!(trash_entries(trash_dir), Vec::<PathBuf>::new());
        for file_id in [present.id, missing.id] {
            assert_eq!(file_status(repo.path(), file_id).0, "deleted");
            assert!(matches!(
                get_file(path_string(repo.path()), file_id),
                Err(CoreError::FileNotFound { .. })
            ));
            assert_eq!(action_count(repo.path(), file_id, "removed_from_index"), 1);
        }
        assert_eq!(
            list_files(path_string(repo.path()), active_file_filter())
                .expect("list active files after remove-index"),
            Vec::new()
        );

        let detail = latest_change_detail(repo.path(), present.id, "removed_from_index");
        assert_eq!(detail["by"], "user");
        assert_eq!(detail["index_only"], true);
        assert_eq!(detail["storage_mode"], "indexed");
        assert_eq!(detail["origin"], "imported");
        assert_eq!(detail["path"], path_string(&present_source));
        assert_metadata_consistent(repo.path());
    });
}

#[test]
fn delete_remove_index_integration_verify_rejected_operations_have_no_side_effects() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_indexed_root, indexed_source) = source_file("external.pdf", b"external bytes");
        let indexed = import_file(
            path_string(repo.path()),
            path_string(&indexed_source),
            import_options(StorageMode::Indexed, "external.pdf"),
        )
        .expect("index external file");
        let (_copied_root, copied_source) = source_file("owned.pdf", b"owned bytes");
        let copied = import_file(
            path_string(repo.path()),
            path_string(&copied_source),
            import_options(StorageMode::Copied, "owned.pdf"),
        )
        .expect("import copied file");

        assert!(matches!(
            delete_file(path_string(repo.path()), indexed.id),
            Err(CoreError::PermissionDenied { .. })
        ));
        assert!(matches!(
            remove_index_entry(path_string(repo.path()), copied.id),
            Err(CoreError::PermissionDenied { .. })
        ));

        assert_eq!(
            fs::read(&indexed_source).expect("read indexed source after rejected delete"),
            b"external bytes"
        );
        assert_eq!(
            fs::read(repo.path().join(&copied.path))
                .expect("read copied file after rejected remove"),
            b"owned bytes"
        );
        assert_eq!(
            file_status(repo.path(), indexed.id),
            ("active".to_owned(), None)
        );
        assert_eq!(
            file_status(repo.path(), copied.id),
            ("active".to_owned(), None)
        );
        assert_eq!(action_count(repo.path(), indexed.id, "deleted"), 0);
        assert_eq!(
            action_count(repo.path(), copied.id, "removed_from_index"),
            0
        );
        assert_eq!(trash_entries(trash_dir), Vec::<PathBuf>::new());
        assert_metadata_consistent(repo.path());
    });
}
