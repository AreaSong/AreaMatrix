use area_matrix_core::{
    move_to_category, CoreError, CoreResult, FileEntry, FileOrigin, StorageMode,
};

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md");
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

#[test]
fn move_to_category_contract_exports_core_api_and_udl_signature() {
    fn assert_move(_: fn(String, i64, String) -> CoreResult<FileEntry>) {}

    assert_move(move_to_category);

    for fragment in [
        "FileEntry move_to_category(string repo_path, i64 file_id, string new_category);",
        "dictionary FileEntry",
        "string path;",
        "string current_name;",
        "string category;",
        "StorageMode storage_mode;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn move_to_category_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C1-24 move-to-category",
        "- S1-35 change-category-sheet",
        "- S1-09 main-list",
        "- S1-12 detail-meta",
        "`move_to_category(repo_path, file_id, new_category) -> FileEntry`",
        "更新 `files.category`、`files.path`、`updated_at`。",
        "写入 `change_log.moved`。",
        "Indexed 文件只更新分类元数据，不移动源文件。",
        "批量改分类属于 Stage 2 的 C2-09。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-35 | change-category-sheet | C1-24, C1-10 | `move_to_category`",
        "| C1-22..C1-26 | `1-5/task-01` 到 `1-5/task-25`",
        "Core 能力若未在本矩阵出现，默认不得提前进入 Stage 1 实现。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "| `move_to_category(repo, file_id, cat)` | storage | √ | Classify / Conflict / FileNotFound / PermissionDenied / Io / Db |",
        "`move_to_category` 是 C1-24 的单文件改分类入口",
        "`newCategory` 必须存在于",
        "Core\n不得隐式创建新分类",
        "Copy / Move 等 repo-owned 文件移动到目标分类目录",
        "不覆盖已有文件",
        "Indexed 文件只更新 `files.category`",
        "不移动、重命名或覆盖外部源文件",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "C1-24 owns the user-visible change-category contract",
        "not an arbitrary directory",
        "records `change_log.action = moved`",
        "C1-10 conflict-free numbering",
        "Indexed rows are metadata-only",
        "external source file untouched",
    ] {
        assert_contains(API_RS, fragment);
    }
}

#[test]
fn move_to_category_contract_documents_outputs_errors_and_scope_boundaries() {
    let entry = FileEntry {
        id: 24,
        path: "finance/report.pdf".to_owned(),
        original_name: "report.pdf".to_owned(),
        current_name: "report.pdf".to_owned(),
        category: "finance".to_owned(),
        size_bytes: 128,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some("/tmp/source/report.pdf".to_owned()),
        imported_at: 10,
        updated_at: 20,
    };
    assert_eq!(entry.id, 24);
    assert_eq!(entry.path, "finance/report.pdf");
    assert_eq!(entry.category, "finance");
    assert_eq!(entry.current_name, "report.pdf");

    let documented_errors = [
        CoreError::classify("classification error"),
        CoreError::conflict("path conflict"),
        CoreError::file_not_found("missing file"),
        CoreError::permission_denied("permission denied"),
        CoreError::io("io error"),
        CoreError::db("database error"),
    ];
    assert_eq!(documented_errors.len(), 6);

    for error_name in [
        "Classify",
        "Conflict",
        "FileNotFound",
        "PermissionDenied",
        "Io",
        "Db",
    ] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }

    for fragment in [
        "目标同名不会覆盖目标文件。",
        "成功后 Tree/List/Detail 可通过 Core 查询看到新位置。",
        "批量改分类属于 Stage 2 的 C2-09。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
    assert_contains(API_RS, "preserve");
    assert_contains(API_RS, "tags, notes");
}
