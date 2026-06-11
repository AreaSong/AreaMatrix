use std::{fs, path::Path};

use area_matrix_core::{
    get_file, init_repo, list_changes, read_note, ChangeFilter, ChangeLogEntry, CoreError,
    CoreResult, FileAvailabilityStatus, FileEntry, OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-34-c4-07-validation.md"
);
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-4-multiplatform/C4-07-mobile-detail.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CONTRACT_TEST: &str = include_str!("mobile_detail_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("mobile_detail_implementation.rs");
const FAILURE_TEST: &str = include_str!("mobile_detail_failure_recovery.rs");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options())
        .expect("initialize repository for mobile detail validation");
    repo
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn mobile_log_filter(file_id: i64) -> ChangeFilter {
    ChangeFilter {
        file_id: Some(file_id),
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 10,
        offset: 0,
    }
}

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) {
    let path = repo.join(relative_path);
    let parent = path.parent().expect("fixture path has parent");
    fs::create_dir_all(parent).expect("create fixture parent directory");
    fs::write(path, bytes).expect("write fixture user file");
}

fn insert_file_row(repo: &Path, relative_path: &str, write_backing_file: bool) -> i64 {
    if write_backing_file {
        write_repo_file(
            repo,
            relative_path,
            b"filesystem bytes are not detail metadata",
        );
    }

    let current_name = relative_path
        .rsplit('/')
        .next()
        .expect("fixture path has filename");
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, 'docs', 407,
                ?3, 'copied', 'imported', NULL,
                4070, 4071, 'active'
             )",
            params![relative_path, current_name, format!("{:064x}", 407)],
        )
        .expect("insert mobile detail file row");
    connection.last_insert_rowid()
}

fn insert_change(repo: &Path, file_id: i64, action: &str, occurred_at: i64) {
    open_db(repo)
        .execute(
            "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![
                file_id,
                action,
                r#"{"source":"c4-07-validation"}"#,
                occurred_at
            ],
        )
        .expect("insert mobile detail change-log row");
}

fn insert_note(repo: &Path, file_id: i64, relative_path: &str, content: &str) {
    open_db(repo)
        .execute(
            "INSERT INTO notes (file_id, content_md, updated_at)
             VALUES (?1, ?2, 4072)",
            params![file_id, content],
        )
        .expect("insert mobile detail note row");
    fs::write(repo.join(format!("{relative_path}.md")), content).expect("write note sidecar");
}

fn metadata_counts(repo: &Path) -> (i64, i64, i64) {
    let connection = open_db(repo);
    let files = connection
        .query_row("SELECT COUNT(*) FROM files", [], |row| row.get(0))
        .expect("count file rows");
    let changes = connection
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change-log rows");
    let notes = connection
        .query_row("SELECT COUNT(*) FROM notes", [], |row| row.get(0))
        .expect("count note rows");
    (files, changes, notes)
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn mobile_detail_validation_proves_ui_ready_segments_without_writes() {
    let repo = initialized_repo();
    let file_id = insert_file_row(repo.path(), "docs/report.pdf", true);
    insert_change(repo.path(), file_id, "imported", 100);
    insert_change(repo.path(), file_id, "edited_note", 200);
    insert_note(
        repo.path(),
        file_id,
        "docs/report.pdf",
        "Reviewed from C4-07 validation.",
    );
    let before_counts = metadata_counts(repo.path());
    let before_file = fs::read(repo.path().join("docs/report.pdf")).expect("read file before");
    let before_note =
        fs::read_to_string(repo.path().join("docs/report.pdf.md")).expect("read note before");

    let entry = get_file(path_string(repo.path()), file_id).expect("load mobile detail metadata");
    let changes = list_changes(path_string(repo.path()), mobile_log_filter(file_id))
        .expect("load mobile detail log");
    let note = read_note(path_string(repo.path()), file_id).expect("load mobile detail note");

    assert_eq!(entry.current_name, "report.pdf");
    assert_eq!(entry.size_bytes, 407);
    assert_eq!(entry.availability_status, FileAvailabilityStatus::Available);
    assert_eq!(changes.len(), 2);
    assert_eq!(changes[0].action, "edited_note");
    assert_eq!(note.as_deref(), Some("Reviewed from C4-07 validation."));
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert_eq!(
        fs::read(repo.path().join("docs/report.pdf")).expect("read file after"),
        before_file
    );
    assert_eq!(
        fs::read_to_string(repo.path().join("docs/report.pdf.md")).expect("read note after"),
        before_note
    );
}

#[test]
fn mobile_detail_validation_covers_missing_and_structured_failures() {
    let repo = initialized_repo();
    let missing_file_id = insert_file_row(repo.path(), "docs/missing.pdf", false);
    let before_counts = metadata_counts(repo.path());

    let missing_entry =
        get_file(path_string(repo.path()), missing_file_id).expect("load missing detail row");
    assert_eq!(
        missing_entry.availability_status,
        FileAvailabilityStatus::Missing
    );
    assert_eq!(
        read_note(path_string(repo.path()), missing_file_id),
        Ok(None)
    );
    assert!(matches!(
        get_file(path_string(repo.path()), 99_999),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        read_note(path_string(repo.path()), 99_999),
        Err(CoreError::FileNotFound { .. })
    ));

    let mut invalid_filter = mobile_log_filter(missing_file_id);
    invalid_filter.file_id = Some(0);
    assert!(matches!(
        list_changes(path_string(repo.path()), invalid_filter),
        Err(CoreError::Db { .. })
    ));
    assert_eq!(metadata_counts(repo.path()), before_counts);
    assert!(!repo.path().join("docs/missing.pdf").exists());
}

#[test]
fn mobile_detail_validation_locks_core_api_udl_rust_and_test_evidence() {
    fn assert_get_file(_: fn(String, i64) -> CoreResult<FileEntry>) {}
    fn assert_list_changes(_: fn(String, ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>>) {}
    fn assert_read_note(_: fn(String, i64) -> CoreResult<Option<String>>) {}

    assert_get_file(get_file);
    assert_list_changes(list_changes);
    assert_read_note(read_note);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-34: C4-07 validation",
        "为 C4-07 mobile-detail 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-34",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-07 mobile-detail",
        "- S4-IOS-05 mobile-file-detail",
        "- `get_file`",
        "- `list_changes`",
        "- `read_note`",
        "- file_id。",
        "- 移动端详情所需 metadata、日志、笔记。",
        "- 只读。",
        "- 无写入。",
        "- `FileNotFound`",
        "- `Db`",
        "详情页不从文件系统反推 metadata。",
        "Missing 状态能进入 S4-X-06。",
        "日志和笔记可按需懒加载。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-IOS-05 | mobile-file-detail | C4-07 | detail/log/note query | 缺失进入 recovery",
        "| S4-X-06 | missing-file-recovery | C4-18 | relink/remove record | remove record 不删文件",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    for fragment in [
        "FileEntry get_file(string repo_path, i64 file_id);",
        "sequence<ChangeLogEntry> list_changes(string repo_path, ChangeFilter filter);",
        "string? read_note(string repo_path, i64 file_id);",
        "dictionary FileEntry",
        "FileAvailabilityStatus availability_status;",
        "dictionary ChangeFilter",
        "i64? file_id;",
        "i64 limit;",
        "i64 offset;",
        "dictionary ChangeLogEntry",
        "string detail_json;",
        "FileNotFound(string path);",
        "Db(string message);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `get_file(repoPath, fileId) throws -> FileEntry`",
        "文件不存在抛 `FileNotFound`。",
        "metadata 行仍返回 `FileAvailabilityStatus.Missing`",
        "### `list_changes(repoPath, filter) throws -> [ChangeLogEntry]`",
        "### `read_note(repoPath, fileId) throws -> String?`",
        "无笔记时返回 `nil`。",
        "| `read_note(repo, file_id)` | note | √ | Io |",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "pub fn get_file(repo_path: String, file_id: i64) -> CoreResult<FileEntry>",
        "pub fn list_changes(repo_path: String, filter: ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>>",
        "pub fn read_note(repo_path: String, file_id: i64) -> CoreResult<Option<String>>",
        "C4-07 composes this API with [`list_changes`] and",
        "[`read_note`] for `S4-IOS-05` mobile-file-detail",
        "without platform-side filesystem inference and route the missing state to",
        "`S4-X-06` rather than inferring it from the filesystem",
        "load the Log segment without blocking the Meta segment",
        "does not trigger filesystem rescan, sync",
        "repair, conflict resolution, or missing-file recovery",
        "C4-07 reuses this as the lazy Note segment query",
        "note editing remains with the existing",
        "`write_note` contract",
    ] {
        assert_contains(API_RS, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "mobile_detail_contract_exports_detail_log_and_note_signatures",
        "mobile_detail_docs_core_api_and_udl_stay_aligned",
        "mobile_detail_contract_documents_consumer_state_without_adjacent_capabilities",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "mobile_detail_implementation_loads_metadata_log_and_note_without_writes",
        "mobile_detail_implementation_preserves_missing_rows_for_recovery_route",
        "mobile_detail_implementation_maps_absent_file_id_to_file_not_found",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "mobile_detail_failure_edge_returns_empty_segments_without_mutation",
        "mobile_detail_failure_edge_rejects_invalid_inputs_without_silent_fallback",
        "mobile_detail_failure_edge_maps_metadata_db_failures",
        "mobile_detail_failure_edge_maps_errors_to_recovery_metadata",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
