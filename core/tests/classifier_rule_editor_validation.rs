use area_matrix_core::{
    create_classifier_rule, delete_classifier_rule, list_classifier_rules, predict_category,
    update_classifier_rule, ClassifierLocaleValue, ClassifierRuleCreateRequest,
    ClassifierRuleDeleteRequest, ClassifierRuleEditorSnapshot, ClassifierRuleRecord,
    ClassifierRuleUpdate, ClassifyReason, ContentLocale, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

#[path = "support/classifier_rule_editor_validation.rs"]
mod classifier_rule_editor_validation_support;

use classifier_rule_editor_validation_support::{
    assert_contains, assert_no_classifier_temp_files, category, create_request, delete_request,
    initialized_repo, insert_active_file, path_string, read_classifier, snapshot, update_request,
};

const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
const CLASSIFIER_RULE_EDITOR_RS: &str = include_str!("../src/classifier_rule_editor.rs");
const CLASSIFIER_RULE_EDITOR_CONFIG_RS: &str =
    include_str!("../src/classifier_rule_editor/config.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");

fn locale_value<'a>(values: &'a [ClassifierLocaleValue], locale: &str) -> Option<&'a str> {
    values
        .iter()
        .find(|entry| entry.locale == locale)
        .map(|entry| entry.value.as_str())
}

#[test]
fn classifier_rule_editor_validation_locks_api_udl_and_rust_contract() {
    fn assert_list(
        _: fn(String, Option<ContentLocale>) -> CoreResult<ClassifierRuleEditorSnapshot>,
    ) {
    }
    fn assert_create(
        _: fn(String, ClassifierRuleCreateRequest) -> CoreResult<ClassifierRuleEditorSnapshot>,
    ) {
    }
    fn assert_update(
        _: fn(String, ClassifierRuleUpdate) -> CoreResult<ClassifierRuleEditorSnapshot>,
    ) {
    }
    fn assert_delete(
        _: fn(String, ClassifierRuleDeleteRequest) -> CoreResult<ClassifierRuleEditorSnapshot>,
    ) {
    }
    assert_list(list_classifier_rules);
    assert_create(create_classifier_rule);
    assert_update(update_classifier_rule);
    assert_delete(delete_classifier_rule);

    let record = ClassifierRuleRecord {
        rule_id: "finance".to_owned(),
        slug: "finance".to_owned(),
        display_names: vec![ClassifierLocaleValue {
            locale: "en".to_owned(),
            value: "Finance".to_owned(),
        }],
        descriptions: vec![ClassifierLocaleValue {
            locale: "en".to_owned(),
            value: "Finance documents".to_owned(),
        }],
        extensions: vec!["pdf".to_owned()],
        keywords: vec!["invoice".to_owned()],
        priority: 10,
        naming_template: Some("{stem}".to_owned()),
        is_default: false,
    };
    assert_eq!(record.rule_id, record.slug);
    assert_eq!(record.priority, 10);

    for fragment in [
        "string repo_path, ContentLocale? editing_locale",
        "ClassifierRuleEditorSnapshot create_classifier_rule(",
        "ClassifierRuleCreateRequest request",
        "ClassifierRuleEditorSnapshot update_classifier_rule(",
        "ClassifierRuleUpdate request",
        "ClassifierRuleEditorSnapshot delete_classifier_rule(",
        "ClassifierRuleDeleteRequest request",
        "dictionary ClassifierRuleRecord",
        "string rule_id;",
        "string slug;",
        "sequence<ClassifierLocaleValue> display_names;",
        "sequence<ClassifierLocaleValue> descriptions;",
        "sequence<string> extensions;",
        "sequence<string> keywords;",
        "string? naming_template;",
        "boolean is_default;",
        "dictionary ClassifierRuleEditorSnapshot",
        "sequence<ClassifierRuleRecord> rules;",
        "string default_rule_id;",
        "string? updated_rule_id;",
        "dictionary ClassifierRuleCreateRequest",
        "dictionary ClassifierRuleUpdate",
        "boolean preview_confirmed;",
        "dictionary ClassifierRuleDeleteRequest",
        "string? replacement_category;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "classifier rule editor 的分类规则编辑器入口",
        "`classifier rule editor surface classifier-rule-editor`",
        "### `create_classifier_rule(repoPath, request) throws -> ClassifierRuleEditorSnapshot`",
        "| `create_classifier_rule(repo, request)` | classify | √ | Config / Conflict / PermissionDenied / Io |",
        "只允许原子更新 classifier 配置",
        "删除规则不自动移动、删除、重命名或重分类历史文件",
        "不实现 classifier rule save、classifier impact preview、复杂脚本规则、插件规则或 AI 规则",
        "Config",
        "PermissionDenied",
        "Io",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "## 原则",
        "Core line coverage：70%",
        "Core 测试位于：",
        "`core/tests/**` 合同、实现、失败恢复和集成测试。",
        "文件安全测试矩阵",
    ] {
        assert_contains(TESTING_DOC, fragment);
    }

    for fragment in [
        "create_classifier_rule, create_default_classifier, delete_classifier_rule",
        "list_classifier_rules, restore_default_classifier, restore_last_valid_classifier",
        "update_classifier_rule, ClassifierConfigHealth",
        "ClassifierRecoveryAction, ClassifierRuleCreateRequest, ClassifierRuleDeleteRequest",
        "ClassifierRuleEditorSnapshot, ClassifierRuleObservedState, ClassifierRuleRecord",
        "ClassifierRuleUpdate",
    ] {
        assert_contains(LIB_RS, fragment);
    }

    for fragment in [
        "Lists classifier rule editor state for classifier rule editor surface.",
        "Creates one classifier rule editor row for future classification.",
        "Updates one classifier rule editor row for future classification.",
        "Deletes one classifier rule editor row after explicit impact confirmation.",
        "classifier_rule_editor::list_classifier_rules(repo_path, editing_locale)",
        "classifier_rule_editor::create_classifier_rule(repo_path, request)",
        "classifier_rule_editor::update_classifier_rule(repo_path, request)",
        "classifier_rule_editor::delete_classifier_rule(repo_path, request)",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "classifier rule editor contract types and entry points",
        "pub struct ClassifierRuleRecord",
        "pub struct ClassifierRuleEditorSnapshot",
        "pub struct ClassifierRuleCreateRequest",
        "pub struct ClassifierRuleObservedState",
        "pub struct ClassifierRuleUpdate",
        "pub struct ClassifierRuleDeleteRequest",
        "pub fn list_classifier_rules(",
        "pub fn create_classifier_rule(",
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
        "apply_create",
        "validate_observed_update",
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
fn classifier_rule_editor_validation_create_is_snapshot_ready_and_future_only() {
    let repo = initialized_repo();
    let existing_file_id = insert_active_file(repo.path(), "finance/legacy-invoice.pdf", "finance");
    let before = snapshot(repo.path());

    let saved = create_classifier_rule(path_string(repo.path()), create_request())
        .expect("create classifier rule");

    assert_eq!(saved.default_rule_id, "inbox");
    assert_eq!(saved.updated_rule_id.as_deref(), Some("tax"));
    assert_eq!(saved.warning, None);
    assert!(saved.rules.iter().any(|rule| {
        rule.rule_id == "tax"
            && rule.slug == "tax"
            && locale_value(&rule.display_names, "en") == Some("Tax")
            && locale_value(&rule.descriptions, "en") == Some("Tax documents")
            && rule.extensions == vec!["pdf".to_owned()]
            && rule.keywords == vec!["tax".to_owned()]
            && rule.priority == 20
            && rule.naming_template.as_deref() == Some("{stem}")
            && !rule.is_default
    }));

    let config = read_classifier(repo.path());
    assert_eq!(config.default, "inbox");
    let tax = category(&config, "tax");
    assert_eq!(tax.display_name.get("en").map(String::as_str), Some("Tax"));
    assert_eq!(
        tax.description.get("en").map(String::as_str),
        Some("Tax documents")
    );
    assert_eq!(tax.extensions, vec!["pdf"]);
    assert_eq!(tax.keywords, vec!["tax"]);
    assert_eq!(tax.priority, 20);
    assert_eq!(tax.naming_template.as_deref(), Some("{stem}"));

    let future = predict_category(path_string(repo.path()), "tax.pdf".to_owned())
        .expect("created rule participates in future classification");
    assert_eq!(future.category, "tax");
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
fn classifier_rule_editor_validation_list_and_update_are_snapshot_ready_and_future_only() {
    let repo = initialized_repo();
    let existing_file_id = insert_active_file(repo.path(), "finance/legacy-invoice.pdf", "finance");
    let before = snapshot(repo.path());

    let listed = list_classifier_rules(path_string(repo.path()), Some(ContentLocale::En))
        .expect("list classifier rules");

    assert_eq!(listed.default_rule_id, "inbox");
    assert_eq!(listed.updated_rule_id, None);
    assert_eq!(listed.warning, None);
    assert!(listed.rules.iter().any(|rule| {
        rule.rule_id == "finance"
            && rule.slug == "finance"
            && locale_value(&rule.display_names, "en") == Some("Finance")
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
            && locale_value(&rule.display_names, "en") == Some("Contracts")
            && locale_value(&rule.descriptions, "en") == Some("Signed client contracts")
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

    let mut duplicate_create = create_request();
    duplicate_create.slug = "docs".to_owned();
    assert!(matches!(
        create_classifier_rule(path_string(repo.path()), duplicate_create),
        Err(CoreError::Config { .. })
    ));
    assert_eq!(snapshot(repo.path()), before);

    let mut invalid_create_template = create_request();
    invalid_create_template.naming_template = Some("{unsupported}".to_owned());
    assert!(matches!(
        create_classifier_rule(path_string(repo.path()), invalid_create_template),
        Err(CoreError::Config { .. })
    ));
    assert_eq!(snapshot(repo.path()), before);

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
