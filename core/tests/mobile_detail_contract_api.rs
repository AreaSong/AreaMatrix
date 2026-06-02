use area_matrix_core::{
    get_file, list_changes, read_note, ChangeFilter, ChangeLogEntry, CoreError, CoreResult,
    FileAvailabilityStatus, FileEntry, FileOrigin, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-31-c4-07-contract-api.md"
);
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-4-multiplatform/C4-07-mobile-detail.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const MOBILE_DETAIL_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-IOS-05-mobile-file-detail.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn mobile_detail_contract_exports_detail_log_and_note_signatures() {
    fn assert_get_file(_: fn(String, i64) -> CoreResult<FileEntry>) {}
    fn assert_list_changes(_: fn(String, ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>>) {}
    fn assert_read_note(_: fn(String, i64) -> CoreResult<Option<String>>) {}

    assert_get_file(get_file);
    assert_list_changes(list_changes);
    assert_read_note(read_note);
}

#[test]
fn mobile_detail_contract_exposes_required_inputs_outputs_and_states() {
    let file_id = 407;
    let metadata = FileEntry {
        id: file_id,
        path: "docs/report.pdf".to_owned(),
        original_name: "report.pdf".to_owned(),
        current_name: "report.pdf".to_owned(),
        category: "docs".to_owned(),
        size_bytes: 12_288,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Indexed,
        origin: FileOrigin::External,
        source_path: Some("/mobile/Documents/report.pdf".to_owned()),
        availability_status: FileAvailabilityStatus::Missing,
        imported_at: 1_777_300_000,
        updated_at: 1_777_300_900,
    };
    assert_eq!(metadata.id, file_id);
    assert_eq!(
        metadata.availability_status,
        FileAvailabilityStatus::Missing
    );

    let log_filter = ChangeFilter {
        file_id: Some(file_id),
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 25,
        offset: 0,
    };
    assert_eq!(log_filter.file_id, Some(file_id));
    assert_eq!(log_filter.limit, 25);

    let change = ChangeLogEntry {
        id: 9,
        file_id: Some(file_id),
        filename: metadata.current_name.clone(),
        category: metadata.category.clone(),
        action: "external_modified".to_owned(),
        detail_json: r#"{"platform":"ios"}"#.to_owned(),
        occurred_at: 1_777_300_950,
    };
    assert_eq!(change.file_id, Some(file_id));
    assert_eq!(change.action, "external_modified");

    let note: Option<String> = Some("Reviewed on mobile.".to_owned());
    assert_eq!(note.as_deref(), Some("Reviewed on mobile."));

    let documented_capability_errors = [
        CoreError::file_not_found("missing file"),
        CoreError::db("database error"),
    ];
    assert_eq!(documented_capability_errors.len(), 2);
}

#[test]
fn mobile_detail_docs_core_api_and_udl_stay_aligned() {
    for fragment in [
        "# 4-3/task-31: C4-07 contract-api",
        "为 C4-07 mobile-detail 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
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
        "移动端编辑笔记可后续扩展。",
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
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `get_file(repoPath, fileId) throws -> FileEntry`",
        "返回的 `FileEntry.availability_status` 与 `list_files` 一致",
        "### `list_changes(repoPath, filter) throws -> [ChangeLogEntry]`",
        "### `read_note(repoPath, fileId) throws -> String?`",
        "Stage 1 先用 `get_file` + `list_changes` + `read_note` 组合",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in ["`FileNotFound { path }`", "`Db { message }`"] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn mobile_detail_contract_documents_consumer_state_without_adjacent_capabilities() {
    for fragment in [
        "Core file metadata API。",
        "Core change log API。",
        "Note 读写 API。",
        "进入详情先加载基础 Meta，再异步加载 Log 和 Note。",
        "缺失文件：显示 `File is missing from the repository`",
        "进入 `S4-X-06 missing-file-recovery`。",
        "Log 或 Note 单独失败时只影响对应分段",
        "移动端批量操作另开规格。",
    ] {
        assert_contains(MOBILE_DETAIL_PAGE, fragment);
    }

    for fragment in [
        "C4-07 composes this API with [`list_changes`] and",
        "[`read_note`] for `S4-IOS-05` mobile-file-detail",
        "does not introduce",
        "a separate detail DTO",
        "route the missing state to",
        "`S4-X-06` rather than inferring it from the filesystem",
        "In C4-07, `S4-IOS-05` uses `file_id`",
        "load the Log segment without blocking the Meta segment",
        "does not trigger filesystem rescan, sync",
        "repair, conflict resolution, or missing-file recovery",
        "C4-07 reuses this as the lazy Note segment query",
        "callers can show the empty-note state from `None`",
        "note editing remains with the existing",
        "`write_note` contract",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C4-07 mobile-detail composes get_file + list_changes + read_note.",
        "FileEntry.availability_status lets S4-IOS-05 route Missing to S4-X-06",
        "without platform-side metadata inference.",
    ] {
        assert_contains(UDL, fragment);
    }
}
