use area_matrix_core::{
    preview_classifier_rule_impact, ClassifierImpactPreviewMode, ClassifierImpactPreviewRequest,
    ClassifierRule, CoreError, CoreResult, RuleImpactConflict, RuleImpactConflictKind,
    RuleImpactMatchReason, RuleImpactReport, RuleImpactSample, RuleImpactStatus,
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

fn valid_request() -> ClassifierImpactPreviewRequest {
    ClassifierImpactPreviewRequest {
        mode: ClassifierImpactPreviewMode::RuleDraft,
        rule: valid_rule(),
        move_files: false,
        replacement_category: None,
    }
}

#[test]
fn classifier_impact_preview_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_preview(
        _: fn(String, ClassifierImpactPreviewRequest) -> CoreResult<RuleImpactReport>,
    ) {
    }
    assert_preview(preview_classifier_rule_impact);

    let request = valid_request();
    let report = RuleImpactReport {
        request: request.clone(),
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

    assert_eq!(report.request, request);
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
        preview_classifier_rule_impact(String::new(), valid_request()),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_category = valid_request();
    invalid_category.rule.target_category = "Bad Category".to_owned();
    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), invalid_category),
        Err(CoreError::Config { .. })
    ));

    let mut empty_basis = valid_request();
    empty_basis.rule.keywords.clear();
    empty_basis.rule.extensions.clear();
    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), empty_basis),
        Err(CoreError::Config { .. })
    ));

    let mut dotted_extension = valid_request();
    dotted_extension.rule.extensions = vec![".pdf".to_owned()];
    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), dotted_extension),
        Err(CoreError::Config { .. })
    ));

    let mut duplicate_keyword = valid_request();
    duplicate_keyword.rule.keywords = vec!["invoice".to_owned(), "invoice".to_owned()];
    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), duplicate_keyword),
        Err(CoreError::Config { .. })
    ));

    let mut invalid_priority = valid_request();
    invalid_priority.rule.priority = 1001;
    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), invalid_priority),
        Err(CoreError::Config { .. })
    ));

    assert!(matches!(
        preview_classifier_rule_impact("/tmp/repo".to_owned(), valid_request()),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn classifier_impact_preview_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C2-14 classifier-impact-preview",
        "- S2-18 classifier-impact-preview",
        "计划新增：`preview_classifier_rule_impact(repo_path, request) -> RuleImpactReport`",
        "规则草稿、删除 keyword、删除 extension 或删除 category 的显式预览请求。",
        "受影响文件数量、样例、冲突、needs review、replacement 缺失状态。",
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
        "RuleImpactReport preview_classifier_rule_impact(",
        "ClassifierImpactPreviewRequest request",
        "dictionary ClassifierImpactPreviewRequest",
        "boolean move_files;",
        "dictionary RuleImpactSample",
        "sequence<RuleImpactMatchReason> match_reasons;",
        "RuleImpactStatus status;",
        "dictionary RuleImpactConflict",
        "RuleImpactConflictKind kind;",
        "dictionary RuleImpactReport",
        "ClassifierImpactPreviewRequest request;",
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
        "\"Category\"",
        "enum ClassifierImpactPreviewMode",
        "\"RemoveKeyword\"",
        "\"RemoveExtension\"",
        "\"RemoveCategory\"",
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
        "| `preview_classifier_rule_impact(repo, request)` | classify | √ | Config / Db |",
        "### `preview_classifier_rule_impact(repoPath, request) throws -> RuleImpactReport`",
        "C2-14 的分类规则影响预览入口",
        "`S2-18 classifier-impact-preview`",
        "`affected_file_count`",
        "`will_update_count`",
        "`already_correct_count`",
        "`needs_review_count`",
        "`conflict_count`",
        "`move_files`",
        "`warning_required`",
        "`can_apply`",
        "删除 keyword、extension 或 category",
        "没有 `replacement_category` 时必须返回 `can_apply = false`",
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
        "删除 extension/keyword/category 的预览不会移动、删除或重命名历史文件。",
        "删除 category 并 Apply 到现有文件时必须选择 replacement category。",
    ] {
        assert_contains(CLASSIFIER_IMPACT_PAGE, fragment);
    }

    for fragment in [
        "C2-14 classifier rule impact-preview contract types and boundary",
        "RuleImpactReport",
        "RuleImpactSample",
        "RuleImpactConflict",
        "preview_classifier_rule_impact",
        "ClassifierImpactPreviewRequest",
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
        "ClassifierImpactPreviewRequest",
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
