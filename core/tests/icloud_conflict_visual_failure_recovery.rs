use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, preview_conflict_versions, resolve_icloud_conflict, CoreError,
    ICloudConflictResolution, OverviewOutput, RepoInitMode, RepoInitOptions,
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
