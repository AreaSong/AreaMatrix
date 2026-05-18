use area_matrix_core::{
    delete_classifier_rule, list_classifier_rules, predict_category, update_classifier_rule,
    ClassifierRuleDeleteRequest, ClassifierRuleEditorSnapshot, ClassifierRuleRecord,
    ClassifierRuleUpdate, ClassifyReason, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

#[path = "support/classifier_rule_editor_validation.rs"]
mod classifier_rule_editor_validation_support;

use classifier_rule_editor_validation_support::{
    assert_contains, assert_no_classifier_temp_files, category, delete_request, initialized_repo,
    insert_active_file, path_string, read_classifier, snapshot, update_request,
};

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-15-classifier-rule-editor.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const PAGE_SPEC: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-19-classifier-rule-editor.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const CLASSIFIER_RULE_EDITOR_RS: &str = include_str!("../src/classifier_rule_editor.rs");
const CLASSIFIER_RULE_EDITOR_CONFIG_RS: &str =
    include_str!("../src/classifier_rule_editor/config.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");

#[test]
fn classifier_rule_editor_validation_locks_api_udl_and_rust_contract() {
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

    let record = ClassifierRuleRecord {
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
    assert_eq!(record.rule_id, record.slug);
    assert_eq!(record.priority, 10);

    for fragment in [
        "# C2-15 classifier-rule-editor",
        "- S2-19 classifier-rule-editor",
        "计划新增：`list_classifier_rules`、`update_classifier_rule`、`delete_classifier_rule`",
        "规则 ID 和规则内容。",
        "规则列表或更新结果。",
        "更新分类规则配置。",
        "原子更新 `.areamatrix/classifier.yaml` 或等价配置。",
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
        "管理分类列表。",
        "管理每个分类承载的扩展名、关键词、优先级和命名模板。",
        "校验并保存到 classifier.yaml。",
        "删除分类或匹配值不会自动移动、删除或重命名任何历史文件",
        "Stage 2 不提供 `path` rule、`source_folder` rule 或独立 rule `enabled` 字段。",
    ] {
        assert_contains(PAGE_SPEC, fragment);
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
        "C2-15 的分类规则编辑器入口",
        "`S2-19 classifier-rule-editor`",
        "只允许原子更新 classifier 配置",
        "删除规则不自动移动、删除、重命名或重分类历史文件",
        "不实现 C2-13 rule save、C2-14 impact preview、复杂脚本规则、插件规则或 Stage 3 AI 规则",
        "Config",
        "PermissionDenied",
        "Io",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "测试金字塔",
        "`core/classify` | ≥ 90%",
        "集成测试目录",
        "`core/tests/`，每个文件独立编译",
        "关键测试场景",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }

    for fragment in [
        "delete_classifier_rule, list_classifier_rules, update_classifier_rule",
        "ClassifierRuleDeleteRequest, ClassifierRuleEditorSnapshot, ClassifierRuleRecord",
        "ClassifierRuleUpdate",
    ] {
        assert_contains(LIB_RS, fragment);
    }

    for fragment in [
        "Lists C2-15 classifier rule editor state for S2-19.",
        "Updates one C2-15 classifier editor row for future classification.",
        "Deletes one C2-15 classifier editor row after explicit impact confirmation.",
        "classifier_rule_editor::list_classifier_rules(repo_path)",
        "classifier_rule_editor::update_classifier_rule(repo_path, request)",
        "classifier_rule_editor::delete_classifier_rule(repo_path, request)",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C2-15 classifier rule editor contract types and entry points",
        "pub struct ClassifierRuleRecord",
        "pub struct ClassifierRuleEditorSnapshot",
        "pub struct ClassifierRuleUpdate",
        "pub struct ClassifierRuleDeleteRequest",
        "pub fn list_classifier_rules(",
        "pub fn update_classifier_rule(",
        "pub fn delete_classifier_rule(",
        "must not move, delete, rename",
        "CoreError::Config",
        "CoreError::PermissionDenied",
        "CoreError::Io",
    ] {
        assert_contains(CLASSIFIER_RULE_EDITOR_RS, fragment);
    }

    for fragment in [
        "read_classifier_config",
        "snapshot_from_config",
        "apply_update",
        "apply_delete",
        "reject_unpreviewed_impactful_update",
        "write_classifier_config_atomically",
        "restore_classifier_config",
    ] {
        assert_contains(CLASSIFIER_RULE_EDITOR_CONFIG_RS, fragment);
    }
}

#[test]
fn classifier_rule_editor_validation_list_and_update_are_snapshot_ready_and_future_only() {
    let repo = initialized_repo();
    let existing_file_id = insert_active_file(repo.path(), "finance/legacy-invoice.pdf", "finance");
    let before = snapshot(repo.path());

    let listed = list_classifier_rules(path_string(repo.path())).expect("list classifier rules");

    assert_eq!(listed.default_rule_id, "inbox");
    assert_eq!(listed.updated_rule_id, None);
    assert_eq!(listed.warning, None);
    assert!(listed.rules.iter().any(|rule| {
        rule.rule_id == "finance"
            && rule.slug == "finance"
            && rule.display_name == "Finance"
            && rule.keywords.iter().any(|keyword| keyword == "invoice")
            && !rule.is_default
    }));
    assert_eq!(snapshot(repo.path()), before);

    let saved = update_classifier_rule(path_string(repo.path()), update_request())
        .expect("update classifier rule");

    assert_eq!(saved.default_rule_id, "inbox");
    assert_eq!(saved.updated_rule_id.as_deref(), Some("contracts"));
    assert_eq!(saved.warning, None);
    assert!(saved.rules.iter().any(|rule| {
        rule.rule_id == "contracts"
            && rule.slug == "contracts"
            && rule.display_name == "Contracts"
            && rule.description == "Signed client contracts"
            && rule.extensions == vec!["pdf".to_owned(), "docx".to_owned()]
            && rule.keywords == vec!["agreement".to_owned(), "合同".to_owned()]
            && rule.priority == 30
            && rule.naming_template.as_deref() == Some("{stem}-{date}")
            && !rule.is_default
    }));
    assert!(!saved.rules.iter().any(|rule| rule.rule_id == "finance"));

    let config = read_classifier(repo.path());
    assert_eq!(config.default, "inbox");
    let contracts = category(&config, "contracts");
    assert_eq!(
        contracts.display_name.get("en").map(String::as_str),
        Some("Contracts")
    );
    assert_eq!(
        contracts.description.get("en").map(String::as_str),
        Some("Signed client contracts")
    );
    assert_eq!(contracts.extensions, vec!["pdf", "docx"]);
    assert_eq!(contracts.keywords, vec!["agreement", "合同"]);
    assert_eq!(contracts.priority, 30);
    assert_eq!(contracts.naming_template.as_deref(), Some("{stem}-{date}"));

    let future = predict_category(path_string(repo.path()), "agreement.pdf".to_owned())
        .expect("updated rule participates in future classification");
    assert_eq!(future.category, "contracts");
    assert_eq!(future.reason, ClassifyReason::Keyword);

    let after = snapshot(repo.path());
    assert_ne!(after.classifier_yaml, before.classifier_yaml);
    assert_eq!(
        after.file_rows,
        vec![(
            existing_file_id,
            "finance/legacy-invoice.pdf".to_owned(),
            "finance".to_owned(),
            "active".to_owned()
        )]
    );
    assert_eq!(after.file_rows, before.file_rows);
    assert_eq!(after.user_visible_files, before.user_visible_files);
    assert_eq!(after.generated_paths, before.generated_paths);
    assert_eq!(after.change_log_count, before.change_log_count);
    assert_eq!(after.notes_count, before.notes_count);
    assert_eq!(after.tags_count, before.tags_count);
    assert_eq!(after.undo_count, before.undo_count);
    assert_eq!(after.saved_search_count, before.saved_search_count);
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_editor_validation_delete_removes_only_classifier_state_after_preview() {
    let repo = initialized_repo();
    let existing_file_id = insert_active_file(repo.path(), "finance/legacy-invoice.pdf", "finance");
    let before = snapshot(repo.path());

    let saved = delete_classifier_rule(path_string(repo.path()), delete_request("finance"))
        .expect("delete classifier rule");

    assert_eq!(saved.default_rule_id, "inbox");
    assert_eq!(saved.updated_rule_id.as_deref(), Some("inbox"));
    assert_eq!(saved.warning, None);
    assert!(!saved.rules.iter().any(|rule| rule.rule_id == "finance"));
    assert!(saved.rules.iter().any(|rule| rule.rule_id == "inbox"));

    let config = read_classifier(repo.path());
    assert!(config
        .categories
        .iter()
        .all(|category| category.slug != "finance"));
    assert_eq!(config.default, "inbox");

    let future = predict_category(path_string(repo.path()), "invoice.pdf".to_owned())
        .expect("deleted rule no longer participates in future classification");
    assert_eq!(future.category, "docs");
    assert_eq!(future.reason, ClassifyReason::Extension);

    let after = snapshot(repo.path());
    assert_ne!(after.classifier_yaml, before.classifier_yaml);
    assert_eq!(
        after.file_rows,
        vec![(
            existing_file_id,
            "finance/legacy-invoice.pdf".to_owned(),
            "finance".to_owned(),
            "active".to_owned()
        )]
    );
    assert_eq!(after.file_rows, before.file_rows);
    assert_eq!(after.user_visible_files, before.user_visible_files);
    assert_eq!(after.generated_paths, before.generated_paths);
    assert_eq!(after.change_log_count, before.change_log_count);
    assert_eq!(after.notes_count, before.notes_count);
    assert_eq!(after.tags_count, before.tags_count);
    assert_eq!(after.undo_count, before.undo_count);
    assert_eq!(after.saved_search_count, before.saved_search_count);
    assert_no_classifier_temp_files(repo.path());
}

#[test]
fn classifier_rule_editor_validation_failures_keep_old_config_and_side_effects_clean() {
    let repo = initialized_repo();
    insert_active_file(repo.path(), "finance/legacy-invoice.pdf", "finance");
    let before = snapshot(repo.path());

    let mut duplicate_slug = update_request();
    duplicate_slug.slug = "docs".to_owned();
    assert!(matches!(
        update_classifier_rule(path_string(repo.path()), duplicate_slug),
        Err(CoreError::Config { .. })
    ));
    assert_eq!(snapshot(repo.path()), before);

    let mut invalid_template = update_request();
    invalid_template.naming_template = Some("{unsupported}".to_owned());
    assert!(matches!(
        update_classifier_rule(path_string(repo.path()), invalid_template),
        Err(CoreError::Config { .. })
    ));
    assert_eq!(snapshot(repo.path()), before);

    let mut unpreviewed_rename = update_request();
    unpreviewed_rename.preview_confirmed = false;
    assert!(matches!(
        update_classifier_rule(path_string(repo.path()), unpreviewed_rename),
        Err(CoreError::Config { .. })
    ));
    assert_eq!(snapshot(repo.path()), before);

    let mut missing_replacement = delete_request("finance");
    missing_replacement.replacement_category = None;
    assert!(matches!(
        delete_classifier_rule(path_string(repo.path()), missing_replacement),
        Err(CoreError::Config { .. })
    ));
    assert_eq!(snapshot(repo.path()), before);

    let mut unpreviewed_delete = delete_request("finance");
    unpreviewed_delete.preview_confirmed = false;
    assert!(matches!(
        delete_classifier_rule(path_string(repo.path()), unpreviewed_delete),
        Err(CoreError::Config { .. })
    ));
    assert_eq!(snapshot(repo.path()), before);

    assert!(matches!(
        delete_classifier_rule(path_string(repo.path()), delete_request("inbox")),
        Err(CoreError::Config { .. })
    ));
    assert_eq!(snapshot(repo.path()), before);
    assert_no_classifier_temp_files(repo.path());
}
