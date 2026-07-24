use area_matrix_core::{
    create_classifier_rule, create_default_classifier, delete_classifier_rule,
    list_classifier_rules, restore_default_classifier, restore_last_valid_classifier,
    update_classifier_rule, ClassifierConfigHealth, ClassifierLocaleValue,
    ClassifierRecoveryAction, ClassifierRuleCreateRequest, ClassifierRuleDeleteRequest,
    ClassifierRuleEditorSnapshot, ClassifierRuleObservedState, ClassifierRuleRecord,
    ClassifierRuleUpdate, ContentLocale, CoreError, CoreResult,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
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
        repository_locale_policy: "system".to_owned(),
        editing_locale: ContentLocale::En,
        rule_id: "finance".to_owned(),
        observed: ClassifierRuleObservedState {
            rule_id: "finance".to_owned(),
            slug: "finance".to_owned(),
            display_name: "Finance".to_owned(),
            description: String::new(),
            extensions: Vec::new(),
            keywords: vec![
                "invoice".to_owned(),
                "receipt".to_owned(),
                "tax".to_owned(),
                "contract".to_owned(),
                "发票".to_owned(),
                "收据".to_owned(),
                "税务".to_owned(),
                "合同".to_owned(),
                "报销".to_owned(),
            ],
            priority: 10,
            naming_template: None,
        },
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

fn create_request() -> ClassifierRuleCreateRequest {
    ClassifierRuleCreateRequest {
        repository_locale_policy: "system".to_owned(),
        editing_locale: ContentLocale::En,
        slug: "tax".to_owned(),
        display_name: "Tax".to_owned(),
        description: "Tax documents".to_owned(),
        extensions: vec!["pdf".to_owned()],
        keywords: vec!["tax".to_owned()],
        priority: 20,
        naming_template: Some("{stem}".to_owned()),
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
    fn assert_recovery(
        _: fn(String, bool, Option<ContentLocale>) -> CoreResult<ClassifierRuleEditorSnapshot>,
    ) {
    }
    assert_list(list_classifier_rules);
    assert_create(create_classifier_rule);
    assert_update(update_classifier_rule);
    assert_delete(delete_classifier_rule);
    assert_recovery(create_default_classifier);
    assert_recovery(restore_default_classifier);
    assert_recovery(restore_last_valid_classifier);

    let rule = ClassifierRuleRecord {
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
    let snapshot = ClassifierRuleEditorSnapshot {
        rules: vec![rule],
        default_rule_id: "inbox".to_owned(),
        updated_rule_id: Some("finance".to_owned()),
        repository_locale_policy: "system".to_owned(),
        editing_locale: Some(ContentLocale::En),
        health: ClassifierConfigHealth::Valid,
        recovery_actions: vec![ClassifierRecoveryAction::RestoreDefault],
        warning: Some("impact preview required before deleting this rule".to_owned()),
    };

    assert_eq!(snapshot.rules[0].rule_id, "finance");
    assert_eq!(snapshot.rules[0].extensions, vec!["pdf"]);
    assert_eq!(snapshot.rules[0].keywords, vec!["invoice"]);
    assert_eq!(snapshot.default_rule_id, "inbox");
    assert_eq!(snapshot.updated_rule_id.as_deref(), Some("finance"));

    let create = create_request();
    assert_eq!(create.slug, "tax");
    assert_eq!(create.priority, 20);

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
    let uninitialized = tempfile::tempdir().expect("create uninitialized repository fixture");
    let uninitialized_path = uninitialized.path().to_string_lossy().into_owned();
    assert!(matches!(
        list_classifier_rules(String::new(), Some(ContentLocale::En)),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_id = update_request();
    invalid_id.rule_id.clear();
    assert!(matches!(
        update_classifier_rule(uninitialized_path.clone(), invalid_id),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_slug = update_request();
    invalid_slug.slug = "Bad Category".to_owned();
    assert!(matches!(
        update_classifier_rule(uninitialized_path.clone(), invalid_slug),
        Err(CoreError::Config { .. })
    ));

    let mut dotted_extension = update_request();
    dotted_extension.extensions = vec![".pdf".to_owned()];
    assert!(matches!(
        update_classifier_rule(uninitialized_path.clone(), dotted_extension),
        Err(CoreError::Config { .. })
    ));

    let mut duplicate_keyword = update_request();
    duplicate_keyword.keywords = vec!["invoice".to_owned(), "invoice".to_owned()];
    assert!(matches!(
        update_classifier_rule(uninitialized_path.clone(), duplicate_keyword),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_priority = update_request();
    invalid_priority.priority = 1001;
    assert!(matches!(
        update_classifier_rule(uninitialized_path.clone(), invalid_priority),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_create = create_request();
    invalid_create.slug = "Bad Category".to_owned();
    assert!(matches!(
        create_classifier_rule(uninitialized_path.clone(), invalid_create),
        Err(CoreError::Config { .. })
    ));

    assert!(create_classifier_rule(uninitialized_path.clone(), create_request()).is_err());
    assert!(update_classifier_rule(uninitialized_path.clone(), update_request()).is_err());
    assert!(delete_classifier_rule(uninitialized_path, delete_request()).is_err());
    assert_eq!(
        std::fs::read_dir(uninitialized.path())
            .expect("read uninitialized fixture")
            .count(),
        0
    );
}

#[test]
fn classifier_rule_editor_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "string repo_path, ContentLocale? editing_locale",
        "ClassifierRuleEditorSnapshot create_classifier_rule(",
        "ClassifierRuleEditorSnapshot create_default_classifier(",
        "ClassifierRuleEditorSnapshot restore_default_classifier(",
        "ClassifierRuleEditorSnapshot restore_last_valid_classifier(",
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
        "string repository_locale_policy;",
        "ContentLocale? editing_locale;",
        "enum ClassifierConfigHealth",
        "enum ClassifierRecoveryAction",
        "ClassifierConfigHealth health;",
        "sequence<ClassifierRecoveryAction> recovery_actions;",
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
        "| `list_classifier_rules(repo, editing_locale)` | classify | √ | Config / PermissionDenied / Io |",
        "| `create_default_classifier(repo, confirmed, editing_locale)` | classify | √ | Config / PermissionDenied / Io |",
        "| `restore_default_classifier(repo, confirmed, editing_locale)` | classify | √ | Config / PermissionDenied / Io |",
        "| `restore_last_valid_classifier(repo, confirmed, editing_locale)` | classify | √ | Config / PermissionDenied / Io |",
        "| `create_classifier_rule(repo, request)` | classify | √ | Config / Conflict / PermissionDenied / Io |",
        "| `update_classifier_rule(repo, request)` | classify | √ | Config / Conflict / PermissionDenied / Io |",
        "| `delete_classifier_rule(repo, request)` | classify | √ | Config / PermissionDenied / Io |",
        "### `list_classifier_rules(repoPath, editingLocale) throws -> ClassifierRuleEditorSnapshot`",
        "### `create_classifier_rule(repoPath, request) throws -> ClassifierRuleEditorSnapshot`",
        "### `update_classifier_rule(repoPath, request) throws -> ClassifierRuleEditorSnapshot`",
        "### `delete_classifier_rule(repoPath, request) throws -> ClassifierRuleEditorSnapshot`",
        "classifier rule editor 的分类规则编辑器入口",
        "`classifier rule editor surface classifier-rule-editor`",
        "删除规则不自动移动、删除、重命名或重分类历史文件",
        "不实现 classifier rule save、classifier impact preview、复杂脚本规则、插件规则或 AI 规则",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn classifier_rule_editor_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "classifier rule editor contract types and entry points",
        "ClassifierRuleRecord",
        "ClassifierRuleEditorSnapshot",
        "ClassifierRuleCreateRequest",
        "ClassifierRuleUpdate",
        "ClassifierRuleDeleteRequest",
        "list_classifier_rules",
        "create_classifier_rule",
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
        "Lists classifier rule editor state for classifier rule editor surface",
        "Creates one classifier rule editor row",
        "Updates one classifier rule editor row",
        "Deletes one classifier rule editor row",
        "must not move, delete, rename",
        "call AI/network providers",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Io"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}
