use area_matrix_core::{
    apply_tag_suggestions, suggest_tags_for_file, ApplyTagSuggestionItem,
    ApplyTagSuggestionsRequest, CoreError, CoreResult, TagRecord, TagSet, TagSuggestion,
    TagSuggestionApplyItemResult, TagSuggestionApplyReport, TagSuggestionApplyStatus,
    TagSuggestionContext, TagSuggestionMatch, TagSuggestionReport, TagSuggestionRequest,
    TagSuggestionSource, TagSuggestionStatus,
};
use pretty_assertions::assert_eq;

const TASK: &str =
    include_str!("../../tasks/prompts/phase-4/4-1-stage2-experience/task-91-c2-19-contract-api.md");
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-19-tag-suggestions.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TAG_SUGGESTIONS_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-23-tag-suggestions.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const TAGS_RS: &str = include_str!("../src/tags.rs");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn request() -> TagSuggestionRequest {
    TagSuggestionRequest {
        file_id: 42,
        context: Some(TagSuggestionContext {
            source_folder: Some("Finance/Invoices".to_owned()),
            source_keywords: vec!["client-a".to_owned()],
        }),
        limit: 8,
    }
}

fn tag_set() -> TagSet {
    TagSet {
        file_id: 42,
        file_tags: vec![TagRecord {
            value: "tax".to_owned(),
            label: "Tax".to_owned(),
            file_count: 3,
            selected: true,
            disabled: false,
            updated_at: 1_000,
        }],
        available_tags: vec![TagRecord {
            value: "finance".to_owned(),
            label: "Finance".to_owned(),
            file_count: 12,
            selected: false,
            disabled: false,
            updated_at: 900,
        }],
        recent_tags: Vec::new(),
        updated_at: 1_000,
    }
}

fn apply_request() -> ApplyTagSuggestionsRequest {
    ApplyTagSuggestionsRequest {
        file_id: 42,
        suggestions: vec![ApplyTagSuggestionItem {
            suggestion_id: "suggestion:finance".to_owned(),
            slug: "finance".to_owned(),
            display_name: "Finance".to_owned(),
        }],
    }
}

#[test]
fn tag_suggestions_contract_exposes_signatures_outputs_and_errors() {
    fn assert_suggest(_: fn(String, TagSuggestionRequest) -> CoreResult<TagSuggestionReport>) {}
    fn assert_apply(
        _: fn(String, ApplyTagSuggestionsRequest) -> CoreResult<TagSuggestionApplyReport>,
    ) {
    }
    assert_suggest(suggest_tags_for_file);
    assert_apply(apply_tag_suggestions);

    let suggestion = TagSuggestion {
        suggestion_id: "suggestion:finance".to_owned(),
        slug: "finance".to_owned(),
        display_name: "Finance".to_owned(),
        reason: "Matched file name: invoice_2026.pdf".to_owned(),
        source: TagSuggestionSource::FileName,
        match_strength: TagSuggestionMatch::Strong,
        already_exists: true,
        needs_create: false,
        status: TagSuggestionStatus::NewTag,
        selected_by_default: true,
        disabled_reason: None,
    };
    let report = TagSuggestionReport {
        file_id: 42,
        suggestions: vec![suggestion],
        tag_set: tag_set(),
        contents_read: false,
        ai_used: false,
        network_used: false,
    };

    assert_eq!(report.file_id, 42);
    assert_eq!(report.suggestions[0].source, TagSuggestionSource::FileName);
    assert_eq!(
        report.suggestions[0].match_strength,
        TagSuggestionMatch::Strong
    );
    assert!(report.suggestions[0].selected_by_default);
    assert!(!report.contents_read);
    assert!(!report.ai_used);
    assert!(!report.network_used);

    let apply_report = TagSuggestionApplyReport {
        file_id: 42,
        requested_count: 2,
        applied_count: 1,
        skipped_count: 1,
        failed_count: 0,
        item_results: vec![TagSuggestionApplyItemResult {
            suggestion_id: "suggestion:finance".to_owned(),
            slug: "finance".to_owned(),
            status: TagSuggestionApplyStatus::Applied,
            error: None,
        }],
        tag_set: tag_set(),
        undo_token: Some("undo:tag-suggestions:42".to_owned()),
        refresh_targets: vec![
            "tags".to_owned(),
            "change_log".to_owned(),
            "undo_actions".to_owned(),
        ],
    };
    assert_eq!(apply_report.applied_count, 1);
    assert_eq!(
        apply_report.item_results[0].status,
        TagSuggestionApplyStatus::Applied
    );
    assert_eq!(
        apply_report.undo_token.as_deref(),
        Some("undo:tag-suggestions:42")
    );

    let documented_errors = [
        CoreError::file_not_found("missing file"),
        CoreError::validation("invalid suggestion"),
        CoreError::conflict("duplicate edited tag"),
        CoreError::db("tag suggestion metadata failed"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn tag_suggestions_contract_validates_inputs_without_fake_success() {
    assert!(matches!(
        suggest_tags_for_file(
            "/tmp/repo".to_owned(),
            TagSuggestionRequest {
                file_id: 0,
                ..request()
            }
        ),
        Err(CoreError::FileNotFound { .. })
    ));
    assert!(matches!(
        suggest_tags_for_file(
            "/tmp/repo".to_owned(),
            TagSuggestionRequest {
                limit: 0,
                ..request()
            }
        ),
        Err(CoreError::Validation { .. })
    ));
    assert!(matches!(
        suggest_tags_for_file(
            "/tmp/repo".to_owned(),
            TagSuggestionRequest {
                context: Some(TagSuggestionContext {
                    source_folder: Some("https://remote.example".to_owned()),
                    source_keywords: Vec::new(),
                }),
                ..request()
            }
        ),
        Err(CoreError::Validation { .. })
    ));
    assert!(matches!(
        suggest_tags_for_file("/tmp/repo".to_owned(), request()),
        Err(CoreError::Db { .. })
    ));

    assert!(matches!(
        apply_tag_suggestions(
            "/tmp/repo".to_owned(),
            ApplyTagSuggestionsRequest {
                suggestions: Vec::new(),
                ..apply_request()
            }
        ),
        Err(CoreError::Validation { .. })
    ));
    assert!(matches!(
        apply_tag_suggestions(
            "/tmp/repo".to_owned(),
            ApplyTagSuggestionsRequest {
                suggestions: vec![ApplyTagSuggestionItem {
                    suggestion_id: "suggestion:bad".to_owned(),
                    slug: "bad/tag".to_owned(),
                    display_name: "Bad".to_owned(),
                }],
                ..apply_request()
            }
        ),
        Err(CoreError::Validation { .. })
    ));
    assert!(matches!(
        apply_tag_suggestions(
            "/tmp/repo".to_owned(),
            ApplyTagSuggestionsRequest {
                suggestions: vec![
                    ApplyTagSuggestionItem {
                        suggestion_id: "a".to_owned(),
                        slug: "Finance".to_owned(),
                        display_name: "Finance".to_owned(),
                    },
                    ApplyTagSuggestionItem {
                        suggestion_id: "b".to_owned(),
                        slug: "finance".to_owned(),
                        display_name: "Finance".to_owned(),
                    },
                ],
                ..apply_request()
            }
        ),
        Err(CoreError::Conflict { .. })
    ));
    assert!(matches!(
        apply_tag_suggestions("/tmp/repo".to_owned(), apply_request()),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn tag_suggestions_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-1/task-91: C2-19 contract-api",
        "为 C2-19 tag-suggestions 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C2-19 tag-suggestions",
        "- S2-23 tag-suggestions",
        "计划新增：`suggest_tags_for_file`、`apply_tag_suggestions`",
        "file_id、可选来源上下文、建议数量上限。",
        "建议标签、来源理由、是否已存在、是否需新建。",
        "不读取文件正文，不调用 AI，不发生网络访问。",
        "采纳建议后能被搜索、筛选、详情页和 undo 读取。",
        "AI 标签建议属于 Stage 3 的 C3-07。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-23 | tag-suggestions | C2-19, C2-05 | non-AI tag suggestion",
        "tags, file_tags after confirm",
        "`4-1/task-140`, `4-1/task-141`, `4-1/task-142`",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "TagSuggestionReport suggest_tags_for_file(",
        "TagSuggestionApplyReport apply_tag_suggestions(",
        "dictionary TagSuggestionRequest",
        "TagSuggestionContext? context;",
        "dictionary TagSuggestion",
        "TagSuggestionSource source;",
        "TagSuggestionMatch match_strength;",
        "boolean already_exists;",
        "boolean needs_create;",
        "TagSuggestionStatus status;",
        "dictionary TagSuggestionReport",
        "boolean contents_read;",
        "boolean ai_used;",
        "boolean network_used;",
        "dictionary ApplyTagSuggestionsRequest",
        "dictionary TagSuggestionApplyReport",
        "sequence<string> refresh_targets;",
        "enum TagSuggestionSource",
        "\"FileName\"",
        "\"Path\"",
        "\"SourceFolder\"",
        "\"ExistingTagPattern\"",
        "enum TagSuggestionMatch { \"Strong\", \"Weak\" };",
        "enum TagSuggestionStatus { \"NewTag\", \"AlreadyAdded\", \"Invalid\", \"Blocked\" };",
        "enum TagSuggestionApplyStatus { \"Applied\", \"AlreadyAdded\", \"Failed\" };",
        "Validation(string reason);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `suggest_tags_for_file(repo, request)` | tags | √ | FileNotFound / Validation / Conflict / Db |",
        "| `apply_tag_suggestions(repo, request)` | tags | √ | FileNotFound / Validation / Conflict / Db |",
        "### `suggest_tags_for_file(repoPath, request) throws -> TagSuggestionReport`",
        "### `apply_tag_suggestions(repoPath, request) throws -> TagSuggestionApplyReport`",
        "`contents_read` / `ai_used` / `network_used`",
        "C3-07",
        "本合同不新增",
        "control map 之外的页面能力",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn tag_suggestions_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "Tag suggestions",
        "Suggestions come from file name and path keywords. File contents are not read.",
        "显示候选标签和建议理由。",
        "支持一键采纳、逐条采纳、编辑后采纳、忽略。",
        "防止重复添加当前文件已有标签。",
        "采纳后写 change_log，并接入 Undo。",
        "明确说明建议来源非 AI、非内容读取。",
        "Strong match",
        "Weak match",
        "New tag",
        "Already added",
        "Invalid",
        "Blocked",
        "Apply selected",
        "Apply edited",
        "Ignore 只忽略当前展示，不删除标签定义，不写 change_log。",
        "成功后有 Undo toast，Undo 只撤销本次新增标签关系。",
    ] {
        assert_contains(TAG_SUGGESTIONS_PAGE, fragment);
    }

    for fragment in [
        "C2-19 owns the Stage 2 tag-suggestion contract for S2-23",
        "must not read file contents",
        "call AI or remote providers",
        "access the network",
        "must never apply unselected",
        "CoreError::Validation",
        "CoreError::Conflict",
        "CoreError::Db",
    ] {
        assert_contains(TAGS_RS, fragment);
    }

    for fragment in [
        "pub fn suggest_tags_for_file(",
        "tags::suggest_tags_for_file",
        "pub fn apply_tag_suggestions(",
        "tags::apply_tag_suggestions",
        "no AI, network, or content read",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in ["FileNotFound", "Validation", "Conflict", "Db"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}
