use area_matrix_core::{save_classifier_rule, ClassifierRule, CoreError, CoreResult};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const CLASSIFIER_YAML: &str = include_str!("../../docs/api/classifier-yaml.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const CLASSIFIER_RULES_RS: &str = include_str!("../src/classifier_rules.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn valid_rule() -> ClassifierRule {
    ClassifierRule {
        target_category: "finance".to_owned(),
        keywords: vec!["合同".to_owned(), "invoice".to_owned()],
        extensions: vec!["pdf".to_owned()],
        priority: 0,
        preview_confirmed: false,
    }
}

#[test]
fn classifier_rule_save_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_save(_: fn(String, ClassifierRule) -> CoreResult<ClassifierRule>) {}
    assert_save(save_classifier_rule);

    let rule = valid_rule();
    assert_eq!(rule.target_category, "finance");
    assert_eq!(rule.keywords, vec!["合同".to_owned(), "invoice".to_owned()]);
    assert_eq!(rule.extensions, vec!["pdf".to_owned()]);
    assert_eq!(rule.priority, 0);
    assert!(!rule.preview_confirmed);

    let documented_errors = [
        CoreError::config("invalid classifier rule"),
        CoreError::permission_denied("classifier config is not writable"),
        CoreError::io("classifier config write failed"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn classifier_rule_save_contract_validates_inputs_without_metadata_writes() {
    assert!(matches!(
        save_classifier_rule(String::new(), valid_rule()),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_category = valid_rule();
    invalid_category.target_category = "Bad Category".to_owned();
    assert!(matches!(
        save_classifier_rule("/tmp/repo".to_owned(), invalid_category),
        Err(CoreError::Config { .. })
    ));

    let mut empty_basis = valid_rule();
    empty_basis.keywords.clear();
    empty_basis.extensions.clear();
    assert!(matches!(
        save_classifier_rule("/tmp/repo".to_owned(), empty_basis),
        Err(CoreError::Config { .. })
    ));

    let mut dotted_extension = valid_rule();
    dotted_extension.extensions = vec![".pdf".to_owned()];
    assert!(matches!(
        save_classifier_rule("/tmp/repo".to_owned(), dotted_extension),
        Err(CoreError::Config { .. })
    ));

    let mut duplicate_keyword = valid_rule();
    duplicate_keyword.keywords = vec!["invoice".to_owned(), "invoice".to_owned()];
    assert!(matches!(
        save_classifier_rule("/tmp/repo".to_owned(), duplicate_keyword),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_priority = valid_rule();
    invalid_priority.priority = 1001;
    assert!(matches!(
        save_classifier_rule("/tmp/repo".to_owned(), invalid_priority),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        save_classifier_rule("/tmp/repo".to_owned(), valid_rule()),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn classifier_rule_save_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "ClassifierRule save_classifier_rule(string repo_path, ClassifierRule rule);",
        "dictionary ClassifierRule",
        "string target_category;",
        "sequence<string> keywords;",
        "sequence<string> extensions;",
        "i64 priority;",
        "boolean preview_confirmed;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `save_classifier_rule(repo, rule)` | classify | √ | Config / PermissionDenied / Io |",
        "### `save_classifier_rule(repoPath, rule) throws -> ClassifierRule`",
        "classifier rule save 的分类规则保存入口",
        "`classifier save-rule surface classifier-save-rule`",
        "`target_category`",
        "`keywords`",
        "`extensions`",
        "`priority`",
        "`preview_confirmed`",
        "不是 keyword AND extension 复合规则",
        "只允许原子更新 classifier 配置",
        "保存规则只影响未来分类",
        "`Save rule only` 回流",
        "不实现 classifier impact preview、classifier rule editor CRUD",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn classifier_rule_save_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "`extensions`",
        "`keywords`",
        "`priority`",
        "Extension 匹配",
        "`keywords` 优先级整体高于 `extensions`",
        "校验失败 = **不替换**当前规则",
    ] {
        assert_contains(CLASSIFIER_YAML, fragment);
    }

    for fragment in [
        "classifier rule save types and persistence",
        "ClassifierRule",
        "save_classifier_rule",
        "does not model path, source-folder",
        "enabled flags, compound AND rules",
        "pub preview_confirmed: bool",
        "impact preview is required",
        "Saves one classifier rule request",
        "appends independent keyword and extension basis values",
        "does not",
        "reclassify, move, rename, delete, preview impact",
        "CoreError::Config",
        "CoreError::PermissionDenied",
        "CoreError::Io",
    ] {
        assert_contains(CLASSIFIER_RULES_RS, fragment);
    }

    for fragment in [
        "classifier save-rule surface uses this contract",
        "Extensions must be",
        "lowercase values without a leading dot",
        "preview has already been confirmed",
        "does not create categories",
        "model compound AND rules",
        "apply the rule to historical files",
        "call AI/network providers",
        "CoreError::Config",
        "CoreError::PermissionDenied",
        "CoreError::Io",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in ["Config", "PermissionDenied", "Io"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}
