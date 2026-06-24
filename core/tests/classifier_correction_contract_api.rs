use area_matrix_core::{
    correct_file_category, ClassifierCorrectionResult, ClassifierRuleDraft, CoreError, CoreResult,
    FileEntry, FileOrigin, StorageMode,
};
use pretty_assertions::assert_eq;

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
        "classifier correction 的分类纠错入口",
        "`classifier correction surface classifier-correct`",
        "`moveFile`",
        "`remember`",
        "`rule_draft`",
        "classifier correction 不保存该草稿。",
        "不得写入 `.areamatrix/classifier.yaml`",
        "不实现 classifier rule save、classifier impact preview、classifier rule editor",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn classifier_correction_contract_documents_consumer_state_and_scope_boundaries() {
    for fragment in [
        "classifier correction contract types and entry point",
        "ClassifierRuleDraft",
        "ClassifierCorrectionResult",
        "correct_file_category",
        "classifier correction must not persist it",
        "classifier rule save and classifier impact preview",
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
        "classifier correction surface",
        "must not save",
        "classifier rule save/classifier impact preview/classifier rule editor",
        "CoreError::Classify",
        "CoreError::Conflict",
        "CoreError::Io",
        "CoreError::Db",
    ] {
        assert_contains(API_RS, fragment);
    }

    for error_name in ["Classify", "Conflict", "Io", "Db"] {
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
        assert_contains(API_RS, error_name);
    }
}
