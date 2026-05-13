use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, rename_file, CoreError, CoreResult, DuplicateStrategy, FileEntry,
    FileOrigin, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode, RepoInitOptions,
    StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-22-rename-file.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const STORAGE_RENAME_RS: &str = include_str!("../src/storage/rename.rs");
const UDL: &str = include_str!("../area_matrix.udl");

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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn count_rows(repo: &Path, table: &str, status: Option<&str>) -> i64 {
    let connection = open_db(repo);
    match status {
        Some(status) => connection
            .query_row(
                &format!("SELECT COUNT(*) FROM {table} WHERE status = ?1"),
                [status],
                |row| row.get(0),
            )
            .expect("count rows by status"),
        None => connection
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .expect("count rows"),
    }
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

fn sidecar_path(repo: &Path, relative_path: &str) -> PathBuf {
    let path = repo.join(relative_path);
    let file_name = path.file_name().expect("relative path has file name");
    path.with_file_name(format!("{}.md", file_name.to_string_lossy()))
}

fn insert_note_and_tag(repo: &Path, file_id: i64, relative_path: &str) {
    open_db(repo)
        .execute_batch(&format!(
            "INSERT INTO notes (file_id, content_md, updated_at)
             VALUES ({file_id}, 'original note', 10);
             INSERT INTO tags (file_id, tag, added_at)
             VALUES ({file_id}, 'keep-tag', 11);"
        ))
        .expect("insert note and tag metadata");
    fs::write(sidecar_path(repo, relative_path), "original note").expect("write note sidecar");
}

fn note_and_tag_snapshot(repo: &Path, file_id: i64) -> (String, String) {
    let connection = open_db(repo);
    let note = connection
        .query_row(
            "SELECT content_md FROM notes WHERE file_id = ?1",
            [file_id],
            |row| row.get(0),
        )
        .expect("read note content");
    let tag = connection
        .query_row(
            "SELECT tag FROM tags WHERE file_id = ?1",
            [file_id],
            |row| row.get(0),
        )
        .expect("read tag value");
    (note, tag)
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn rename_file_contract_exports_core_api_and_udl_signature() {
    fn assert_rename(_: fn(String, i64, String) -> CoreResult<FileEntry>) {}

    assert_rename(rename_file);

    for fragment in [
        "FileEntry rename_file(string repo_path, i64 file_id, string new_name);",
        "dictionary FileEntry",
        "string path;",
        "string current_name;",
        "string? source_path;",
        "enum StorageMode { \"Moved\", \"Copied\", \"Indexed\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn rename_file_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C1-22 rename-file",
        "- S1-33 file-rename-sheet",
        "- S1-09 main-list",
        "- S1-12 detail-meta",
        "`rename_file(repo_path, file_id, new_name) -> FileEntry`",
        "Indexed 文件只更新索引显示名，不移动外部源文件。",
        "不覆盖同目录已有文件。",
        "Copy / Move rename 成功后触发 C1-20 generated overview 再生成",
        "仅当配置显式允许时维护根目录 `AREAMATRIX.md`",
        "批量重命名属于 Stage 2 的 C2-11。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-33 | file-rename-sheet | C1-22 | `rename_file`",
        "| C1-22..C1-26 | `1-5/task-01` 到 `1-5/task-25`",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "C1-22 owns the user-visible rename contract",
        "Indexed rows are display-name only",
        "leaves `files.path`",
        "Repository-owned rename also triggers C1-20 generated-overview",
        "C1-10 conflict-free numbering is reused",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "| `rename_file(repo, file_id, new_name)` | storage | √ | Io / Db / Config / InvalidPath / Conflict / FileNotFound / PermissionDenied |",
        "`newName` 是文件名而不是路径",
        "`files.path`、`files.current_name`、`updated_at`",
        "Indexed 文件只更新 `files.current_name`",
        "不移动、重命名或覆盖外部源文件",
        "Copy / Move rename 成功后触发 C1-20 generated overview 再生成",
        "默认只写\n  `.areamatrix/generated/**`",
        "`FileNotFound`：`fileId` 对应的 active row 不存在",
        "`Db`：SQLite 查询、更新或 change log 写入失败。",
        "`Config`：generated overview 输出配置无效。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for error_name in [
        "InvalidPath",
        "Conflict",
        "FileNotFound",
        "PermissionDenied",
        "Io",
        "Db",
        "Config",
    ] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in ["rename_indexed_file", "rename_indexed_display_name"] {
        assert_contains(STORAGE_RENAME_RS, fragment);
    }
    assert_contains(STORAGE_RENAME_RS, "overview::regenerate_for_node");
}

#[test]
fn rename_file_contract_repo_owned_rename_preserves_identity_metadata_and_logs() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("draft.pdf", b"draft bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import copied file before rename");
    insert_note_and_tag(repo.path(), entry.id, &entry.path);

    let renamed = rename_file(path_string(repo.path()), entry.id, "final.pdf".to_owned())
        .expect("rename copied file");

    assert_eq!(renamed.id, entry.id);
    assert_eq!(renamed.path, "finance/final.pdf");
    assert_eq!(renamed.current_name, "final.pdf");
    assert_eq!(renamed.original_name, entry.original_name);
    assert_eq!(renamed.category, entry.category);
    assert_eq!(renamed.hash_sha256, entry.hash_sha256);
    assert_eq!(renamed.storage_mode, entry.storage_mode);
    assert_eq!(renamed.origin, entry.origin);
    assert_eq!(renamed.source_path, entry.source_path);
    assert_eq!(
        note_and_tag_snapshot(repo.path(), entry.id),
        ("original note".to_owned(), "keep-tag".to_owned())
    );
    assert!(!repo.path().join("finance/draft.pdf").exists());
    assert_eq!(
        fs::read(repo.path().join("finance/final.pdf")).expect("read renamed file"),
        b"draft bytes"
    );
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/final.pdf".to_owned(),
            "final.pdf".to_owned(),
            "finance".to_owned(),
            Some(path_string(&source)),
        )
    );

    let detail = change_detail(repo.path(), entry.id, "renamed");
    assert_eq!(detail["from_path"], "finance/draft.pdf");
    assert_eq!(detail["to_path"], "finance/final.pdf");
    assert_eq!(detail["from_name"], "draft.pdf");
    assert_eq!(detail["requested_name"], "final.pdf");
    assert_eq!(detail["final_name"], "final.pdf");
    assert_eq!(detail["name_conflict_resolved"], false);
    assert_eq!(detail["storage_mode"], "copied");
    assert_eq!(detail["index_only"], false);
    assert_eq!(count_rows(repo.path(), "change_log", None), 2);
}

#[test]
fn rename_file_contract_updates_generated_overview_outputs_without_touching_readme() {
    let repo = initialized_repo();
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    let (_source_root, source) = source_file("draft.pdf", b"draft bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import copied file before rename");

    let generated_root_path = repo.path().join(".areamatrix/generated/root.md");
    let generated_node_path = repo.path().join(".areamatrix/generated/nodes/finance.md");
    let generated_node_before =
        fs::read_to_string(&generated_node_path).expect("read generated node overview");
    assert_contains(&generated_node_before, "draft.pdf");

    let renamed = rename_file(path_string(repo.path()), entry.id, "final.pdf".to_owned())
        .expect("rename copied file");

    assert_eq!(renamed.current_name, "final.pdf");
    let generated_root_after =
        fs::read_to_string(&generated_root_path).expect("read root overview after rename");
    let generated_node_after =
        fs::read_to_string(&generated_node_path).expect("read node overview after rename");
    assert_contains(&generated_root_after, "final.pdf");
    assert_contains(&generated_node_after, "final.pdf");
    assert!(
        !generated_node_after.contains("draft.pdf"),
        "renamed node overview must not keep the old filename"
    );
    assert!(!repo.path().join("AREAMATRIX.md").exists());
    assert_eq!(
        fs::read_to_string(&readme_path).expect("read user README after rename"),
        "user readme\n"
    );
}

#[test]
fn rename_file_contract_indexed_rename_only_changes_display_name() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("external.pdf", b"external bytes");
    let source_path = path_string(&source);
    let source_bytes = fs::read(&source).expect("read external source before rename");
    let entry = import_file(
        path_string(repo.path()),
        source_path.clone(),
        import_options(StorageMode::Indexed, "shown.pdf"),
    )
    .expect("index external source");

    let renamed = rename_file(path_string(repo.path()), entry.id, "display.pdf".to_owned())
        .expect("rename indexed display name");

    assert_eq!(renamed.id, entry.id);
    assert_eq!(renamed.path, source_path);
    assert_eq!(renamed.source_path.as_deref(), Some(source_path.as_str()));
    assert_eq!(renamed.current_name, "display.pdf");
    assert_eq!(renamed.original_name, "external.pdf");
    assert_eq!(renamed.category, "finance");
    assert_eq!(renamed.storage_mode, StorageMode::Indexed);
    assert_eq!(renamed.origin, FileOrigin::Imported);
    assert_eq!(
        fs::read(&source).expect("external source remains untouched"),
        source_bytes
    );
    assert!(!repo.path().join("finance").exists());
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            renamed.path.clone(),
            "display.pdf".to_owned(),
            "finance".to_owned(),
            Some(source_path.clone()),
        )
    );

    let detail = change_detail(repo.path(), entry.id, "renamed");
    assert_eq!(detail["from_path"], source_path);
    assert_eq!(detail["to_path"], renamed.path);
    assert_eq!(detail["from_name"], "shown.pdf");
    assert_eq!(detail["requested_name"], "display.pdf");
    assert_eq!(detail["final_name"], "display.pdf");
    assert_eq!(detail["storage_mode"], "indexed");
    assert_eq!(detail["index_only"], true);
    assert_eq!(count_rows(repo.path(), "change_log", None), 2);
}

#[test]
fn rename_file_contract_same_name_conflict_uses_safe_numbering_without_overwrite() {
    let repo = initialized_repo();
    let (_source_root_a, source_a) = source_file("first.pdf", b"first bytes");
    let (_source_root_b, source_b) = source_file("draft.pdf", b"draft bytes");
    let existing = import_file(
        path_string(repo.path()),
        path_string(&source_a),
        import_options(StorageMode::Copied, "same.pdf"),
    )
    .expect("import existing target");
    let draft = import_file(
        path_string(repo.path()),
        path_string(&source_b),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import draft target");

    let renamed = rename_file(path_string(repo.path()), draft.id, "same.pdf".to_owned())
        .expect("rename with safe numbered target");

    assert_eq!(renamed.path, "finance/same_1.pdf");
    assert_eq!(renamed.current_name, "same_1.pdf");
    assert_eq!(
        fs::read(repo.path().join(&existing.path)).expect("existing target is not overwritten"),
        b"first bytes"
    );
    assert_eq!(
        fs::read(repo.path().join(&renamed.path)).expect("read numbered rename target"),
        b"draft bytes"
    );
    assert!(!repo.path().join("finance/draft.pdf").exists());

    let detail = change_detail(repo.path(), draft.id, "renamed");
    assert_eq!(detail["requested_name"], "same.pdf");
    assert_eq!(detail["final_name"], "same_1.pdf");
    assert_eq!(detail["name_conflict_resolved"], true);
}

#[test]
fn rename_file_contract_rejects_invalid_names_and_missing_ids_without_side_effects() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("draft.pdf", b"draft bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "draft.pdf"),
    )
    .expect("import file before rejected renames");

    for invalid in ["", "bad/name.pdf", "bad:name.pdf"] {
        let result = rename_file(path_string(repo.path()), entry.id, invalid.to_owned());
        assert!(matches!(result, Err(CoreError::InvalidPath { .. })));
    }

    let missing = rename_file(path_string(repo.path()), 999_999, "missing.pdf".to_owned());
    assert!(matches!(missing, Err(CoreError::FileNotFound { .. })));

    assert_eq!(
        fs::read(repo.path().join("finance/draft.pdf")).expect("original file remains"),
        b"draft bytes"
    );
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/draft.pdf".to_owned(),
            "draft.pdf".to_owned(),
            "finance".to_owned(),
            Some(path_string(&source)),
        )
    );
    assert_eq!(count_rows(repo.path(), "files", Some("active")), 1);
    assert_eq!(count_rows(repo.path(), "change_log", None), 1);
}
