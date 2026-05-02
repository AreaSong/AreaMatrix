use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_files, rename_file, CoreError, DuplicateStrategy, FileEntry,
    FileFilter, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions,
    StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

mod support;
use support::system_trash_home::with_test_system_trash;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const DESTINATION_RS: &str = include_str!("../src/storage/destination.rs");
const IMPORT_RS: &str = include_str!("../src/storage/import.rs");
const REPLACEMENT_TRASH_RS: &str = include_str!("../src/storage/replacement_trash.rs");
const S1_23_CONFLICT_NAME: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-23-conflict-name.md");
const S1_24_REPLACE_CONFIRM: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-24-replace-confirm.md");
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

fn copied_options(filename: &str, strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some(filename.to_owned()),
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
        .expect("prepare change-log action query");
    statement
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query change-log actions")
        .map(|row| row.expect("read change-log action"))
        .collect()
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

fn assert_no_staging_residue(repo: &Path) {
    assert_eq!(count_file_rows(repo, "staging"), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

fn import_with_name(
    repo: &Path,
    source: &Path,
    filename: &str,
    strategy: DuplicateStrategy,
) -> Result<FileEntry, CoreError> {
    import_file(
        path_string(repo),
        path_string(source),
        copied_options(filename, strategy),
    )
}

#[test]
fn resolve_name_conflict_integration_verify_docs_control_map_udl_and_consumers_stay_aligned() {
    for fragment in [
        "C1-10 resolve-name-conflict",
        "S1-23 conflict-name",
        "S1-24 replace-confirm",
        "- `import_file(repo_path, source_path, options)`",
        "- `rename_file(repo_path, file_id, new_name)`",
        "同名不同 hash 不覆盖旧文件。",
        "Replace 路径必须经过 S1-24",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-23 | conflict-name | C1-10 | `import_file`, `rename_file`",
        "| S1-24 | replace-confirm | C1-09, C1-10 | `import_file`, `delete_file`",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "默认选择安全策略：保留两份并自动编号。",
        "重命名只影响导入的新文件，不影响已有文件。",
        "Replace 必须进入二次确认，不得在当前区域直接替换。",
        "UI preview contract 必须覆盖 hash 不同、自动编号成功、自动编号失败三个分支",
    ] {
        assert_contains(S1_23_CONFLICT_NAME, fragment);
    }

    for fragment in [
        "Replace 每次必须二次确认。",
        "确认前不移动、不删除、不覆盖任何文件。",
        "confirmation sheet itself never calls it",
        "final import uses Core `import_file(..., duplicate_strategy=Overwrite)`",
    ] {
        assert_contains(S1_24_REPLACE_CONFIRM, fragment);
    }

    for fragment in [
        "FileEntry import_file(",
        "FileEntry rename_file(string repo_path, i64 file_id, string new_name);",
        "string? override_filename;",
        "DuplicateStrategy duplicate_strategy;",
        "string path;",
        "string current_name;",
        "enum DuplicateStrategy { \"Skip\", \"Overwrite\", \"KeepBoth\", \"Ask\" };",
        "Conflict();",
        "InvalidPath();",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "C1-10 owns same-name conflict handling",
        "must not overwrite an existing user file by default",
        "Dangerous replacement remains explicit through `DuplicateStrategy::Overwrite`",
        "C1-10 exposes this entry point for manual name-conflict resolution",
    ] {
        assert_contains(API_RS, fragment);
    }
}

#[test]
fn resolve_name_conflict_integration_verify_storage_quality_stays_platform_neutral() {
    for (path, source) in [
        ("core/src/storage/import.rs", IMPORT_RS),
        ("core/src/storage/destination.rs", DESTINATION_RS),
        (
            "core/src/storage/replacement_trash.rs",
            REPLACEMENT_TRASH_RS,
        ),
    ] {
        assert!(
            source.lines().count() <= 500,
            "{path} must stay within the coding-standard 500 line limit"
        );
    }

    for forbidden in [
        "trash::macos",
        "DeleteMethod",
        "TrashContextExtMacos",
        "NsFileManager",
        "target_os = \"macos\"",
    ] {
        assert!(
            !DESTINATION_RS.contains(forbidden),
            "destination.rs must not depend on macOS-specific Trash APIs"
        );
        assert!(
            !REPLACEMENT_TRASH_RS.contains(forbidden),
            "replacement_trash.rs must not depend on macOS-specific Trash APIs"
        );
    }
}

#[test]
fn resolve_name_conflict_integration_verify_default_import_keeps_both_without_overwrite() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("incoming-a.pdf", b"original bytes");
    let (_source_root_b, source_b) = source_file("incoming-b.pdf", b"incoming bytes");

    let first = import_with_name(repo.path(), &source_a, "same.pdf", DuplicateStrategy::Skip)
        .expect("import first same-name target");
    let second = import_with_name(repo.path(), &source_b, "same.pdf", DuplicateStrategy::Skip)
        .expect("default same-name import should resolve a numbered filename");

    assert_eq!(first.path, "finance/same.pdf");
    assert_eq!(second.path, "finance/same_1.pdf");
    assert_eq!(second.current_name, "same_1.pdf");
    assert_eq!(
        fs::read(repo.path().join(&first.path)).expect("read original target"),
        b"original bytes"
    );
    assert_eq!(
        fs::read(repo.path().join(&second.path)).expect("read numbered target"),
        b"incoming bytes"
    );
    assert_eq!(
        fs::read(&source_b).expect("copied import leaves source untouched"),
        b"incoming bytes"
    );
    assert_eq!(
        file_row(repo.path(), second.id),
        (
            "finance/same_1.pdf".to_owned(),
            "same_1.pdf".to_owned(),
            "active".to_owned(),
        )
    );
    assert_eq!(count_file_rows(repo.path(), "active"), 2);
    assert_eq!(count_file_rows(repo.path(), "deleted"), 0);
    assert_no_staging_residue(repo.path());

    let listed = list_files(path_string(repo.path()), all_active_files_filter())
        .expect("list active files for consuming UI");
    assert_eq!(listed.len(), 2);

    let detail = change_detail(repo.path(), second.id, "imported");
    assert_eq!(detail["requested_name"], "same.pdf");
    assert_eq!(detail["final_name"], "same_1.pdf");
    assert_eq!(detail["final_path"], "finance/same_1.pdf");
    assert_eq!(detail["name_conflict_resolved"], true);
    assert_eq!(
        change_log_actions(repo.path()),
        vec!["imported", "imported"]
    );
}

#[test]
fn resolve_name_conflict_integration_verify_manual_rename_is_safe_numbered_resolution() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("existing.pdf", b"existing bytes");
    let (_source_root_b, source_b) = source_file("draft.pdf", b"draft bytes");

    let existing = import_with_name(repo.path(), &source_a, "same.pdf", DuplicateStrategy::Skip)
        .expect("import existing target");
    let draft = import_with_name(repo.path(), &source_b, "draft.pdf", DuplicateStrategy::Skip)
        .expect("import file to rename");

    let renamed = rename_file(path_string(repo.path()), draft.id, "same.pdf".to_owned())
        .expect("rename should auto-number instead of overwriting");

    assert_eq!(renamed.path, "finance/same_1.pdf");
    assert_eq!(renamed.current_name, "same_1.pdf");
    assert_eq!(
        fs::read(repo.path().join(&existing.path)).expect("read existing target"),
        b"existing bytes"
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
    assert_no_staging_residue(repo.path());

    let detail = change_detail(repo.path(), draft.id, "renamed");
    assert_eq!(detail["from_path"], "finance/draft.pdf");
    assert_eq!(detail["to_path"], "finance/same_1.pdf");
    assert_eq!(detail["requested_name"], "same.pdf");
    assert_eq!(detail["final_name"], "same_1.pdf");
    assert_eq!(detail["name_conflict_resolved"], true);
    assert_eq!(
        change_log_actions(repo.path()),
        vec!["imported", "imported", "renamed"]
    );
}

#[test]
fn resolve_name_conflict_integration_verify_overwrite_is_explicit_confirmed_strategy_only() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (_source_root_a, source_a) = source_file("existing.pdf", b"existing bytes");
        let (_source_root_b, source_b) = source_file("incoming.pdf", b"incoming bytes");
        let (_source_root_c, source_c) = source_file("replacement.pdf", b"replacement bytes");

        let existing =
            import_with_name(repo.path(), &source_a, "same.pdf", DuplicateStrategy::Skip)
                .expect("import existing target");
        let safe_default =
            import_with_name(repo.path(), &source_b, "same.pdf", DuplicateStrategy::Skip)
                .expect("default path keeps both before any explicit replace");

        assert_eq!(safe_default.path, "finance/same_1.pdf");
        assert_eq!(
            fs::read(repo.path().join("finance/same.pdf")).expect("read original before replace"),
            b"existing bytes"
        );

        let replacement = import_with_name(
            repo.path(),
            &source_c,
            "same.pdf",
            DuplicateStrategy::Overwrite,
        )
        .expect("overwrite runs only when caller supplies confirmed strategy");

        assert_eq!(replacement.path, "finance/same.pdf");
        assert_eq!(replacement.current_name, "same.pdf");
        assert_ne!(replacement.id, existing.id);
        assert_eq!(
            fs::read(repo.path().join("finance/same.pdf")).expect("read replacement target"),
            b"replacement bytes"
        );
        assert_eq!(
            fs::read(repo.path().join("finance/same_1.pdf")).expect("read kept default copy"),
            b"incoming bytes"
        );
        assert_eq!(count_file_rows(repo.path(), "active"), 2);
        assert_eq!(count_file_rows(repo.path(), "deleted"), 1);
        assert_no_staging_residue(repo.path());

        let (archived_path, archived_name, old_status) = file_row(repo.path(), existing.id);
        assert_eq!(archived_name, "same.pdf");
        assert_eq!(old_status, "deleted");
        assert!(archived_path.starts_with("system-trash://replace-"));
        assert!(!repo.path().join(".areamatrix/trash").exists());
        assert_eq!(
            fs::read(trash_dir.join("same.pdf")).expect("read old target from system Trash"),
            b"existing bytes"
        );

        let deleted_detail = change_detail(repo.path(), existing.id, "deleted");
        assert_eq!(deleted_detail["reason"], "name_conflict_replace");
        assert_eq!(deleted_detail["trash_location"], "system");
        assert_eq!(deleted_detail["trashed"], true);

        let import_detail = change_detail(repo.path(), replacement.id, "imported");
        assert_eq!(import_detail["duplicate_strategy"], "overwrite");
        assert_eq!(import_detail["replace_reason"], "name_conflict_replace");
        assert_eq!(import_detail["replaced_file_id"], existing.id);
        assert_eq!(import_detail["replaced_path"], "finance/same.pdf");
        assert_eq!(import_detail["final_path"], "finance/same.pdf");
        assert_eq!(
            change_log_actions(repo.path()),
            vec!["imported", "imported", "deleted", "imported"]
        );
    });
}
