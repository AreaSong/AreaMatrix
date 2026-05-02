use area_matrix_core::{recover_on_startup, CoreError, CoreResult, RecoveryReport};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
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
        CoreError::RepoNotInitialized,
        CoreError::Db,
        CoreError::Io,
        CoreError::PermissionDenied,
    ];
    assert_eq!(documented_errors.len(), 4);
}

#[test]
fn recover_on_startup_contract_api_docs_control_map_and_udl_stay_aligned() {
    for fragment in [
        "C1-16 recover-on-startup",
        "- S1-05 initializing",
        "- S1-10 main-loading",
        "- S1-30 settings-advanced",
        "- S1-32 error-recovery",
        "- `recover_on_startup(repo_path) -> RecoveryReport`",
        "- `repo_path`",
        "- `cleaned_staging_files`",
        "- `reverted_staging_db_rows`",
        "- `warnings`",
        "- 将未完成 staging rows 回滚或标记为可恢复状态。",
        "- 清理 `.areamatrix/staging/` 中可判定安全的临时文件。",
        "- 不删除任何最终目录用户文件。",
        "- `RepoNotInitialized`",
        "- `Db`",
        "- `Io`",
        "- `PermissionDenied`",
        "- 崩溃残留 staging 文件能清理。",
        "- active 文件和用户文件不得被误删。",
        "- recovery report 可直接驱动 S1-32 展示。",
        "- 自动从备份恢复损坏 DB 属于后续高级恢复。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-05 | initializing | C1-02, C1-03, C1-16 | `init_repo`, `recover_on_startup`, `get_latest_scan_session`",
        "| S1-10 | main-loading | C1-03, C1-15, C1-16 | `get_latest_scan_session`, `resume_scan_session`, `list_tree_json`",
        "| S1-30 | settings-advanced | C1-04, C1-16, C1-20 | `recover_on_startup`, `reindex_from_filesystem`, `update_config`",
        "| S1-32 | error-recovery | C1-16, C1-21 | `recover_on_startup`, error mapping",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志、笔记、Tree、recovery、错误映射。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

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
        "`Db(msg)`",
        "`Io(msg)`",
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
        "S1-32 can display",
        "The only allowed filesystem side effect",
        "`.areamatrix/staging/` directory",
        "must not delete",
        "active repository file",
        "does not repair corrupted",
        "reindex the repository",
        "process FSEvents",
        "generate overviews",
        "Returns `CoreError::RepoNotInitialized`",
        "`CoreError::PermissionDenied`",
        "`CoreError::Io`",
        "`CoreError::Db`",
    ] {
        assert_contains(API_RS, fragment);
    }
}
