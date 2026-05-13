use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_file, import_file, init_repo, list_changes, list_files, read_note, rename_file, write_note,
    ChangeFilter, CoreError, DuplicateStrategy, FileFilter, ImportDestination, ImportOptions,
    OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

const API_RS: &str = include_str!("../src/api.rs");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-22-rename-file.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const DB_RENAME_RS: &str = include_str!("../src/db/rename.rs");
const S1_33_RENAME_SHEET: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-33-file-rename-sheet.md");
const STORAGE_RENAME_RS: &str = include_str!("../src/storage/rename.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
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

fn insert_tag(repo: &Path, file_id: i64, tag: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO tags (file_id, tag, added_at) VALUES (?1, ?2, 11)",
            (file_id, tag),
        )
        .expect("insert tag metadata");
}

fn sidecar_path(repo: &Path, relative_path: &str) -> PathBuf {
    let path = repo.join(relative_path);
    let file_name = path.file_name().expect("relative path has file name");
    path.with_file_name(format!("{}.md", file_name.to_string_lossy()))
}

fn tag_value(repo: &Path, file_id: i64) -> String {
    open_db(repo)
        .query_row(
            "SELECT tag FROM tags WHERE file_id = ?1",
            [file_id],
            |row| row.get(0),
        )
        .expect("read tag value")
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

fn renamed_detail(repo: &Path, file_id: i64) -> Value {
    let changes =
        list_changes(path_string(repo), renamed_change_filter(file_id)).expect("list changes");
    assert_eq!(changes.len(), 1);
    serde_json::from_str(&changes[0].detail_json).expect("parse rename detail")
}

fn install_rename_change_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_rename_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'renamed'
             BEGIN
               SELECT RAISE(ABORT, 'forced rename change-log failure');
             END;",
        )
        .expect("install rename change-log failure trigger");
}

#[test]
fn rename_file_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    for fragment in [
        "# C1-22 rename-file",
        "- S1-33 file-rename-sheet",
        "- S1-09 main-list",
        "- S1-12 detail-meta",
        "`rename_file(repo_path, file_id, new_name) -> FileEntry`",
        "更新 `files.current_name`、`files.path`、`updated_at`。",
        "写入 `change_log.renamed`，记录旧名和新名。",
        "Indexed 文件只更新索引显示名，不移动外部源文件。",
        "不覆盖同目录已有文件。",
        "批量重命名属于 Stage 2 的 C2-11。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-33 | file-rename-sheet | C1-22 | `rename_file`",
        "safe rename or index-only metadata",
        "InvalidPath, Conflict, PermissionDenied",
        "| C1-22..C1-26 | `1-5/task-01` 到 `1-5/task-25`",
        "标记为 Real Core 的页面，最终验收不得用 mock、fixture 或静态占位通过。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "入口：`S1-09 main-list`",
        "`S1-12 detail-meta` 的文件操作菜单",
        "即时校验空值、非法字符、未变化、同目录同名冲突。",
        "Index-only 文件：只更新索引中的显示名和 change_log",
        "`Cancel` 关闭 sheet，不写文件、不写 DB。",
        "`Rename` 调用单文件重命名动作",
        "成功后 change_log 出现 rename 记录。",
        "Index-only 文件不会移动源文件。",
    ] {
        assert_contains(S1_33_RENAME_SHEET, fragment);
    }

    for fragment in [
        "FileEntry rename_file(string repo_path, i64 file_id, string new_name);",
        "dictionary FileEntry",
        "string path;",
        "string current_name;",
        "StorageMode storage_mode;",
        "string? source_path;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
        "Conflict(string path);",
        "PermissionDenied(string path);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "`newName` 是文件名而不是路径",
        "Copy / Move 等 repo-owned 文件只在当前目录内执行安全 rename",
        "Indexed 文件只更新 `files.current_name`",
        "不移动、重命名或覆盖外部源文件",
        "同目录同名时复用 C1-10 的安全编号策略",
        "Copy / Move rename 成功后触发 C1-20 generated overview 再生成",
        "`InvalidPath`：`repoPath` 或 `newName` 为空",
        "`Config`：generated overview 输出配置无效。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "pub fn rename_file(repo_path: String, file_id: i64, new_name: String)",
        "storage::rename_file(repo_path, file_id, new_name)",
        "C1-22 owns the user-visible rename contract",
        "Indexed rows are display-name only",
        "Repository-owned rename also triggers C1-20 generated-overview",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "rename_repo_owned_file",
        "rename_indexed_file",
        "dedup::resolve_rename_path",
        "move_recoverable_file",
        "db::rename_active_file",
        "NoteSidecarPlan",
        "overview::regenerate_for_node",
    ] {
        assert_contains(STORAGE_RENAME_RS, fragment);
    }

    for fragment in [
        "transaction()",
        "UPDATE files",
        "SET path = ?2",
        "current_name = ?3",
        "INSERT INTO change_log",
        "'renamed'",
        "tx.commit()",
    ] {
        assert_contains(DB_RENAME_RS, fragment);
    }
}

#[test]
fn rename_file_integration_verify_repo_owned_flow_reaches_list_detail_log_and_overview() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    let (_source_root, source) = source_file("draft.pdf", b"integration bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import copied file before rename integration");
    write_note(
        path_string(repo.path()),
        entry.id,
        "attached note".to_owned(),
    )
    .expect("write note before rename");
    insert_tag(repo.path(), entry.id, "keep-tag");

    let generated_node = repo.path().join(".areamatrix/generated/nodes/finance.md");
    let generated_before =
        fs::read_to_string(&generated_node).expect("read generated node before rename");
    assert_contains(&generated_before, "draft.pdf");

    let renamed = rename_file(path_string(repo.path()), entry.id, "final.pdf".to_owned())
        .expect("rename copied file");

    assert_eq!(renamed.id, entry.id);
    assert_eq!(renamed.path, "finance/final.pdf");
    assert_eq!(renamed.current_name, "final.pdf");
    assert_eq!(renamed.category, entry.category);
    assert_eq!(renamed.hash_sha256, entry.hash_sha256);
    assert_eq!(renamed.storage_mode, StorageMode::Copied);
    assert_eq!(renamed.source_path, entry.source_path);
    assert_eq!(
        read_note(path_string(repo.path()), entry.id).expect("read note after rename"),
        Some("attached note".to_owned())
    );
    assert_eq!(tag_value(repo.path(), entry.id), "keep-tag");
    assert_eq!(
        list_files(path_string(repo.path()), file_filter()).expect("list files after rename"),
        vec![renamed.clone()]
    );
    assert_eq!(
        get_file(path_string(repo.path()), entry.id).expect("get renamed file"),
        renamed
    );
    assert!(!repo.path().join("finance/draft.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("finance/final.pdf")).expect("read renamed file"),
        b"integration bytes"
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
        "generated overview should not keep the old filename"
    );

    let detail = renamed_detail(repo.path(), entry.id);
    assert_eq!(detail["from_path"], "finance/draft.pdf");
    assert_eq!(detail["to_path"], "finance/final.pdf");
    assert_eq!(detail["requested_name"], "final.pdf");
    assert_eq!(detail["name_conflict_resolved"], false);
    assert_eq!(detail["storage_mode"], "copied");
    assert_eq!(detail["index_only"], false);
    assert!(!sidecar_path(repo.path(), "finance/draft.pdf").exists());
    assert_eq!(
        fs::read_to_string(sidecar_path(repo.path(), "finance/final.pdf"))
            .expect("read renamed note sidecar"),
        "attached note"
    );
    assert_eq!(change_count(repo.path(), "renamed"), 1);
    assert_eq!(sqlite_integrity_check(repo.path()), "ok");
    assert!(foreign_key_violations(repo.path()).is_empty());
}

#[test]
fn rename_file_integration_verify_indexed_flow_updates_metadata_without_external_mutation() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("external.pdf", b"external bytes");
    let source_path = path_string(&source);
    let source_before = fs::read(&source).expect("read external source before rename");
    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        import_options(StorageMode::Indexed, "shown.pdf"),
    )
    .expect("index external file");

    let renamed = rename_file(path_string(repo.path()), entry.id, "display.pdf".to_owned())
        .expect("rename indexed display name");

    assert_eq!(renamed.id, entry.id);
    assert_eq!(renamed.path, source_path);
    assert_eq!(renamed.source_path.as_deref(), Some(source_path.as_str()));
    assert_eq!(renamed.current_name, "display.pdf");
    assert_eq!(renamed.storage_mode, StorageMode::Indexed);
    assert_eq!(
        fs::read(&source).expect("read external source after indexed rename"),
        source_before
    );
    assert!(!repo.path().join("finance").exists());
    assert_eq!(
        list_files(path_string(repo.path()), file_filter()).expect("list indexed file"),
        vec![renamed.clone()]
    );
    assert_eq!(
        get_file(path_string(repo.path()), entry.id).expect("get indexed renamed file"),
        renamed
    );

    let detail = renamed_detail(repo.path(), entry.id);
    assert_eq!(detail["from_path"], source_path);
    assert_eq!(detail["to_path"], source_path);
    assert_eq!(detail["requested_name"], "display.pdf");
    assert_eq!(detail["final_name"], "display.pdf");
    assert_eq!(detail["storage_mode"], "indexed");
    assert_eq!(detail["index_only"], true);
    assert_eq!(change_count(repo.path(), "renamed"), 1);
}

#[test]
fn rename_file_integration_verify_failure_keeps_consumers_on_original_state() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("draft.pdf", b"draft bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import copied file before forced failure");
    install_rename_change_log_failure(repo.path());

    let failed = rename_file(path_string(repo.path()), entry.id, "final.pdf".to_owned());

    assert!(matches!(failed, Err(CoreError::Db { .. })));
    assert_eq!(
        fs::read(repo.path().join("finance/draft.pdf")).expect("read original file"),
        b"draft bytes"
    );
    assert!(!repo.path().join("finance/final.pdf").exists());
    assert_eq!(
        list_files(path_string(repo.path()), file_filter()).expect("list files after failure"),
        vec![entry.clone()]
    );
    assert_eq!(
        get_file(path_string(repo.path()), entry.id).expect("get original file after failure"),
        entry
    );
    assert_eq!(change_count(repo.path(), "renamed"), 0);
    assert_eq!(sqlite_integrity_check(repo.path()), "ok");
    assert!(foreign_key_violations(repo.path()).is_empty());
}
