use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, load_config, map_core_error, preview_conflict_versions, resolve_icloud_conflict,
    CoreError, ErrorKind, ErrorMappingInput, ErrorRecoverability, ICloudConflictResolution,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

mod support;

use support::system_trash_home::with_test_system_trash;

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

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) -> PathBuf {
    let path = repo.join(relative_path);
    fs::create_dir_all(path.parent().expect("fixture has parent directory"))
        .expect("create fixture parent");
    fs::write(&path, bytes).expect("write fixture file");
    path
}

fn snapshot_tree(root: &Path) -> BTreeMap<PathBuf, Option<Vec<u8>>> {
    let mut snapshot = BTreeMap::new();
    collect_snapshot(root, root, &mut snapshot);
    snapshot
}

fn collect_snapshot(
    root: &Path,
    current: &Path,
    snapshot: &mut BTreeMap<PathBuf, Option<Vec<u8>>>,
) {
    for entry in fs::read_dir(current).expect("read snapshot directory") {
        let entry = entry.expect("read snapshot entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(root)
            .expect("snapshot path stays under root")
            .to_path_buf();
        let file_type = entry.file_type().expect("read snapshot file type");
        if file_type.is_dir() {
            snapshot.insert(relative, None);
            collect_snapshot(root, &path, snapshot);
        } else if file_type.is_file() {
            snapshot.insert(relative, Some(fs::read(&path).expect("read snapshot file")));
        }
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
}

fn undo_action_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM undo_actions", [], |row| row.get(0))
        .expect("count undo action rows")
}

fn config_keys_like(repo: &Path, pattern: &str) -> Vec<String> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT key FROM repo_config WHERE key LIKE ?1 ORDER BY key")
        .expect("prepare config key query");
    statement
        .query_map([pattern], |row| row.get(0))
        .expect("query config keys")
        .map(|row| row.expect("read config key"))
        .collect()
}

fn conflict_resolution_change_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*)
             FROM change_log
             WHERE action = 'external_modified'
               AND json_extract(detail_json, '$.kind') = 'icloud_conflict_resolved'",
            [],
            |row| row.get(0),
        )
        .expect("count conflict resolution rows")
}

fn install_icloud_resolution_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_icloud_resolution_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'external_modified'
              AND json_extract(NEW.detail_json, '$.kind') = 'icloud_conflict_resolved'
             BEGIN
               SELECT RAISE(ABORT, 'forced icloud resolution log failure');
             END;",
        )
        .expect("install conflict resolution log failure trigger");
}

#[test]
fn icloud_conflict_visual_failure_edge_empty_repo_path_is_invalid_without_side_effects() {
    let preview = preview_conflict_versions(
        "   ".to_owned(),
        "docs/report (Alice's conflicted copy).pdf".to_owned(),
    );
    let resolve = resolve_icloud_conflict(
        "".to_owned(),
        "docs/report (Alice's conflicted copy).pdf".to_owned(),
        ICloudConflictResolution::KeepBoth,
    );

    assert!(matches!(preview, Err(CoreError::InvalidPath { .. })));
    assert!(matches!(resolve, Err(CoreError::InvalidPath { .. })));
}

#[test]
fn icloud_conflict_visual_failure_edge_empty_state_is_read_only_and_returns_stale_conflict() {
    let repo = initialized_repo();
    let before = snapshot_tree(repo.path());

    let preview = preview_conflict_versions(
        path_string(repo.path()),
        "docs/report (Alice's conflicted copy).pdf".to_owned(),
    );
    let resolve = resolve_icloud_conflict(
        path_string(repo.path()),
        "docs/report (Alice's conflicted copy).pdf".to_owned(),
        ICloudConflictResolution::KeepBoth,
    );

    assert!(matches!(preview, Err(CoreError::Conflict { .. })));
    assert!(matches!(resolve, Err(CoreError::Conflict { .. })));
    assert_eq!(snapshot_tree(repo.path()), before);
    assert_eq!(change_log_count(repo.path()), 0);
    assert_eq!(undo_action_count(repo.path()), 0);
}

#[test]
fn icloud_conflict_visual_failure_edge_invalid_conflict_id_is_rejected_without_side_effects() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        write_repo_file(repo.path(), "docs/report.pdf", b"original");
        write_repo_file(
            repo.path(),
            "docs/report (Alice's conflicted copy).pdf",
            b"conflicted",
        );
        let before = snapshot_tree(repo.path());

        for invalid_id in [
            "",
            "../outside.pdf",
            ".areamatrix/index.db",
            "/tmp/outside.pdf",
        ] {
            let preview =
                preview_conflict_versions(path_string(repo.path()), invalid_id.to_owned());
            let resolve = resolve_icloud_conflict(
                path_string(repo.path()),
                invalid_id.to_owned(),
                ICloudConflictResolution::KeepOriginal,
            );

            assert!(
                matches!(preview, Err(CoreError::Conflict { .. })),
                "preview should reject invalid id {invalid_id:?}"
            );
            assert!(
                matches!(resolve, Err(CoreError::Conflict { .. })),
                "resolve should reject invalid id {invalid_id:?}"
            );
        }

        assert_eq!(snapshot_tree(repo.path()), before);
        assert_eq!(change_log_count(repo.path()), 0);
        assert_eq!(undo_action_count(repo.path()), 0);
    });
}

#[test]
fn icloud_conflict_visual_failure_edge_rejects_placeholder_without_side_effects() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        write_repo_file(repo.path(), "docs/report.pdf", b"original");
        write_repo_file(
            repo.path(),
            "docs/report (Alice's conflicted copy).pdf.icloud",
            b"placeholder marker",
        );
        let before = snapshot_tree(repo.path());

        let preview = preview_conflict_versions(
            path_string(repo.path()),
            "docs/report (Alice's conflicted copy).pdf.icloud".to_owned(),
        );
        let resolve = resolve_icloud_conflict(
            path_string(repo.path()),
            "docs/report (Alice's conflicted copy).pdf.icloud".to_owned(),
            ICloudConflictResolution::KeepBoth,
        );

        assert!(matches!(preview, Err(CoreError::ICloudPlaceholder { .. })));
        assert!(matches!(resolve, Err(CoreError::ICloudPlaceholder { .. })));
        assert_eq!(snapshot_tree(repo.path()), before);
        assert_eq!(change_log_count(repo.path()), 0);
        assert_eq!(undo_action_count(repo.path()), 0);
    });
}

#[test]
fn icloud_conflict_visual_failure_edge_missing_original_blocks_destructive_choice() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        let conflicted = write_repo_file(
            repo.path(),
            "docs/report (Alice's conflicted copy).pdf",
            b"conflicted",
        );
        let before = snapshot_tree(repo.path());

        let preview = preview_conflict_versions(
            path_string(repo.path()),
            "docs/report (Alice's conflicted copy).pdf".to_owned(),
        )
        .expect("preview incomplete conflict");
        let result = resolve_icloud_conflict(
            path_string(repo.path()),
            "docs/report (Alice's conflicted copy).pdf".to_owned(),
            ICloudConflictResolution::KeepOriginal,
        );

        assert!(!preview.metadata_complete);
        assert!(preview.can_keep_both);
        assert!(!preview.can_resolve_destructive);
        assert!(matches!(result, Err(CoreError::Conflict { .. })));
        assert_eq!(snapshot_tree(repo.path()), before);
        assert_eq!(
            fs::read(conflicted)
                .expect("conflicted copy remains after blocked destructive resolve"),
            b"conflicted"
        );
        assert_eq!(change_log_count(repo.path()), 0);
        assert_eq!(undo_action_count(repo.path()), 0);
    });
}

#[test]
fn icloud_conflict_visual_failure_edge_destructive_resolution_rolls_back_db_failure() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let original = write_repo_file(repo.path(), "docs/report.pdf", b"original");
        let conflicted = write_repo_file(
            repo.path(),
            "docs/report (Alice's conflicted copy).pdf",
            b"conflicted",
        );
        let before_change_count = change_log_count(repo.path());
        let before_undo_count = undo_action_count(repo.path());
        install_icloud_resolution_log_failure(repo.path());

        let result = resolve_icloud_conflict(
            path_string(repo.path()),
            "docs/report (Alice's conflicted copy).pdf".to_owned(),
            ICloudConflictResolution::KeepOriginal,
        );

        assert!(matches!(result, Err(CoreError::Db { .. })));
        assert_eq!(fs::read(original).expect("read original"), b"original");
        assert_eq!(
            fs::read(conflicted).expect("read conflicted"),
            b"conflicted"
        );
        assert!(!trash_dir
            .join("report (Alice's conflicted copy).pdf")
            .exists());
        assert_eq!(change_log_count(repo.path()), before_change_count);
        assert_eq!(undo_action_count(repo.path()), before_undo_count);
    });
}

#[test]
fn icloud_conflict_visual_failure_edge_failed_destructive_retry_can_keep_both() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        let original = write_repo_file(repo.path(), "docs/report.pdf", b"original");
        let conflicted = write_repo_file(
            repo.path(),
            "docs/report (Alice's conflicted copy).pdf",
            b"conflicted",
        );
        install_icloud_resolution_log_failure(repo.path());

        let failed = resolve_icloud_conflict(
            path_string(repo.path()),
            "docs/report (Alice's conflicted copy).pdf".to_owned(),
            ICloudConflictResolution::KeepOriginal,
        );
        assert!(matches!(failed, Err(CoreError::Db { .. })));

        open_db(repo.path())
            .execute("DROP TRIGGER fail_icloud_resolution_log", [])
            .expect("remove forced log failure trigger");
        let retry = resolve_icloud_conflict(
            path_string(repo.path()),
            "docs/report (Alice's conflicted copy).pdf".to_owned(),
            ICloudConflictResolution::KeepBoth,
        )
        .expect("retry can keep both after rollback");

        assert_eq!(retry.trashed_paths, Vec::<String>::new());
        assert_eq!(
            fs::read(original).expect("read original after retry"),
            b"original"
        );
        assert_eq!(
            fs::read(conflicted).expect("read conflicted after retry"),
            b"conflicted"
        );
        assert_eq!(conflict_resolution_change_count(repo.path()), 1);
        assert_eq!(undo_action_count(repo.path()), 0);
    });
}

#[test]
fn icloud_conflict_visual_failure_edge_trash_unavailable_blocks_destructive_choice() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/report.pdf", b"original");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );
    let previous_home = std::env::var_os("HOME");
    std::env::remove_var("HOME");

    let preview = preview_conflict_versions(
        path_string(repo.path()),
        "docs/report (Alice's conflicted copy).pdf".to_owned(),
    )
    .expect("preview with unavailable trash");
    let result = resolve_icloud_conflict(
        path_string(repo.path()),
        "docs/report (Alice's conflicted copy).pdf".to_owned(),
        ICloudConflictResolution::KeepOriginal,
    );

    match previous_home {
        Some(value) => std::env::set_var("HOME", value),
        None => std::env::remove_var("HOME"),
    }

    assert!(!preview.trash_available);
    assert!(!preview.can_resolve_destructive);
    assert!(preview
        .resolution_options
        .iter()
        .filter(|option| option.destructive)
        .all(|option| !option.enabled));
    assert!(matches!(result, Err(CoreError::Conflict { .. })));
    assert_eq!(change_log_count(repo.path()), 0);
    assert_eq!(undo_action_count(repo.path()), 0);
}

#[test]
fn icloud_conflict_visual_failure_edge_error_mapping_keeps_retry_and_user_action_boundaries() {
    let icloud = map_core_error(ErrorMappingInput {
        kind: ErrorKind::ICloudPlaceholder,
        path: Some("docs/report (Alice's conflicted copy).pdf.icloud".to_owned()),
        reason: Some("permission denied".to_owned()),
        message: Some("database is locked".to_owned()),
    });
    let permission = map_core_error(ErrorMappingInput {
        kind: ErrorKind::PermissionDenied,
        path: Some("/restricted/repo/docs/report.pdf".to_owned()),
        reason: Some("icloud placeholder can retry".to_owned()),
        message: Some("database is locked".to_owned()),
    });
    let db = map_core_error(ErrorMappingInput {
        kind: ErrorKind::Db,
        path: Some("/ignored".to_owned()),
        reason: Some("ignored".to_owned()),
        message: Some("forced icloud resolution log failure".to_owned()),
    });

    assert_eq!(icloud.kind, ErrorKind::ICloudPlaceholder);
    assert_eq!(icloud.recoverability, ErrorRecoverability::Retryable);
    assert_eq!(permission.kind, ErrorKind::PermissionDenied);
    assert_eq!(
        permission.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(db.kind, ErrorKind::Db);
    assert_eq!(db.recoverability, ErrorRecoverability::UserActionRequired);
}

#[test]
fn icloud_conflict_visual_failure_edge_does_not_enable_ai_or_remote_privacy_paths() {
    let repo = initialized_repo();
    let config = load_config(path_string(repo.path())).expect("load repository config");

    let preview = preview_conflict_versions(
        path_string(repo.path()),
        "docs/report (Alice's conflicted copy).pdf".to_owned(),
    );

    assert!(matches!(preview, Err(CoreError::Conflict { .. })));
    assert!(!config.ai_enabled);

    assert!(config_keys_like(repo.path(), "%api_key%").is_empty());
    assert!(config_keys_like(repo.path(), "%token%").is_empty());
}
