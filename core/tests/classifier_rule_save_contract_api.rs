use area_matrix_core::{save_classifier_rule, ClassifierRule, CoreError, CoreResult};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-13-classifier-rule-save.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const CLASSIFIER_SAVE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-17-classifier-save-rule.md");
const CLASSIFIER_IMPACT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-18-classifier-impact-preview.md");
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
        "# C2-13 classifier-rule-save",
        "- S2-17 classifier-save-rule",
        "计划新增：`save_classifier_rule(repo_path, rule) -> ClassifierRule`",
        "关键词、扩展名、目标分类、优先级。",
        "保存后的规则。",
        "可写入 classifier metadata 或 `.areamatrix/classifier.yaml` 对应结构。",
        "原子更新 classifier 配置。",
        "- `Config`",
        "- `PermissionDenied`",
        "- `Io`",
        "过宽规则必须 warning 或阻止。",
        "重复规则有结构化反馈。",
        "保存前不应用到历史文件。",
        "AI 自动生成规则属于 Stage 3+。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-17 | classifier-save-rule | C2-13 | save rule | classifier config",
        "| S2-18 | classifier-impact-preview | C2-14 | rule impact preview | 只读",
        "| S2-19 | classifier-rule-editor | C2-15 | rule CRUD | classifier config",
        "分类规则保存和影响预览分离；未预览不得大面积应用。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "ClassifierRule save_classifier_rule(string repo_path, ClassifierRule rule);",
        "dictionary ClassifierRule",
        "string target_category;",
        "sequence<string> keywords;",
        "sequence<string> extensions;",
        "i64 priority;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `save_classifier_rule(repo, rule)` | classify | √ | Config / PermissionDenied / Io |",
        "### `save_classifier_rule(repoPath, rule) throws -> ClassifierRule`",
        "C2-13 的分类规则保存入口",
        "`S2-17 classifier-save-rule`",
        "`target_category`",
        "`keywords`",
        "`extensions`",
        "`priority`",
        "不是 keyword AND extension 复合规则",
        "只允许原子更新 classifier 配置",
        "保存规则只影响未来分类",
        "不实现 C2-14 impact preview、C2-15 rule CRUD",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn classifier_rule_save_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "选择规则依据：扩展名、文件名关键词。",
        "保存到分类规则配置。",
        "提供影响预览。",
        "保存到 `classifier.yaml` 时只能写入 `keywords`。",
        "来源目录和路径片段只作为“为什么推荐这个关键词”的解释，不作为 `path` 或 `source_folder` 规则写入。",
        "扩展名 UI 可显示 `.pdf`，写入 `classifier.yaml` 时必须保存为无点小写 `pdf`。",
        "Priority 字段默认 `0`，范围 `-1000..1000`，越大越优先。",
        "多个关键词和扩展名是追加到目标分类的独立匹配值，不是 `keyword AND extension` 复合规则。",
        "保存规则只影响未来分类；是否重分类现有文件由影响预览页决定。",
        "本页不得引入 `path`、`source_folder` 或独立 rule `enabled` 字段",
        "Save rule 不重分类现有文件。",
    ] {
        assert_contains(CLASSIFIER_SAVE_PAGE, fragment);
    }

    for fragment in [
        "从 S2-16 / S2-17 进入时：`Save rule only`",
        "| S2-17 classifier-save-rule | `Save rule only` | 保存规则配置，不重分类现有文件，返回来源上下文。 |",
        "从 S2-16 / S2-17 点击 `Save rule only` 写入规则配置并返回；不更新现有文件分类。",
    ] {
        assert_contains(CLASSIFIER_IMPACT_PAGE, fragment);
    }

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
        "C2-13 classifier rule save types and persistence",
        "ClassifierRule",
        "save_classifier_rule",
        "does not model path, source-folder, enabled flags, compound AND rules",
        "Saves one C2-13 classifier rule request",
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
        "S2-17 uses this contract",
        "must be lowercase values without a leading dot",
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
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
    }
}
