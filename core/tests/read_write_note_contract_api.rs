use area_matrix_core::{read_note, write_note, CoreError, CoreResult};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-14-read-write-note.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
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
        "C1-14 read-write-note",
        "- S1-14 detail-note",
        "- `read_note(repo_path, file_id) -> string?`",
        "- `write_note(repo_path, file_id, content_md)`",
        "- `file_id`",
        "- Markdown 文本。",
        "- 当前笔记内容或 `nil`。",
        "- 写入成功无返回值。",
        "- `notes` upsert。",
        "- `change_log.action = edited_note`。",
        "- 写入同目录伴生 `.md` 文件。",
        "- 写入应由 app 层 InFlightTracker 标记",
        "- 写入失败时不得破坏旧笔记内容。",
        "DB `notes`、`change_log` 与伴生 `.md` 文件必须保持一致",
        "- `FileNotFound`",
        "- `PermissionDenied`",
        "- `Io`",
        "- `Db`",
        "- 无笔记返回 `nil`。",
        "- 写入后 DB 和伴生文件一致。",
        "- 笔记写失败不应破坏旧内容。",
        "- 富文本编辑、双向链接、Markdown 预览增强属于 Stage 2+。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-14 | detail-note | C1-14 | `read_note`, `write_note` | `notes`, `change_log` | sidecar `.md` | FileNotFound, Io | `2-3/task-07` | Real Core |",
        "Core 能力若未在本矩阵出现，默认不得提前进入 Stage 1 实现。",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志、笔记、Tree、recovery、错误映射。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

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
        "Stage 1 先用 `get_file` + `list_changes` + `read_note` 组合",
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
        "C1-14 exposes this read-only query",
        "S1-14 detail-note",
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
        "C1-14 writes exactly one note",
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
