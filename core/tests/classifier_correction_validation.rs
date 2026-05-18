use std::{fs, path::Path};

use area_matrix_core::{
    correct_file_category, import_file, init_repo, ClassifierCorrectionResult, CoreError,
    CoreResult, DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-12-classifier-correction.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const CLASSIFIER_CORRECTION_RS: &str = include_str!("../src/classifier_correction.rs");
const UDL: &str = include_str!("../area_matrix.udl");

#[derive(Debug, Eq, PartialEq)]
struct CorrectionSnapshot {
    file_row: (String, String, String),
    moved_change_count: i64,
    classifier_yaml: String,
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");
    repo
}

fn import_options(category: &str, filename: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some(category.to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn import_fixture(repo: &Path, filename: &str, content: &[u8]) -> area_matrix_core::FileEntry {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source = source_root.path().join(filename);
    fs::write(&source, content).expect("write source fixture");
    import_file(
        path_string(repo),
        path_string(&source),
        import_options("docs", filename),
    )
    .expect("import copied fixture")
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read file row")
}

fn moved_change_count(repo: &Path, file_id: i64) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log WHERE file_id = ?1 AND action = 'moved'",
            [file_id],
            |row| row.get(0),
        )
        .expect("count moved change rows")
}

fn classifier_yaml(repo: &Path) -> String {
    fs::read_to_string(repo.join(".areamatrix/classifier.yaml")).expect("read classifier config")
}

fn snapshot(repo: &Path, file_id: i64) -> CorrectionSnapshot {
    CorrectionSnapshot {
        file_row: file_row(repo, file_id),
        moved_change_count: moved_change_count(repo, file_id),
        classifier_yaml: classifier_yaml(repo),
    }
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn classifier_correction_validation_locks_api_udl_and_rust_contract() {
    fn assert_signature(
        _: fn(String, i64, String, bool, bool) -> CoreResult<ClassifierCorrectionResult>,
    ) {
    }
    assert_signature(correct_file_category);

    for fragment in [
        "correct_file_category(repo_path, file_id, category, move_file, remember) -> ClassifierCorrectionResult",
        "更新后的 FileEntry、可选规则草稿、移动/记住规则请求状态、是否仍需规则确认。",
        "纠错本身不等于保存全局规则。",
        "记住规则必须进入规则保存/预览流程。",
        "不覆盖目标目录同名文件。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    assert_contains(
        CONTROL_MAP,
        "| S2-16 | classifier-correct | C2-12 | correct category | files, change_log, safe move",
    );

    for fragment in [
        "ClassifierCorrectionResult correct_file_category(",
        "string repo_path,",
        "i64 file_id,",
        "string category,",
        "boolean move_file,",
        "boolean remember",
        "dictionary ClassifierRuleDraft",
        "dictionary ClassifierCorrectionResult",
        "FileEntry updated_file;",
        "ClassifierRuleDraft? rule_draft;",
        "boolean rule_confirmation_required;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "Applies one C2-12 classifier correction for S2-16.",
        "must not save",
        "C2-13/C2-14/C2-15",
        "CoreError::Classify",
        "CoreError::Conflict",
        "CoreError::Io",
        "CoreError::Db",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C2-12 classifier correction contract types and entry point",
        "ClassifierRuleDraft",
        "ClassifierCorrectionResult",
        "must not save classifier rules",
        "preview broad rule impact",
        "call AI or network providers",
    ] {
        assert_contains(CLASSIFIER_CORRECTION_RS, fragment);
    }
}

#[test]
fn classifier_correction_validation_success_moves_safely_without_saving_rule() {
    let repo = initialized_repo();
    let entry = import_fixture(repo.path(), "same.pdf", b"corrected bytes");
    fs::create_dir(repo.path().join("finance")).expect("create target category directory");
    fs::write(repo.path().join("finance/same.pdf"), b"existing target")
        .expect("write pre-existing target");
    let before_classifier = classifier_yaml(repo.path());

    let result = correct_file_category(
        path_string(repo.path()),
        entry.id,
        "finance".to_owned(),
        true,
        true,
    )
    .expect("apply classifier correction");

    assert_eq!(result.updated_file.category, "finance");
    assert_eq!(result.updated_file.path, "finance/same_1.pdf");
    assert_eq!(result.move_file_requested, true);
    assert_eq!(result.remember_requested, true);
    assert_eq!(result.rule_confirmation_required, true);
    assert_eq!(
        result
            .rule_draft
            .expect("remember returns rule draft")
            .target_category,
        "finance"
    );
    assert_eq!(
        fs::read(repo.path().join("finance/same.pdf")).expect("read pre-existing target"),
        b"existing target"
    );
    assert_eq!(
        fs::read(repo.path().join("finance/same_1.pdf")).expect("read moved fixture"),
        b"corrected bytes"
    );
    assert_eq!(
        file_row(repo.path(), entry.id),
        (
            "finance/same_1.pdf".to_owned(),
            "same_1.pdf".to_owned(),
            "finance".to_owned(),
        )
    );
    assert_eq!(moved_change_count(repo.path(), entry.id), 1);
    assert_eq!(classifier_yaml(repo.path()), before_classifier);
}

#[test]
fn classifier_correction_validation_failure_paths_leave_state_unchanged() {
    let repo = initialized_repo();
    let entry = import_fixture(repo.path(), "manual.pdf", b"manual bytes");
    let before = snapshot(repo.path(), entry.id);

    let invalid_category = correct_file_category(
        path_string(repo.path()),
        entry.id,
        "unknown".to_owned(),
        true,
        true,
    );
    assert!(matches!(invalid_category, Err(CoreError::Classify { .. })));
    assert_eq!(snapshot(repo.path(), entry.id), before);

    fs::remove_file(repo.path().join("docs/manual.pdf")).expect("remove repo-owned file");
    let missing_file = correct_file_category(
        path_string(repo.path()),
        entry.id,
        "finance".to_owned(),
        true,
        false,
    );
    assert!(matches!(missing_file, Err(CoreError::Io { .. })));
    assert_eq!(snapshot(repo.path(), entry.id), before);
    assert!(!repo.path().join("finance/manual.pdf").exists());
}
