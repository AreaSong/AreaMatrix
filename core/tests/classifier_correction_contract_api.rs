use area_matrix_core::{
    correct_file_category, ClassifierCorrectionResult, ClassifierRuleDraft, CoreError, CoreResult,
    FileEntry, FileOrigin, StorageMode,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-12-classifier-correction.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const CLASSIFIER_CORRECT_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-2-experience/S2-16-classifier-correct.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const CLASSIFIER_CORRECTION_RS: &str = include_str!("../src/classifier_correction.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn classifier_correction_contract_exposes_signature_inputs_outputs_and_errors() {
    fn assert_correct(
        _: fn(String, i64, String, bool, bool) -> CoreResult<ClassifierCorrectionResult>,
    ) {
    }
    assert_correct(correct_file_category);

    let updated_file = FileEntry {
        id: 56,
        path: "finance/report.pdf".to_owned(),
        original_name: "report.pdf".to_owned(),
        current_name: "report.pdf".to_owned(),
        category: "finance".to_owned(),
        size_bytes: 128,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Copied,
        origin: FileOrigin::Imported,
        source_path: Some("/tmp/report.pdf".to_owned()),
        availability_status: area_matrix_core::FileAvailabilityStatus::Available,
        imported_at: 1_000,
        updated_at: 1_200,
    };
    let rule_draft = ClassifierRuleDraft {
        source_file_id: updated_file.id,
        target_category: "finance".to_owned(),
        keyword_candidates: vec!["contract".to_owned(), "客户a".to_owned()],
        extension_candidates: vec!["pdf".to_owned()],
        priority: 0,
    };
    let result = ClassifierCorrectionResult {
        updated_file,
        rule_draft: Some(rule_draft),
        move_file_requested: true,
        remember_requested: true,
        rule_confirmation_required: true,
    };

    assert_eq!(result.updated_file.category, "finance");
    assert!(result.move_file_requested);
    assert!(result.remember_requested);
    assert!(result.rule_confirmation_required);
    let draft = result
        .rule_draft
        .as_ref()
        .expect("contract result carries rule draft when remember is requested");
    assert_eq!(draft.target_category, "finance");
    assert_eq!(draft.extension_candidates, vec!["pdf"]);

    let documented_errors = [
        CoreError::classify("invalid category"),
        CoreError::conflict("target exists"),
        CoreError::io("move failed"),
        CoreError::db("metadata failed"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn classifier_correction_contract_validates_inputs_without_fake_success() {
    assert!(matches!(
        correct_file_category(String::new(), 1, "finance".to_owned(), true, false),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        correct_file_category("/tmp/repo".to_owned(), 0, "finance".to_owned(), true, false),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        correct_file_category("/tmp/repo".to_owned(), 1, String::new(), true, false),
        Err(CoreError::Classify { .. })
    ));
    assert!(matches!(
        correct_file_category(
            "/tmp/repo".to_owned(),
            1,
            "Bad Category".to_owned(),
            true,
            true
        ),
        Err(CoreError::Classify { .. })
    ));
    assert!(matches!(
        correct_file_category("/tmp/repo".to_owned(), 1, "finance".to_owned(), false, true),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn classifier_correction_contract_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# C2-12 classifier-correction",
        "- S2-16 classifier-correct",
        "计划新增：`correct_file_category(repo_path, file_id, category, move_file, remember) -> ClassifierCorrectionResult`",
        "file_id、目标分类、是否移动 repo-managed 文件、是否记住规则。",
        "更新后的 FileEntry、可选规则草稿、移动/记住规则请求状态、是否仍需规则确认。",
        "更新文件分类。",
        "写 change log。",
        "按单文件改分类规则移动或只改索引。",
        "- `Classify`",
        "- `Conflict`",
        "- `Io`",
        "- `Db`",
        "纠错本身不等于保存全局规则。",
        "记住规则必须进入规则保存/预览流程。",
        "不覆盖目标目录同名文件。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S2-16 | classifier-correct | C2-12 | correct category | files, change_log, safe move",
        "| S2-17 | classifier-save-rule | C2-13 | save rule | classifier config",
        "| S2-18 | classifier-impact-preview | C2-14 | rule impact preview | 只读",
        "| S2-19 | classifier-rule-editor | C2-15 | rule CRUD | classifier config",
        "分类规则保存和影响预览分离；未预览不得大面积应用。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "ClassifierCorrectionResult correct_file_category(",
        "string repo_path,",
        "i64 file_id,",
        "string category,",
        "boolean move_file,",
        "boolean remember",
        "dictionary ClassifierRuleDraft",
        "i64 source_file_id;",
        "sequence<string> keyword_candidates;",
        "sequence<string> extension_candidates;",
        "dictionary ClassifierCorrectionResult",
        "FileEntry updated_file;",
        "ClassifierRuleDraft? rule_draft;",
        "boolean move_file_requested;",
        "boolean remember_requested;",
        "boolean rule_confirmation_required;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `correct_file_category(repo, file_id, category, move_file, remember)` | classify | √ | Classify / Conflict / Io / Db |",
        "### `correct_file_category(repoPath, fileId, category, moveFile, remember) throws -> ClassifierCorrectionResult`",
        "C2-12 的分类纠错入口",
        "`S2-16 classifier-correct`",
        "`moveFile`",
        "`remember`",
        "`rule_draft`",
        "C2-12 不保存该草稿。",
        "不得写入 `.areamatrix/classifier.yaml`",
        "不实现 C2-13 rule save、C2-14 impact preview、C2-15 rule editor",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn classifier_correction_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "显示当前文件和当前分类。",
        "显示自动分类原因或命中的规则。",
        "选择新的目标分类。",
        "选择是否移动文件到目标目录。",
        "选择是否创建纠错规则。",
        "应用后写入 change log。",
        "`Apply correction` 只应用当前文件纠错，不保存规则",
        "规则写入只能由 `S2-17` 的 `Save rule`",
        "Index-only 文件默认不移动源文件，只更新分类记录。",
        "记住规则但未完成规则确认时，`Apply correction` 只应用当前文件纠错，不保存规则。",
        "点击 `Apply correction` 只执行当前文件的分类更新和可选移动，不保存规则；成功后显示 Undo toast。",
    ] {
        assert_contains(CLASSIFIER_CORRECT_PAGE, fragment);
    }

    for fragment in [
        "C2-12 classifier correction contract types and entry point",
        "ClassifierRuleDraft",
        "ClassifierCorrectionResult",
        "correct_file_category",
        "C2-12 must not persist it",
        "C2-13 and C2-14",
        "must not save classifier rules",
        "preview broad rule impact",
        "call AI or network providers",
        "CoreError::Classify",
        "CoreError::Db",
    ] {
        assert_contains(CLASSIFIER_CORRECTION_RS, fragment);
    }

    for fragment in [
        "pub fn correct_file_category(",
        "ClassifierCorrectionResult",
        "S2-16",
        "must not save",
        "C2-13/C2-14/C2-15",
        "CoreError::Classify",
        "CoreError::Conflict",
        "CoreError::Io",
        "CoreError::Db",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in ["Classify", "Conflict", "Io", "Db"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}
