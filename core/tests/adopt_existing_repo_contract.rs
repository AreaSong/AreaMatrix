use area_matrix_core::{
    get_latest_scan_session, init_repo, resume_scan_session, CoreError, CoreResult, FileEntry,
    FileOrigin, OverviewOutput, ReindexReport, RepoInitMode, RepoInitOptions, ScanSession,
    ScanSessionKind, ScanSessionStatus, StorageMode,
};
use pretty_assertions::assert_eq;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document to contain `{needle}`"
    );
}

#[test]
fn adopt_existing_repo_contract_exports_callable_signatures() {
    fn assert_init(_: fn(String, RepoInitOptions) -> CoreResult<()>) {}
    fn assert_latest(_: fn(String) -> CoreResult<Option<ScanSession>>) {}
    fn assert_resume(_: fn(String, i64) -> CoreResult<ReindexReport>) {}

    assert_init(init_repo);
    assert_latest(get_latest_scan_session);
    assert_resume(resume_scan_session);
}

#[test]
fn adopt_existing_repo_contract_exposes_documented_inputs() {
    let options = RepoInitOptions {
        mode: RepoInitMode::AdoptExisting,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    };

    assert_eq!(options.mode, RepoInitMode::AdoptExisting);
    assert!(!options.create_default_categories);
    assert_eq!(options.overview_output, OverviewOutput::GeneratedOnly);
}

#[test]
fn adopt_existing_repo_contract_exposes_documented_outputs() {
    let scan_session = ScanSession {
        id: 7,
        kind: ScanSessionKind::Adopt,
        status: ScanSessionStatus::Completed,
        last_path: Some("docs/readme.md".to_owned()),
        inserted: 1,
        updated: 0,
        skipped: 2,
        started_at: 10,
        updated_at: 20,
        finished_at: Some(20),
        errors: Vec::new(),
    };
    let report = ReindexReport {
        scan_session_id: Some(scan_session.id),
        inserted: scan_session.inserted,
        updated: scan_session.updated,
        skipped: scan_session.skipped,
        errors: scan_session.errors.clone(),
    };
    let entry = FileEntry {
        id: 11,
        path: "docs/readme.md".to_owned(),
        original_name: "readme.md".to_owned(),
        current_name: "readme.md".to_owned(),
        category: "docs".to_owned(),
        size_bytes: 42,
        hash_sha256: "hash".to_owned(),
        storage_mode: StorageMode::Indexed,
        origin: FileOrigin::Adopted,
        source_path: None,
        availability_status: area_matrix_core::FileAvailabilityStatus::Available,
        imported_at: 10,
        updated_at: 20,
    };

    assert_eq!(scan_session.kind, ScanSessionKind::Adopt);
    assert_eq!(report.scan_session_id, Some(7));
    assert_eq!(entry.origin, FileOrigin::Adopted);
    assert_eq!(entry.storage_mode, StorageMode::Indexed);
}

#[test]
fn adopt_existing_repo_contract_exposes_documented_error_codes() {
    let errors = [
        CoreError::permission_denied("permission denied"),
        CoreError::invalid_path("invalid path"),
        CoreError::io("io error"),
        CoreError::db("database error"),
        CoreError::config("configuration error"),
    ];

    assert_eq!(errors.len(), 5);
    for error_name in ["PermissionDenied", "InvalidPath", "Io", "Db", "Config"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(UDL, error_name);
    }
}

#[test]
fn adopt_existing_repo_contract_udl_matches_public_core_api() {
    for api_fragment in [
        "void init_repo(string repo_path, RepoInitOptions options);",
        "ScanSession? get_latest_scan_session(string repo_path);",
        "ReindexReport resume_scan_session(string repo_path, i64 scan_session_id);",
        "dictionary RepoInitOptions",
        "RepoInitMode mode;",
        "OverviewOutput overview_output;",
        "dictionary ScanSession",
        "ScanSessionKind kind;",
        "ScanSessionStatus status;",
        "string? last_path;",
        "sequence<string> errors;",
        "enum FileOrigin { \"Imported\", \"Adopted\", \"External\" };",
        "enum RepoInitMode { \"CreateEmpty\", \"AdoptExisting\" };",
        "enum ScanSessionKind { \"Adopt\", \"Reindex\" };",
    ] {
        assert_contains(CORE_API, api_fragment);
        assert_contains(UDL, api_fragment);
    }

    assert_contains(
        CAPABILITY_SPEC,
        "`init_repo(repo_path, RepoInitOptions { mode: AdoptExisting, ... })`",
    );
    assert_contains(CAPABILITY_SPEC, "`get_latest_scan_session(repo_path)`");
    assert_contains(
        CAPABILITY_SPEC,
        "`resume_scan_session(repo_path, scan_session_id)`",
    );
}

#[test]
fn adopt_existing_repo_contract_documents_side_effect_boundaries() {
    for fragment in [
        "只创建 `.areamatrix/**` 管理目录",
        "不移动、不重命名、不删除、不覆盖任何已有用户文件",
        "跳过 `.areamatrix/`、系统临时文件和 AreaMatrix generated overview",
        "`README.md` 作为普通用户文件索引",
        "`AREAMATRIX.md` 与 generated overview 按文档规则跳过",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    assert_contains(
        CORE_API,
        "`AdoptExisting`：目录可以非空；不移动、不重命名、不删除、不覆盖已有内容",
    );
    assert_contains(
        CORE_API,
        "仅当 `overview_output = RootAreaMatrixFile` 时写入/维护根目录",
    );
}

#[test]
fn adopt_existing_repo_contract_control_map_consumers_are_declared() {
    for fragment in [
        "| S1-03 | validate-path | C1-01, C1-03, C1-21 |",
        "| S1-04 | confirm-init | C1-02, C1-03 | `init_repo`",
        "| S1-05 | initializing | C1-02, C1-03, C1-16 | `init_repo`",
        "| S1-10 | main-loading | C1-03, C1-15, C1-16 |",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for page in [
        "- S1-03 validate-path",
        "- S1-04 confirm-init",
        "- S1-05 initializing",
        "- S1-10 main-loading",
    ] {
        assert_contains(CAPABILITY_SPEC, page);
    }
}
