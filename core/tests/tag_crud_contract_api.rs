use area_matrix_core::{add_tag, list_tags, remove_tag, CoreError, CoreResult, TagRecord, TagSet};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-05-tag-crud.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TAGS_ADD_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-07-tags-add.md");
const TAGS_FILTER_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-08-tags-filter.md");
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
        "# C2-05 tag-crud",
        "- S2-07 tags-add",
        "- S2-08 tags-filter",
        "`add_tag(repo_path, file_id, tag)`",
        "`remove_tag`",
        "`list_tags`",
        "file_id、tag。",
        "更新后的 tag set。",
        "- `FileNotFound`",
        "- `Db`",
        "- `InvalidPath`",
        "标签不替代分类，不移动文件。",
        "重复标签幂等处理。",
        "标签名称校验、大小写策略和排序稳定。",
        "AI 自动标签建议属于 Stage 3。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-07 | tags-add | C2-05 | add/remove/list tags | tags, change_log",
        "| S2-08 | tags-filter | C2-02, C2-05 | tag filter | tags 只读",
        "| S2-09 | batch-add-tags | C2-06, C2-07 | batch tag mutation",
        "| S2-23 | tag-suggestions | C2-19, C2-05 | non-AI tag suggestion",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

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
        "展示当前文件已有标签。",
        "搜索已有标签。",
        "创建新标签。",
        "防止重复添加。",
        "移除当前文件上的标签关系。",
        "Tag store 加载失败时显示 `Could not load tags` 和 `Retry`",
        "添加/移除成功后刷新 Detail Meta",
        "Suggestions...` 打开 `S2-23 tag-suggestions`",
        "本页没有危险按钮；不会改变分类、路径或删除标签定义。",
    ] {
        assert_contains(TAGS_ADD_PAGE, fragment);
    }

    for fragment in [
        "标签筛选是搜索过滤器的一部分，不能改变文件标签本身。",
        "搜索并选择已有标签。",
        "选择匹配模式：Any 或 All。",
        "显示每个标签的大致文件数量。",
        "本页不能创建、删除或重命名标签。",
        "标签列表失败和 count 失败是不同状态。",
    ] {
        assert_contains(TAGS_FILTER_PAGE, fragment);
    }

    for fragment in [
        "C2-05 tag CRUD contract",
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
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
    }
}
