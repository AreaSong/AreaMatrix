use area_matrix_core::{
    move_to_category, preview_move_to_category, CoreError, CoreResult, FileEntry, FileOrigin,
    MoveToCategoryPreview, StorageMode,
};

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
    fn assert_preview(_: fn(String, i64, String) -> CoreResult<MoveToCategoryPreview>) {}

    assert_move(move_to_category);
    assert_preview(preview_move_to_category);

    for fragment in [
        "MoveToCategoryPreview preview_move_to_category(",
        "FileEntry move_to_category(string repo_path, i64 file_id, string new_category);",
        "dictionary MoveToCategoryPreview",
        "string target_path;",
        "boolean name_conflict_resolved;",
        "boolean will_move_file;",
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
        "| `preview_move_to_category(repo, file_id, cat)` | storage | √ | Classify / Conflict / FileNotFound / PermissionDenied / Io / Db |",
        "| `move_to_category(repo, file_id, cat)` | storage | √ | Classify / Conflict / FileNotFound / PermissionDenied / Io / Db |",
        "`preview_move_to_category` 是 C1-24 的确认前目标路径解析入口",
        "不得创建分类目录、移动文件、重命名文件、删除文件、更新",
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
        "Previews the final destination for a C1-24 category move",
        "must not create category directories",
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
        availability_status: area_matrix_core::FileAvailabilityStatus::Available,
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
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
    assert_contains(API_RS, "preserve");
    assert_contains(API_RS, "tags, notes");
}
