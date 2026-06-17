use area_matrix_core::{
    get_file, list_changes, read_note, ChangeFilter, ChangeLogEntry, CoreError, CoreResult,
    FileAvailabilityStatus, FileEntry, FileOrigin, StorageMode,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-31-c4-07-contract-api.md"
);
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
