use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, map_core_error, CoreError, DuplicateStrategy, ErrorKind,
    ErrorMappingInput, ErrorRecoverability, ErrorSeverity, ImportDestination, ImportOptions,
    OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{Connection, OptionalExtension};

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-23-c4-05-failure-edge.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-05-share-extension-import.md"
);
const TRANSACTIONAL_IMPORT: &str = include_str!("../../docs/architecture/transactional-import.md");

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
    }
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    repo
}

fn share_payload(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let app_group = tempfile::tempdir().expect("create app-group staging directory");
    let source_path = app_group.path().join(name);
    fs::write(&source_path, content).expect("write staged share payload");
    (app_group, source_path)
}

fn share_options(filename: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("inbox".to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::KeepBoth,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn row_count(repo: &Path, table: &str, status: Option<&str>) -> i64 {
    let connection = open_db(repo);
    match status {
        Some(status) => connection
            .query_row(
                &format!("SELECT COUNT(*) FROM {table} WHERE status = ?1"),
                [status],
                |row| row.get(0),
            )
            .expect("count rows by status"),
        None => connection
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .expect("count rows"),
    }
}

fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            [key],
            |row| row.get(0),
        )
        .optional()
        .expect("read repo config value")
}

fn table_exists(repo: &Path, table: &str) -> bool {
    open_db(repo)
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            [table],
            |_| Ok(true),
        )
        .optional()
        .expect("check table existence")
        .unwrap_or(false)
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn share_final_path(repo: &Path) -> PathBuf {
    repo.join("inbox/Shared Extension Item.pdf")
}

fn assert_clean_share_failure(repo: &Path) {
    assert_eq!(row_count(repo, "files", Some("active")), 0);
    assert_eq!(row_count(repo, "files", Some("staging")), 0);
    assert_eq!(row_count(repo, "change_log", None), 0);
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
    assert!(!share_final_path(repo).exists());
}

fn install_share_metadata_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_share_import_change_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'imported'
             BEGIN
               SELECT RAISE(ABORT, 'forced share import metadata failure');
             END;",
        )
        .expect("install share import metadata failure trigger");
}

#[test]
fn share_extension_import_failure_edge_docs_require_explicit_failure_semantics() {
    for fragment in [
        "覆盖空态、非法输入、权限、IO/DB 错误和错误码映射。",
        "必须证明失败不留下半成品。",
        "必须证明默认关闭、密钥不入日志。",
        "不得用吞错或静默降级掩盖失败。",
    ] {
        assert!(TASK.contains(fragment), "missing task fragment: {fragment}");
    }

    for fragment in [
        "Share Extension 超时不留下成功假状态。",
        "deferred import 可被主 app 继续。",
        "不把外部 app payload 内容写入日志。",
        "- `PermissionDenied`",
        "- `InvalidPath`",
        "- `Io`",
    ] {
        assert!(
            CAPABILITY_SPEC.contains(fragment),
            "missing capability fragment: {fragment}"
        );
    }

    for fragment in [
        "失败的 import 不留下 DB 记录或最终目录中的半文件",
        "ROLLBACK",
        "StagingGuard",
        "最终目录无变化",
        "Indexed 失败只回滚本次 DB staging 行",
    ] {
        assert!(
            TRANSACTIONAL_IMPORT.contains(fragment),
            "missing transactional import fragment: {fragment}"
        );
    }
}

#[test]
fn share_extension_import_failure_recovery_empty_deferred_state_has_no_core_side_effects() {
    let repo = initialized_repo();
    let (_app_group, source) = share_payload("queued-but-timeout.pdf", b"not imported yet");

    assert_eq!(
        fs::read(&source).expect("platform-owned payload remains staged"),
        b"not imported yet"
    );
    assert_clean_share_failure(repo.path());
    assert_eq!(
        repo_config_value(repo.path(), "ai_enabled"),
        Some("false".to_owned())
    );
    assert_eq!(
        repo_config_value(repo.path(), "remote_provider_config"),
        None
    );
    assert!(!table_exists(repo.path(), "ai_call_log"));
}

#[test]
fn share_extension_import_failure_recovery_invalid_inputs_are_explicit_and_non_mutating() {
    let repo = initialized_repo();

    let empty_repo = import_file(
        String::new(),
        "/tmp/share-item.pdf".to_owned(),
        share_options("Shared Extension Item.pdf"),
    );
    assert!(matches!(empty_repo, Err(CoreError::InvalidPath { .. })));

    let empty_source = import_file(
        path_string(repo.path()),
        String::new(),
        share_options("Shared Extension Item.pdf"),
    );
    assert!(matches!(empty_source, Err(CoreError::InvalidPath { .. })));

    let (_app_group, source) = share_payload("share-item.pdf", b"invalid filename input");
    let bad_filename = import_file(
        path_string(repo.path()),
        path_string(&source),
        share_options("bad/name.pdf"),
    );
    assert!(matches!(bad_filename, Err(CoreError::InvalidPath { .. })));
    assert_clean_share_failure(repo.path());

    let internal_source = repo.path().join(".areamatrix/staging/share-item.pdf");
    fs::write(&internal_source, b"internal staging file").expect("write internal staging file");
    let internal_result = import_file(
        path_string(repo.path()),
        path_string(&internal_source),
        share_options("Shared Extension Item.pdf"),
    );

    assert!(matches!(
        internal_result,
        Err(CoreError::InvalidPath { .. })
    ));
    assert_eq!(
        fs::read(&internal_source).expect("internal source remains untouched"),
        b"internal staging file"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 0);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 0);
    assert!(!share_final_path(repo.path()).exists());
}

#[cfg(unix)]
#[test]
fn share_extension_import_failure_recovery_permission_denied_maps_and_keeps_payload() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    let (_app_group, source) = share_payload("blocked.pdf", b"permission blocked payload bytes");
    let original_permissions = fs::metadata(&source)
        .expect("read source permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&source, blocked_permissions).expect("remove source read permission");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        share_options("Shared Extension Item.pdf"),
    );

    fs::set_permissions(&source, original_permissions).expect("restore source permissions");

    assert!(
        matches!(
            result,
            Err(CoreError::PermissionDenied { path }) if path == path_string(&source)
        ),
        "permission error should carry the share payload path"
    );
    assert_eq!(
        fs::read(&source).expect("share payload remains readable after permission restore"),
        b"permission blocked payload bytes"
    );
    assert_clean_share_failure(repo.path());

    let mapping = map_core_error(ErrorMappingInput {
        kind: ErrorKind::PermissionDenied,
        path: Some(path_string(&source)),
        reason: None,
        message: None,
    });
    assert_eq!(mapping.kind, ErrorKind::PermissionDenied);
    assert_eq!(mapping.severity, ErrorSeverity::High);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
}

#[test]
fn share_extension_import_failure_recovery_io_error_from_staging_root_has_no_half_product() {
    let repo = initialized_repo();
    let (_app_group, source) = share_payload("io-blocked.pdf", b"io failure payload bytes");
    let staging_root = repo.path().join(".areamatrix/staging");
    fs::remove_dir(&staging_root).expect("remove staging directory for IO blocker setup");
    fs::write(&staging_root, b"not a staging directory").expect("block staging directory");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        share_options("Shared Extension Item.pdf"),
    );

    assert!(matches!(result, Err(CoreError::Io { .. })));
    assert_eq!(
        fs::read(&source).expect("share payload survives staging IO failure"),
        b"io failure payload bytes"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 0);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 0);
    assert!(!share_final_path(repo.path()).exists());
}

#[test]
fn share_extension_import_failure_recovery_db_error_rolls_back_and_can_retry() {
    let repo = initialized_repo();
    let (_app_group, source) = share_payload("retry.pdf", b"retryable share payload bytes");
    install_share_metadata_failure(repo.path());

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        share_options("Shared Extension Item.pdf"),
    );

    assert!(matches!(result, Err(CoreError::Db { .. })));
    assert_eq!(
        fs::read(&source).expect("share payload survives DB failure"),
        b"retryable share payload bytes"
    );
    assert_clean_share_failure(repo.path());

    open_db(repo.path())
        .execute_batch("DROP TRIGGER fail_share_import_change_log;")
        .expect("remove share import metadata failure trigger");

    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        share_options("Shared Extension Item.pdf"),
    )
    .expect("retry share import after metadata failure");

    assert_eq!(entry.path, "inbox/Shared Extension Item.pdf");
    assert_eq!(
        fs::read(repo.path().join(&entry.path)).expect("read retried share import"),
        b"retryable share payload bytes"
    );
    assert_eq!(
        fs::read(&source).expect("copied share payload remains platform-owned"),
        b"retryable share payload bytes"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 1);
    assert_eq!(row_count(repo.path(), "files", Some("staging")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 1);
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn share_extension_import_failure_recovery_error_mapping_is_structured_and_side_effect_free() {
    let repo = initialized_repo();
    let (_app_group, source) = share_payload(
        "private-note.pdf",
        b"private share payload marker must not be logged",
    );
    let user_readme = repo.path().join("README.md");
    fs::write(&user_readme, b"user-authored readme").expect("write user README");

    let mappings = [
        map_core_error(ErrorMappingInput {
            kind: ErrorKind::InvalidPath,
            path: Some(path_string(&source)),
            reason: None,
            message: None,
        }),
        map_core_error(ErrorMappingInput {
            kind: ErrorKind::Io,
            path: None,
            reason: None,
            message: Some("share import filesystem failure".to_owned()),
        }),
        map_core_error(ErrorMappingInput {
            kind: ErrorKind::Db,
            path: None,
            reason: None,
            message: Some("SQLITE_BUSY: database is locked".to_owned()),
        }),
    ];

    assert_eq!(mappings[0].kind, ErrorKind::InvalidPath);
    assert_eq!(
        mappings[0].recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(mappings[1].kind, ErrorKind::Io);
    assert_eq!(mappings[1].recoverability, ErrorRecoverability::Retryable);
    assert_eq!(mappings[2].kind, ErrorKind::Db);
    assert_eq!(mappings[2].recoverability, ErrorRecoverability::Retryable);
    assert_eq!(
        fs::read(&source).expect("mapping does not touch payload"),
        b"private share payload marker must not be logged"
    );
    assert_eq!(
        fs::read(&user_readme).expect("mapping does not touch user README"),
        b"user-authored readme"
    );
    assert_eq!(row_count(repo.path(), "files", Some("active")), 0);
    assert_eq!(row_count(repo.path(), "change_log", None), 0);
}
