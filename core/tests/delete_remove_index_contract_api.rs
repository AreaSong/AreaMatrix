use area_matrix_core::{delete_file, remove_index_entry, CoreError, CoreResult};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-23-delete-remove-index.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
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

fn assert_not_contains(haystack: &str, needle: &str) {
    assert!(
        !haystack.contains(needle),
        "expected text to omit `{needle}`"
    );
}

#[test]
fn delete_remove_index_contract_api_exports_documented_signatures() {
    fn assert_delete(_: fn(String, i64) -> CoreResult<()>) {}
    fn assert_remove_index(_: fn(String, i64) -> CoreResult<()>) {}

    assert_delete(delete_file);
    assert_remove_index(remove_index_entry);

    for fragment in [
        "void delete_file(string repo_path, i64 file_id);",
        "void remove_index_entry(string repo_path, i64 file_id);",
        "FileNotFound(string path);",
        "PermissionDenied(string path);",
        "Io(string message);",
        "Db(string message);",
        "Internal(string message);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    assert_not_contains(
        CORE_API,
        "delete_file(string repo_path, i64 file_id, boolean hard)",
    );
    assert_not_contains(
        UDL,
        "delete_file(string repo_path, i64 file_id, boolean hard)",
    );
}

#[test]
fn delete_remove_index_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C1-23 delete-remove-index",
        "- S1-34 file-delete-confirm",
        "- S1-12 detail-meta",
        "- S1-09 main-list",
        "`delete_file(repo_path, file_id)`",
        "`remove_index_entry(repo_path, file_id)`",
        "Move to Trash",
        "Remove from Index",
        "`files.status = deleted`",
        "`change_log.deleted`",
        "`change_log.removed_from_index`",
        "不提供永久删除。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-34 | file-delete-confirm | C1-23 | `delete_file`, `remove_index_entry`",
        "| C1-22..C1-26 | `1-5/task-01` 到 `1-5/task-25`",
        "Core 能力若未在本矩阵出现，默认不得提前进入 Stage 1 实现。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "| `delete_file(repo, file_id)` | storage | √ | Io / Db / FileNotFound / PermissionDenied / Internal |",
        "| `remove_index_entry(repo, file_id)` | storage | √ | Db / FileNotFound / PermissionDenied / Internal |",
        "`delete_file` 是用户确认后的 repo-owned 删除入口",
        "不提供永久删除参数",
        "`remove_index_entry` 是 index-only 删除入口",
        "`change_log.action = removed_from_index`",
        "不触碰外部源文件",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "C1-23 owns the user-visible delete/remove-index contract",
        "no `hard` or permanent-delete flag",
        "Indexed,",
        "adopted, external, or missing references must use",
        "`change_log.action = removed_from_index`",
        "must not move anything to Trash",
    ] {
        assert_contains(API_RS, fragment);
    }
}

#[test]
fn delete_remove_index_contract_documents_errors_and_side_effect_boundaries() {
    let documented_errors = [
        CoreError::file_not_found("missing file"),
        CoreError::permission_denied("permission denied"),
        CoreError::io("io error"),
        CoreError::db("database error"),
        CoreError::internal("internal error"),
    ];
    assert_eq!(documented_errors.len(), 5);

    for error_name in ["FileNotFound", "PermissionDenied", "Io", "Db", "Internal"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in [
        "Delete 必须能证明走 Trash，不直接物理删除。",
        "Remove from Index 不删除任何用户原文件。",
        "失败时不清空笔记、不误删其他文件。",
        "不提供永久删除。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "不直接物理删除目标文件",
        "不删除、移动、重命名或覆盖任何其他用户文件",
        "不清空 notes / tags 等关联 metadata",
        "不触发 iCloud placeholder 下载",
        "不替代 Finder/FSEvents 外部删除同步",
    ] {
        assert_contains(CORE_API, fragment);
    }
}
