use area_matrix_core::{
    preview_classifier_rule_impact, ClassifierRule, CoreError, CoreResult, RuleImpactConflict,
    RuleImpactConflictKind, RuleImpactMatchReason, RuleImpactReport, RuleImpactSample,
    RuleImpactStatus,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-14-classifier-impact-preview.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const CLASSIFIER_IMPACT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-18-classifier-impact-preview.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const CLASSIFIER_IMPACT_RS: &str = include_str!("../src/classifier_impact.rs");
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
        keywords: vec!["合同".to_owned()],
        extensions: vec!["pdf".to_owned()],
        priority: 0,
        preview_confirmed: false,
    }
}

#[test]
fn classifier_impact_preview_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_preview(_: fn(String, ClassifierRule) -> CoreResult<RuleImpactReport>) {}
    assert_preview(preview_classifier_rule_impact);

    let rule = valid_rule();
    let report = RuleImpactReport {
        rule: rule.clone(),
        affected_file_count: 24,
        will_update_count: 18,
        already_correct_count: 4,
        needs_review_count: 2,
        conflict_count: 1,
        sample_limit: 50,
        samples: vec![
            RuleImpactSample {
                file_id: 10,
                path: "docs/contract.pdf".to_owned(),
                current_category: "docs".to_owned(),
                new_category: "finance".to_owned(),
                match_reasons: vec![
                    RuleImpactMatchReason::Keyword,
                    RuleImpactMatchReason::Extension,
                ],
                status: RuleImpactStatus::WillUpdate,
                reason: None,
            },
            RuleImpactSample {
                file_id: 11,
                path: "/external/indexed.pdf".to_owned(),
                current_category: "docs".to_owned(),
                new_category: "finance".to_owned(),
                match_reasons: vec![RuleImpactMatchReason::Extension],
                status: RuleImpactStatus::IndexOnly,
                reason: Some("index-only file cannot be moved".to_owned()),
            },
        ],
        conflicts: vec![RuleImpactConflict {
            file_id: 12,
            path: Some("docs/conflict.pdf".to_owned()),
            conflicting_path: Some("finance/conflict.pdf".to_owned()),
            kind: RuleImpactConflictKind::NameConflict,
            reason: "target path already exists".to_owned(),
        }],
        needs_review: true,
        warning_required: true,
        warning: Some("rule affects many existing files".to_owned()),
        can_apply: false,
        apply_blocked_reason: Some("resolve conflicts and needs review rows".to_owned()),
    };

    assert_eq!(report.rule, rule);
    assert_eq!(report.affected_file_count, 24);
    assert_eq!(report.will_update_count, 18);
    assert_eq!(report.already_correct_count, 4);
    assert_eq!(report.needs_review_count, 2);
    assert_eq!(report.conflict_count, 1);
    assert_eq!(report.samples[0].status, RuleImpactStatus::WillUpdate);
    assert_eq!(report.samples[1].status, RuleImpactStatus::IndexOnly);
    assert_eq!(
        report.conflicts[0].kind,
        RuleImpactConflictKind::NameConflict
    );
    assert!(report.needs_review);
    assert!(report.warning_required);
    assert!(!report.can_apply);

    let documented_errors = [
        CoreError::config("invalid classifier rule draft"),
        CoreError::db("classifier impact metadata unavailable"),
    ];
    assert_eq!(documented_errors.len(), 2);
}

#[test]
fn classifier_impact_preview_contract_validates_inputs_without_fake_success() {
    assert!(matches!(
        preview_classifier_rule_impact(String::new(), valid_rule()),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_category = valid_rule();
    invalid_category.target_category = "Bad Category".to_owned();
    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), invalid_category),
        Err(CoreError::Config { .. })
    ));

    let mut empty_basis = valid_rule();
    empty_basis.keywords.clear();
    empty_basis.extensions.clear();
    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), empty_basis),
        Err(CoreError::Config { .. })
    ));

    let mut dotted_extension = valid_rule();
    dotted_extension.extensions = vec![".pdf".to_owned()];
    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), dotted_extension),
        Err(CoreError::Config { .. })
    ));

    let mut duplicate_keyword = valid_rule();
    duplicate_keyword.keywords = vec!["invoice".to_owned(), "invoice".to_owned()];
    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), duplicate_keyword),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_priority = valid_rule();
    invalid_priority.priority = 1001;
    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), invalid_priority),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), valid_rule()),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn classifier_impact_preview_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C2-14 classifier-impact-preview",
        "- S2-18 classifier-impact-preview",
        "计划新增：`preview_classifier_rule_impact(repo_path, rule) -> RuleImpactReport`",
        "分类规则草稿。",
        "受影响文件数量、样例、冲突、needs review。",
        "无写入。",
        "- `Config`",
        "- `Db`",
        "仅预览不改变文件分类。",
        "影响量超过阈值必须提示。",
        "冲突或 needs review 时不能直接批量应用。",
        "后台持续规则评估属于后续优化。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-18 | classifier-impact-preview | C2-14 | rule impact preview | 只读",
        "分类规则保存和影响预览分离；未预览不得大面积应用。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "RuleImpactReport preview_classifier_rule_impact(string repo_path, ClassifierRule rule);",
        "dictionary RuleImpactSample",
        "sequence<RuleImpactMatchReason> match_reasons;",
        "RuleImpactStatus status;",
        "dictionary RuleImpactConflict",
        "RuleImpactConflictKind kind;",
        "dictionary RuleImpactReport",
        "ClassifierRule rule;",
        "i64 affected_file_count;",
        "i64 will_update_count;",
        "i64 already_correct_count;",
        "i64 needs_review_count;",
        "i64 conflict_count;",
        "sequence<RuleImpactSample> samples;",
        "sequence<RuleImpactConflict> conflicts;",
        "boolean needs_review;",
        "boolean warning_required;",
        "boolean can_apply;",
        "enum RuleImpactMatchReason",
        "\"Keyword\"",
        "\"Extension\"",
        "enum RuleImpactStatus",
        "\"WillUpdate\"",
        "\"AlreadyCorrect\"",
        "\"NeedsReview\"",
        "\"Conflict\"",
        "\"Missing\"",
        "\"IndexOnly\"",
        "enum RuleImpactConflictKind",
        "\"NameConflict\"",
        "\"MissingFile\"",
        "\"UnsupportedStorage\"",
        "\"RuleConflict\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `preview_classifier_rule_impact(repo, rule)` | classify | √ | Config / Db |",
        "### `preview_classifier_rule_impact(repoPath, rule) throws -> RuleImpactReport`",
        "C2-14 的分类规则影响预览入口",
        "`S2-18 classifier-impact-preview`",
        "`affected_file_count`",
        "`will_update_count`",
        "`already_correct_count`",
        "`needs_review_count`",
        "`conflict_count`",
        "`warning_required`",
        "`can_apply`",
        "只读读取 classifier 配置和文件 metadata",
        "不得保存规则、重分类、移动、重命名、删除、Trash、导入、reindex",
        "不实现 C2-13 rule save、C2-15 rule CRUD、后续 apply 行为",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn classifier_impact_preview_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "显示规则摘要。",
        "显示受影响文件数量。",
        "展示文件当前分类和新分类。",
        "标记冲突、缺失、Index-only、不可移动项。",
        "显示应用后 Undo 可用性。",
        "影响过大：显示 warning",
        "有冲突或不可处理项时",
        "Save rule only",
        "Move 开启时必须执行路径冲突 dry-run。",
        "dry-run 必须复用当前 `classifier.yaml` matcher 语义",
        "keyword 和 extension 是独立匹配值",
        "影响数量应覆盖真实 matcher 下会改变分类的所有文件",
        "Index-only 文件只允许更新分类记录",
        "只保存规则不会修改现有文件或分类。",
        "dry-run 失败时不允许 Apply",
    ] {
        assert_contains(CLASSIFIER_IMPACT_PAGE, fragment);
    }

    for fragment in [
        "C2-14 classifier rule impact-preview contract types and boundary",
        "RuleImpactReport",
        "RuleImpactSample",
        "RuleImpactConflict",
        "preview_classifier_rule_impact",
        "must not save",
        "apply category changes",
        "move files",
        "call AI/network providers",
        "CoreError::Config",
        "CoreError::Db",
    ] {
        assert_contains(CLASSIFIER_IMPACT_RS, fragment);
    }

    for fragment in [
        "pub fn preview_classifier_rule_impact(",
        "RuleImpactReport",
        "S2-18",
        "must not save the rule",
        "apply it to existing files",
        "write undo/change-log state",
        "C2-15",
        "CoreError::Config",
        "CoreError::Db",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in ["Config", "Db"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}
