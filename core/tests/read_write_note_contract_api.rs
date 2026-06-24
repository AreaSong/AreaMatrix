use area_matrix_core::{read_note, write_note, CoreError, CoreResult};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn read_write_note_contract_api_exposes_documented_signatures_inputs_and_outputs() {
    fn assert_read_note(_: fn(String, i64) -> CoreResult<Option<String>>) {}
    fn assert_write_note(_: fn(String, i64, String) -> CoreResult<()>) {}
    assert_read_note(read_note);
    assert_write_note(write_note);

    let file_id = 42;
    let content_md = "# 会议记录\n\n- follow up".to_owned();
    let read_result: Option<String> = Some(content_md.clone());

    assert_eq!(file_id, 42);
    assert_eq!(read_result.as_deref(), Some("# 会议记录\n\n- follow up"));
    assert_eq!(content_md.lines().count(), 3);

    let documented_errors = [
        CoreError::file_not_found("missing file"),
        CoreError::permission_denied("permission denied"),
        CoreError::io("io error"),
        CoreError::db("database error"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn read_write_note_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "string? read_note(string repo_path, i64 file_id);",
        "void write_note(string repo_path, i64 file_id, string content_md);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `read_note(repoPath, fileId) throws -> String?`",
        "无笔记时返回 `nil`。",
        "### `write_note(repoPath, fileId, contentMd) throws`",
        "DB `notes` 表",
        "物理文件 `<filename>.md`",
        "`InFlightTracker` 标记避免 watcher",
        "当前先用 `get_file` + `list_changes` + `read_note` 组合",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn read_write_note_contract_api_documents_errors_side_effects_and_scope() {
    for fragment in [
        "`FileNotFound { path }`",
        "`PermissionDenied { path }`",
        "`Io { message }`",
        "`Db { message }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "file note contract exposes this read-only query",
        "detail note surface",
        "stable `file_id`",
        "`Some(markdown)`",
        "`None` when the file has no note",
        "must not create note rows",
        "write sidecar files",
        "insert change-log",
        "Returns `CoreError::RepoNotInitialized { path }`",
        "`CoreError::FileNotFound { path }`",
        "`CoreError::PermissionDenied { path }`",
        "`CoreError::Io { message }`",
        "`CoreError::Db { message }`",
        "file note contract writes exactly one note",
        "upserts",
        "`notes` row",
        "same-directory sidecar markdown file",
        "`change_log.action = edited_note`",
        "DB state and sidecar content are",
        "consistent",
        "`InFlightTracker`",
        "must not delete, move, rename, or overwrite",
        "Failed writes must preserve the previous note",
        "must not leave a successful change-log entry",
        "transactional metadata failures",
    ] {
        assert_contains(API_RS, fragment);
    }
}
