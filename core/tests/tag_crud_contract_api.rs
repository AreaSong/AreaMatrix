use area_matrix_core::{add_tag, list_tags, remove_tag, CoreError, CoreResult, TagRecord, TagSet};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const TAGS_RS: &str = include_str!("../src/tags.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn tag_crud_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_add(_: fn(String, i64, String) -> CoreResult<TagSet>) {}
    fn assert_remove(_: fn(String, i64, String) -> CoreResult<TagSet>) {}
    fn assert_list(_: fn(String, i64) -> CoreResult<TagSet>) {}

    assert_add(add_tag);
    assert_remove(remove_tag);
    assert_list(list_tags);

    let selected = TagRecord {
        value: "clienta".to_owned(),
        label: "clientA".to_owned(),
        file_count: 12,
        selected: true,
        disabled: false,
        updated_at: 1_000,
    };
    let available = TagRecord {
        value: "finance".to_owned(),
        label: "finance".to_owned(),
        file_count: 24,
        selected: false,
        disabled: false,
        updated_at: 900,
    };
    let tags = TagSet {
        file_id: 42,
        file_tags: vec![selected.clone()],
        available_tags: vec![selected, available],
        recent_tags: vec![TagRecord {
            value: "urgent".to_owned(),
            label: "urgent".to_owned(),
            file_count: 3,
            selected: false,
            disabled: false,
            updated_at: 1_100,
        }],
        updated_at: 1_200,
    };

    assert_eq!(tags.file_id, 42);
    assert_eq!(tags.file_tags[0].label, "clientA");
    assert_eq!(tags.available_tags[1].file_count, 24);
    assert_eq!(tags.recent_tags[0].value, "urgent");
    assert_eq!(tags.updated_at, 1_200);

    let documented_errors = [
        CoreError::file_not_found("missing file"),
        CoreError::db("tag metadata failed"),
        CoreError::invalid_path("bad tag"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn tag_crud_contract_validates_inputs_without_fake_success() {
    assert!(matches!(
        add_tag(String::new(), 1, "clientA".to_owned()),
        Err(CoreError::InvalidPath { .. })
    ));
    assert!(matches!(
        add_tag("/tmp/repo".to_owned(), 0, "clientA".to_owned()),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        add_tag("/tmp/repo".to_owned(), 1, "bad/tag".to_owned()),
        Err(CoreError::InvalidPath { .. })
    ));
    assert!(matches!(
        remove_tag("/tmp/repo".to_owned(), 1, "bad:tag".to_owned()),
        Err(CoreError::InvalidPath { .. })
    ));
    assert!(matches!(
        list_tags("/tmp/repo".to_owned(), 1),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn tag_crud_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "TagSet add_tag(string repo_path, i64 file_id, string tag);",
        "TagSet remove_tag(string repo_path, i64 file_id, string tag);",
        "TagSet list_tags(string repo_path, i64 file_id);",
        "dictionary TagRecord",
        "string value;",
        "string label;",
        "i64 file_count;",
        "boolean selected;",
        "boolean disabled;",
        "dictionary TagSet",
        "sequence<TagRecord> file_tags;",
        "sequence<TagRecord> available_tags;",
        "sequence<TagRecord> recent_tags;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `add_tag(repo, file_id, tag)` | tags | √ | FileNotFound / Db / InvalidPath |",
        "| `remove_tag(repo, file_id, tag)` | tags | √ | FileNotFound / Db / InvalidPath |",
        "| `list_tags(repo, file_id)` | tags | √ | FileNotFound / Db / InvalidPath |",
        "### `add_tag(repoPath, fileId, tag) throws -> TagSet`",
        "### `remove_tag(repoPath, fileId, tag) throws -> TagSet`",
        "### `list_tags(repoPath, fileId) throws -> TagSet`",
        "重复添加同一标签必须幂等返回刷新后的 `TagSet`",
        "移除一个当前文件没有的 tag 必须幂等返回刷新后的 `TagSet`",
        "标签计数和当前 search scope 下的",
        "仍由 C2-02 `list_filter_facets` 返回",
        "批量加标签属于 C2-06",
        "非 AI 标签建议属于",
        "C2-19",
        "AI 自动标签属于 Stage 3",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn tag_crud_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "C2-05 owns this single-file tag mutation contract",
        "must write only tag metadata",
        "must never rename, move, delete",
        "does not delete the tag definition",
        "must not create, update, remove, rename, or suggest tags",
        "db::add_tag_row",
        "db::remove_tag_row",
        "db::list_tag_set",
        "tag_added",
        "tag_removed",
    ] {
        assert_contains(TAGS_RS, fragment);
    }

    for error_name in ["FileNotFound", "Db", "InvalidPath"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}
