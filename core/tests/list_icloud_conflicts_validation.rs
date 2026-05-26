use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_icloud_conflicts, CoreError, ICloudConflictPair, ICloudConflictStatus,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
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
    let parent = path
        .parent()
        .expect("repository fixture should have parent");
    fs::create_dir_all(parent).expect("create fixture parent directory");
    fs::write(&path, bytes).expect("write repository fixture file");
    path
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn active_file_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active file rows")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change_log rows")
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
            .expect("snapshot path should stay under repository root")
            .to_path_buf();
        let file_type = entry.file_type().expect("read snapshot file type");
        if file_type.is_dir() {
            snapshot.insert(relative, None);
            collect_snapshot(root, &path, snapshot);
        } else if file_type.is_file() {
            snapshot.insert(relative, Some(fs::read(path).expect("read snapshot file")));
        }
    }
}

fn conflict_by_path<'a>(
    conflicts: &'a [ICloudConflictPair],
    conflicted_copy_path: &str,
) -> &'a ICloudConflictPair {
    conflicts
        .iter()
        .find(|conflict| conflict.conflicted_copy_path == conflicted_copy_path)
        .unwrap_or_else(|| panic!("expected conflict `{conflicted_copy_path}`"))
}

#[test]
fn list_icloud_conflicts_validation_success_is_structured_sorted_and_read_only() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/report.pdf", b"original report");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted report",
    );
    write_repo_file(repo.path(), "finance/invoice.pdf", b"original invoice");
    write_repo_file(
        repo.path(),
        "finance/invoice (Bob's conflicted copy).pdf",
        b"conflicted invoice",
    );
    write_repo_file(
        repo.path(),
        ".areamatrix/generated/ignored (Alice's conflicted copy).pdf",
        b"metadata must stay ignored",
    );

    let before_snapshot = snapshot_tree(repo.path());
    let before_active = active_file_count(repo.path());
    let before_log = change_log_count(repo.path());
    let conflicts = list_icloud_conflicts(path_string(repo.path())).expect("list iCloud conflicts");

    assert_eq!(conflicts.len(), 2);
    assert_eq!(conflicts, {
        let mut sorted = conflicts.clone();
        sorted.sort_by(|left, right| {
            right
                .conflicted_modified_at
                .cmp(&left.conflicted_modified_at)
                .then_with(|| left.conflicted_copy_path.cmp(&right.conflicted_copy_path))
        });
        sorted
    });

    let report = conflict_by_path(&conflicts, "docs/report (Alice's conflicted copy).pdf");
    assert_eq!(report.conflict_id, report.conflicted_copy_path);
    assert_eq!(report.original_path.as_deref(), Some("docs/report.pdf"));
    assert_eq!(report.status, ICloudConflictStatus::NeedsReview);
    assert_eq!(report.uncertainty_reason, None);
    assert!(report.original_modified_at.is_some());
    assert!(report.conflicted_modified_at > 0);

    assert_eq!(snapshot_tree(repo.path()), before_snapshot);
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);
}

#[test]
fn list_icloud_conflicts_validation_uncertain_pair_stays_needs_review() {
    let repo = initialized_repo();
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted without original",
    );
    let before_snapshot = snapshot_tree(repo.path());

    let conflicts = list_icloud_conflicts(path_string(repo.path())).expect("list iCloud conflicts");

    assert_eq!(conflicts.len(), 1);
    assert_eq!(conflicts[0].original_path, None);
    assert_eq!(conflicts[0].original_modified_at, None);
    assert_eq!(conflicts[0].status, ICloudConflictStatus::NeedsReview);
    assert_eq!(
        conflicts[0].uncertainty_reason.as_deref(),
        Some("original version not found")
    );
    assert_eq!(snapshot_tree(repo.path()), before_snapshot);
}

#[test]
fn list_icloud_conflicts_validation_placeholder_error_preserves_files_and_metadata() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/report.pdf", b"original");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf.icloud",
        b"placeholder marker",
    );
    let before_snapshot = snapshot_tree(repo.path());
    let before_active = active_file_count(repo.path());
    let before_log = change_log_count(repo.path());

    let result = list_icloud_conflicts(path_string(repo.path()));

    assert!(matches!(result, Err(CoreError::ICloudPlaceholder { .. })));
    assert_eq!(snapshot_tree(repo.path()), before_snapshot);
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);
}

#[test]
fn list_icloud_conflicts_validation_missing_repo_path_returns_file_not_found() {
    let parent = tempfile::tempdir().expect("create temporary parent directory");
    let missing_repo = parent.path().join("missing-repository");

    let result = list_icloud_conflicts(path_string(&missing_repo));

    assert!(matches!(result, Err(CoreError::FileNotFound { .. })));
}

#[cfg(unix)]
#[test]
fn list_icloud_conflicts_validation_permission_denied_preserves_existing_state() {
    use std::os::unix::fs::PermissionsExt;

    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/report.pdf", b"original");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );
    let blocked_dir = repo.path().join("blocked");
    write_repo_file(
        repo.path(),
        "blocked/secret (Alice's conflicted copy).pdf",
        b"secret",
    );
    let original_permissions = fs::metadata(&blocked_dir)
        .expect("read blocked directory permissions")
        .permissions();
    let before_snapshot = snapshot_tree(repo.path());
    let before_active = active_file_count(repo.path());
    let before_log = change_log_count(repo.path());

    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o000);
    fs::set_permissions(&blocked_dir, blocked_permissions).expect("remove blocked permissions");
    let can_still_read = fs::read_dir(&blocked_dir).is_ok();
    let result = list_icloud_conflicts(path_string(repo.path()));
    fs::set_permissions(&blocked_dir, original_permissions).expect("restore blocked permissions");

    if can_still_read {
        return;
    }

    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert_eq!(snapshot_tree(repo.path()), before_snapshot);
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);
}
