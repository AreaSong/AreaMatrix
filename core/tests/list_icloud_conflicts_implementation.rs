use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_icloud_conflicts, CoreError, ICloudConflictStatus, OverviewOutput,
    RepoInitMode, RepoInitOptions,
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
    let parent = path.parent().expect("file has parent directory");
    fs::create_dir_all(parent).expect("create parent directory");
    fs::write(&path, bytes).expect("write repository file");
    path
}

fn active_file_count(repo: &Path) -> i64 {
    Connection::open(repo.join(".areamatrix/index.db"))
        .expect("open repository database")
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active file rows")
}

#[test]
fn list_icloud_conflicts_implementation_lists_standard_conflicted_copy_read_only() {
    let repo = initialized_repo();
    let original = write_repo_file(repo.path(), "docs/report.pdf", b"original");
    let conflicted = write_repo_file(
        repo.path(),
        "docs/report (Conflicted Copy of MacBook).pdf",
        b"conflicted",
    );

    let before_count = active_file_count(repo.path());
    let conflicts = list_icloud_conflicts(path_string(repo.path())).expect("list conflicts");

    assert_eq!(conflicts.len(), 1);
    let conflict = &conflicts[0];
    assert_eq!(conflict.conflict_id, conflict.conflicted_copy_path);
    assert_eq!(conflict.original_path.as_deref(), Some("docs/report.pdf"));
    assert_eq!(
        conflict.conflicted_copy_path,
        "docs/report (Conflicted Copy of MacBook).pdf"
    );
    assert_eq!(conflict.status, ICloudConflictStatus::NeedsReview);
    assert_eq!(conflict.uncertainty_reason, None);
    assert!(conflict.original_modified_at.is_some());
    assert!(conflict.conflicted_modified_at > 0);

    assert_eq!(
        fs::read(&original).expect("read original after list"),
        b"original"
    );
    assert_eq!(
        fs::read(&conflicted).expect("read conflicted copy after list"),
        b"conflicted"
    );
    assert_eq!(active_file_count(repo.path()), before_count);
}

#[test]
fn list_icloud_conflicts_implementation_marks_missing_original_as_uncertain() {
    let repo = initialized_repo();
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );

    let conflicts = list_icloud_conflicts(path_string(repo.path())).expect("list conflicts");

    assert_eq!(conflicts.len(), 1);
    assert_eq!(conflicts[0].original_path, None);
    assert_eq!(conflicts[0].original_modified_at, None);
    assert_eq!(conflicts[0].status, ICloudConflictStatus::NeedsReview);
    assert_eq!(
        conflicts[0].uncertainty_reason.as_deref(),
        Some("original version not found")
    );
}

#[test]
fn list_icloud_conflicts_implementation_rejects_placeholder_candidates() {
    let repo = initialized_repo();
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf.icloud",
        b"placeholder marker",
    );

    let result = list_icloud_conflicts(path_string(repo.path()));

    assert!(matches!(result, Err(CoreError::ICloudPlaceholder { .. })));
}

#[test]
fn list_icloud_conflicts_implementation_ignores_internal_metadata() {
    let repo = initialized_repo();
    write_repo_file(
        repo.path(),
        ".areamatrix/generated/report (Alice's conflicted copy).pdf",
        b"internal metadata",
    );

    let conflicts = list_icloud_conflicts(path_string(repo.path())).expect("list conflicts");

    assert!(conflicts.is_empty());
}
