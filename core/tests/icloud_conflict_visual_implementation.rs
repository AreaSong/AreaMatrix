use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_icloud_conflicts, list_undo_actions, preview_conflict_versions,
    resolve_icloud_conflict, ICloudConflictPreviewStatus, ICloudConflictResolution,
    ICloudConflictStatus, ICloudConflictVersionRole, OverviewOutput, RepoInitMode, RepoInitOptions,
    UndoActionStatus,
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

fn change_rows(repo: &Path) -> Vec<(String, serde_json::Value)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT action, detail_json FROM change_log ORDER BY id")
        .expect("prepare change log query");
    statement
        .query_map([], |row| {
            let detail_json: String = row.get(1)?;
            Ok((
                row.get(0)?,
                serde_json::from_str(&detail_json).expect("detail json parses"),
            ))
        })
        .expect("query change log")
        .map(|row| row.expect("read change row"))
        .collect()
}

#[test]
fn icloud_conflict_visual_implementation_previews_versions_read_only() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        write_repo_file(repo.path(), "docs/report.pdf", b"original");
        write_repo_file(
            repo.path(),
            "docs/report (Alice's conflicted copy).pdf",
            b"conflicted",
        );
        let before = snapshot_tree(repo.path());

        let preview = preview_conflict_versions(
            path_string(repo.path()),
            "docs/report (Alice's conflicted copy).pdf".to_owned(),
        )
        .expect("preview iCloud conflict");

        assert_eq!(
            preview.default_resolution,
            ICloudConflictResolution::KeepBoth
        );
        assert!(preview.metadata_complete);
        assert!(preview.trash_available);
        assert!(preview.can_keep_both);
        assert!(preview.can_resolve_destructive);
        assert_eq!(preview.versions.len(), 2);
        assert!(preview.versions.iter().any(|version| {
            version.role == ICloudConflictVersionRole::Original
                && version.path == "docs/report.pdf"
                && version.size_bytes == Some(8)
                && version.hash_sha256.is_some()
                && version.preview_status == ICloudConflictPreviewStatus::MetadataOnly
        }));
        assert!(preview.versions.iter().any(|version| {
            version.role == ICloudConflictVersionRole::ConflictedCopy
                && version.path == "docs/report (Alice's conflicted copy).pdf"
                && version.size_bytes == Some(10)
                && version.hash_sha256.is_some()
        }));
        assert!(preview
            .resolution_options
            .iter()
            .all(|option| option.enabled));
        assert_eq!(snapshot_tree(repo.path()), before);
        assert!(change_rows(repo.path()).is_empty());
    });
}

#[test]
fn icloud_conflict_visual_implementation_keep_both_records_resolved_without_moving_versions() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        let original = write_repo_file(repo.path(), "docs/report.pdf", b"original");
        let conflicted = write_repo_file(
            repo.path(),
            "docs/report (Alice's conflicted copy).pdf",
            b"conflicted",
        );

        let report = resolve_icloud_conflict(
            path_string(repo.path()),
            "docs/report (Alice's conflicted copy).pdf".to_owned(),
            ICloudConflictResolution::KeepBoth,
        )
        .expect("resolve keep both");

        assert_eq!(report.status, ICloudConflictStatus::Resolved);
        assert_eq!(report.resolution, ICloudConflictResolution::KeepBoth);
        assert_eq!(
            report.kept_paths,
            vec![
                "docs/report.pdf".to_owned(),
                "docs/report (Alice's conflicted copy).pdf".to_owned(),
            ]
        );
        assert!(report.trashed_paths.is_empty());
        assert!(report.undo_token.is_none());
        assert_eq!(report.change_log_action, "external_modified");
        assert_eq!(fs::read(original).expect("read original"), b"original");
        assert_eq!(
            fs::read(conflicted).expect("read conflicted"),
            b"conflicted"
        );

        let conflicts = list_icloud_conflicts(path_string(repo.path())).expect("list conflicts");
        assert_eq!(conflicts[0].status, ICloudConflictStatus::Resolved);
        let rows = change_rows(repo.path());
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].0, "external_modified");
        assert_eq!(rows[0].1["kind"], "icloud_conflict_resolved");
        assert!(list_undo_actions(path_string(repo.path()))
            .expect("list undo actions")
            .is_empty());
    });
}

#[test]
fn icloud_conflict_visual_implementation_destructive_resolution_uses_trash() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let original = write_repo_file(repo.path(), "docs/report.pdf", b"original");
        let conflicted = write_repo_file(
            repo.path(),
            "docs/report (Alice's conflicted copy).pdf",
            b"conflicted",
        );

        let report = resolve_icloud_conflict(
            path_string(repo.path()),
            "docs/report (Alice's conflicted copy).pdf".to_owned(),
            ICloudConflictResolution::KeepOriginal,
        )
        .expect("resolve keep original");

        assert_eq!(report.status, ICloudConflictStatus::Resolved);
        assert_eq!(report.kept_paths, vec!["docs/report.pdf".to_owned()]);
        assert_eq!(
            report.trashed_paths,
            vec!["docs/report (Alice's conflicted copy).pdf".to_owned()]
        );
        assert!(report
            .undo_token
            .as_deref()
            .expect("destructive resolution creates undo token")
            .starts_with("undo:icloud-conflict-resolution:"));
        assert_eq!(fs::read(original).expect("read kept original"), b"original");
        assert!(!conflicted.exists());
        assert_eq!(
            fs::read(trash_dir.join("report (Alice's conflicted copy).pdf"))
                .expect("read trashed conflict"),
            b"conflicted"
        );

        let undo_actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");
        assert_eq!(undo_actions.len(), 1);
        assert_eq!(undo_actions[0].status, UndoActionStatus::Blocked);
        assert!(!undo_actions[0].can_undo);
    });
}
