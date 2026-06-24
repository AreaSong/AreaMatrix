use area_matrix_core::{recover_on_startup, CoreError, CoreResult, RecoveryReport};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn recover_on_startup_contract_api_exposes_documented_signature_output_and_errors() {
    fn assert_recover(_: fn(String) -> CoreResult<RecoveryReport>) {}
    assert_recover(recover_on_startup);

    let report = RecoveryReport {
        cleaned_staging_files: 2,
        reverted_staging_db_rows: 1,
        warnings: vec!["kept active files untouched".to_owned()],
    };

    assert_eq!(report.cleaned_staging_files, 2);
    assert_eq!(report.reverted_staging_db_rows, 1);
    assert_eq!(
        report.warnings.as_slice(),
        &["kept active files untouched".to_owned()]
    );

    let documented_errors = [
        CoreError::repo_not_initialized("repository not initialized"),
        CoreError::db("database error"),
        CoreError::io("io error"),
        CoreError::permission_denied("permission denied"),
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn recover_on_startup_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "RecoveryReport recover_on_startup(string repo_path);",
        "dictionary RecoveryReport",
        "i64 cleaned_staging_files;",
        "i64 reverted_staging_db_rows;",
        "sequence<string> warnings;",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

#[test]
fn recover_on_startup_contract_api_documents_side_effects_errors_and_scope() {
    for fragment in [
        "`RepoNotInitialized { path }`",
        "`Db { message }`",
        "`Io { message }`",
        "`PermissionDenied { path }`",
    ] {
        assert_contains(ERROR_CODES, fragment);
    }

    for fragment in [
        "Recovers AreaMatrix-owned startup residue",
        "The input is an",
        "initialized repository root",
        "reports how many safe staging files",
        "`files.status = staging` rows",
        "error recovery surface can display",
        "The only allowed filesystem side effect",
        "`.areamatrix/staging/` directory",
        "must not delete",
        "active repository file",
        "does not repair corrupted",
        "reindex the repository",
        "process FSEvents",
        "generate overviews",
        "Returns `CoreError::RepoNotInitialized { path }`",
        "`CoreError::PermissionDenied { path }`",
        "`CoreError::Io { message }`",
        "`CoreError::Db { message }`",
    ] {
        assert_contains(API_RS, fragment);
    }
}
