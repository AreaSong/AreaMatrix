use area_matrix_core::{
    delete_classifier_rule, list_classifier_rules, update_classifier_rule,
    ClassifierRuleDeleteRequest, ClassifierRuleEditorSnapshot, ClassifierRuleRecord,
    ClassifierRuleUpdate, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-15-classifier-rule-editor.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const CLASSIFIER_RULE_EDITOR_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-19-classifier-rule-editor.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const CLASSIFIER_RULE_EDITOR_RS: &str = include_str!("../src/classifier_rule_editor.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn update_request() -> ClassifierRuleUpdate {
    ClassifierRuleUpdate {
        rule_id: "finance".to_owned(),
        slug: "finance".to_owned(),
        display_name: "Finance".to_owned(),
        description: "Finance documents".to_owned(),
        extensions: vec!["pdf".to_owned(), "csv".to_owned()],
        keywords: vec!["invoice".to_owned(), "合同".to_owned()],
        priority: 10,
        naming_template: Some("{stem}-{date}".to_owned()),
        preview_confirmed: true,
    }
}

fn delete_request() -> ClassifierRuleDeleteRequest {
    ClassifierRuleDeleteRequest {
        rule_id: "finance".to_owned(),
        replacement_category: Some("docs".to_owned()),
        preview_confirmed: true,
    }
}

#[test]
fn classifier_rule_editor_contract_exposes_signatures_inputs_outputs_and_errors() {
    fn assert_list(_: fn(String) -> CoreResult<ClassifierRuleEditorSnapshot>) {}
    fn assert_update(
        _: fn(String, ClassifierRuleUpdate) -> CoreResult<ClassifierRuleEditorSnapshot>,
    ) {
    }
    fn assert_delete(
        _: fn(String, ClassifierRuleDeleteRequest) -> CoreResult<ClassifierRuleEditorSnapshot>,
    ) {
    }
    assert_list(list_classifier_rules);
    assert_update(update_classifier_rule);
    assert_delete(delete_classifier_rule);

    let rule = ClassifierRuleRecord {
        rule_id: "finance".to_owned(),
        slug: "finance".to_owned(),
        display_name: "Finance".to_owned(),
        description: "Finance documents".to_owned(),
        extensions: vec!["pdf".to_owned()],
        keywords: vec!["invoice".to_owned()],
        priority: 10,
        naming_template: Some("{stem}".to_owned()),
        is_default: false,
    };
    let snapshot = ClassifierRuleEditorSnapshot {
        rules: vec![rule],
        default_rule_id: "inbox".to_owned(),
        updated_rule_id: Some("finance".to_owned()),
        warning: Some("impact preview required before deleting this rule".to_owned()),
    };

    assert_eq!(snapshot.rules[0].rule_id, "finance");
    assert_eq!(snapshot.rules[0].extensions, vec!["pdf"]);
    assert_eq!(snapshot.rules[0].keywords, vec!["invoice"]);
    assert_eq!(snapshot.default_rule_id, "inbox");
    assert_eq!(snapshot.updated_rule_id.as_deref(), Some("finance"));

    let update = update_request();
    assert_eq!(update.rule_id, "finance");
    assert_eq!(update.slug, "finance");
    assert_eq!(update.priority, 10);
    assert!(update.preview_confirmed);

    let delete = delete_request();
    assert_eq!(delete.replacement_category.as_deref(), Some("docs"));
    assert!(delete.preview_confirmed);

    let documented_errors = [
        CoreError::config("invalid classifier editor request"),
        CoreError::permission_denied("classifier config is not writable"),
        CoreError::io("classifier config write failed"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn classifier_rule_editor_contract_validates_inputs_without_fake_success_or_side_effects() {
    assert!(matches!(
        list_classifier_rules(String::new()),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_id = update_request();
    invalid_id.rule_id.clear();
    assert!(matches!(
        update_classifier_rule("/tmp/repo".to_owned(), invalid_id),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_slug = update_request();
    invalid_slug.slug = "Bad Category".to_owned();
    assert!(matches!(
        update_classifier_rule("/tmp/repo".to_owned(), invalid_slug),
        Err(CoreError::Config { .. })
    ));

    let mut dotted_extension = update_request();
    dotted_extension.extensions = vec![".pdf".to_owned()];
    assert!(matches!(
        update_classifier_rule("/tmp/repo".to_owned(), dotted_extension),
        Err(CoreError::Config { .. })
    ));

    let mut duplicate_keyword = update_request();
    duplicate_keyword.keywords = vec!["invoice".to_owned(), "invoice".to_owned()];
    assert!(matches!(
        update_classifier_rule("/tmp/repo".to_owned(), duplicate_keyword),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_priority = update_request();
    invalid_priority.priority = 1001;
    assert!(matches!(
        update_classifier_rule("/tmp/repo".to_owned(), invalid_priority),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        update_classifier_rule("/tmp/repo".to_owned(), update_request()),
        Err(CoreError::Config { .. })
    ));
    assert!(matches!(
        delete_classifier_rule("/tmp/repo".to_owned(), delete_request()),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn classifier_rule_editor_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C2-15 classifier-rule-editor",
        "- S2-19 classifier-rule-editor",
        "计划新增：`list_classifier_rules`、`update_classifier_rule`、`delete_classifier_rule`",
        "规则 ID 和规则内容。",
        "规则列表或更新结果。",
        "更新分类规则配置。",
        "原子更新 `.areamatrix/classifier.yaml` 或等价配置。",
        "- `Config`",
        "- `PermissionDenied`",
        "- `Io`",
        "编辑规则前后可预览影响。",
        "删除规则不自动移动历史文件。",
        "配置损坏时可恢复到旧版本。",
        "复杂脚本规则和插件规则不在 Stage 2。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-19 | classifier-rule-editor | C2-15 | rule CRUD | classifier config",
        "分类规则保存和影响预览分离；未预览不得大面积应用。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "ClassifierRuleEditorSnapshot list_classifier_rules(string repo_path);",
        "ClassifierRuleEditorSnapshot update_classifier_rule(",
        "ClassifierRuleUpdate request",
        "ClassifierRuleEditorSnapshot delete_classifier_rule(",
        "ClassifierRuleDeleteRequest request",
        "dictionary ClassifierRuleRecord",
        "string rule_id;",
        "string slug;",
        "string display_name;",
        "string description;",
        "sequence<string> extensions;",
        "sequence<string> keywords;",
        "string? naming_template;",
        "boolean is_default;",
        "dictionary ClassifierRuleEditorSnapshot",
        "sequence<ClassifierRuleRecord> rules;",
        "string default_rule_id;",
        "string? updated_rule_id;",
        "dictionary ClassifierRuleUpdate",
        "boolean preview_confirmed;",
        "dictionary ClassifierRuleDeleteRequest",
        "string? replacement_category;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `list_classifier_rules(repo)` | classify | √ | Config / PermissionDenied / Io |",
        "| `update_classifier_rule(repo, request)` | classify | √ | Config / PermissionDenied / Io |",
        "| `delete_classifier_rule(repo, request)` | classify | √ | Config / PermissionDenied / Io |",
        "### `list_classifier_rules(repoPath) throws -> ClassifierRuleEditorSnapshot`",
        "### `update_classifier_rule(repoPath, request) throws -> ClassifierRuleEditorSnapshot`",
        "### `delete_classifier_rule(repoPath, request) throws -> ClassifierRuleEditorSnapshot`",
        "C2-15 的分类规则编辑器入口",
        "`S2-19 classifier-rule-editor`",
        "删除规则不自动移动、删除、重命名或重分类历史文件",
        "不实现 C2-13 rule save、C2-14 impact preview、复杂脚本规则、插件规则或 Stage 3 AI 规则",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn classifier_rule_editor_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "管理分类列表。",
        "管理每个分类承载的扩展名、关键词、优先级和命名模板。",
        "校验并保存到 classifier.yaml。",
        "回退到上次有效版本。",
        "删除分类或删除扩展名/关键词值前展示影响并二次确认。",
        "当前 `classifier.yaml` 没有独立 rule object",
        "Stage 2 不提供 `path` rule、`source_folder` rule 或独立 rule `enabled` 字段。",
        "Delete category 必须二次确认",
        "删除分类或匹配值不会自动移动、删除或重命名任何历史文件",
        "Preview impact 打开 `S2-18 classifier-impact-preview`",
    ] {
        assert_contains(CLASSIFIER_RULE_EDITOR_PAGE, fragment);
    }

    for fragment in [
        "C2-15 classifier rule editor contract types and entry points",
        "ClassifierRuleRecord",
        "ClassifierRuleEditorSnapshot",
        "ClassifierRuleUpdate",
        "ClassifierRuleDeleteRequest",
        "list_classifier_rules",
        "update_classifier_rule",
        "delete_classifier_rule",
        "must not move, delete, rename",
        "CoreError::Config",
        "CoreError::PermissionDenied",
        "CoreError::Io",
    ] {
        assert_contains(CLASSIFIER_RULE_EDITOR_RS, fragment);
    }

    for fragment in [
        "Lists C2-15 classifier rule editor state for S2-19",
        "Updates one C2-15 classifier editor row",
        "Deletes one C2-15 classifier editor row",
        "must not move, delete, rename",
        "call AI/network providers",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Io"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
    }
}
