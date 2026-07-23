use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    create_diagnostics_snapshot, get_latest_scan_session, init_repo, list_files, list_tree_json,
    preflight_repair_metadata, reindex_from_filesystem, repair_metadata, CoreError, FileFilter,
    FileOrigin, OverviewOutput, RepairMetadataLocaleState, RepairMetadataOutcome, RepairOptions,
    RepoInitMode, RepoInitOptions, ScanSessionKind, ScanSessionStatus, StorageMode,
};
use pretty_assertions::assert_eq;
use serde_json::Value;

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
            locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("initialize repository");
    repo
}

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) -> PathBuf {
    let path = repo.join(relative_path);
    let parent = path
        .parent()
        .expect("repository fixture path should have a parent");
    fs::create_dir_all(parent).expect("create repository fixture parent");
    fs::write(&path, bytes).expect("write repository fixture file");
    path
}

fn empty_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn repair_options(repo: &Path, preserve_snapshot: bool) -> RepairOptions {
    let preflight = preflight_repair_metadata(path_string(repo)).expect("preflight metadata repair");
    let repository_locale_policy = if preflight.locale_state == RepairMetadataLocaleState::Healthy {
        preflight
            .repository_locale_policy
            .clone()
            .expect("healthy repair preflight should return the exact locale")
    } else {
        "en".to_owned()
    };
    RepairOptions {
        preserve_diagnostics_snapshot: preserve_snapshot,
        preflight_token: preflight.preflight_token,
        repository_locale_policy,
    }
}

fn sorted_list_paths(repo: &Path) -> Vec<String> {
    let mut paths = list_files(path_string(repo), empty_filter())
        .expect("list files after metadata repair")
        .into_iter()
        .map(|file| {
            assert_eq!(file.origin, FileOrigin::External);
            assert_eq!(file.storage_mode, StorageMode::Indexed);
            file.path
        })
        .collect::<Vec<_>>();
    paths.sort();
    paths
}

fn parse_tree(repo: &Path) -> Value {
    let tree_json = list_tree_json(path_string(repo), "en".to_owned())
        .expect("list tree after metadata repair");
    serde_json::from_str(&tree_json).expect("parse tree JSON")
}

fn child_by_slug<'a>(node: &'a Value, slug: &str) -> &'a Value {
    node["children"]
        .as_array()
        .expect("TreeNode children should be an array")
        .iter()
        .find(|child| child["slug"] == slug)
        .unwrap_or_else(|| panic!("expected child slug `{slug}`"))
}

fn assert_latest_reindex_completed(repo: &Path, expected_id: Option<i64>) {
    let session = get_latest_scan_session(path_string(repo))
        .expect("read latest repair scan session")
        .expect("repair should create a reindex scan session");
    assert_eq!(session.kind, ScanSessionKind::Reindex);
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert_eq!(Some(session.id), expected_id);
}

fn user_file_snapshot(paths: &[&Path]) -> Vec<(String, Vec<u8>)> {
    paths
        .iter()
        .map(|path| {
            (
                path.to_string_lossy().into_owned(),
                fs::read(path).expect("read user file snapshot"),
            )
        })
        .collect()
}

#[test]
fn repair_reindex_metadata_validation_repair_preserves_files_before_explicit_reindex() {
    let repo = initialized_repo();
    let readme = write_repo_file(repo.path(), "README.md", b"# User project\n");
    let spec = write_repo_file(repo.path(), "docs/spec.txt", b"spec content\n");
    let root_overview = write_repo_file(repo.path(), "AREAMATRIX.md", b"user overview\n");
    write_repo_file(
        repo.path(),
        ".areamatrix/generated/root.md",
        b"generated overview\n",
    );
    let before = user_file_snapshot(&[&readme, &spec, &root_overview]);

    let report = repair_metadata(
        path_string(repo.path()),
        repair_options(repo.path(), true),
    )
    .expect("run metadata repair");

    let snapshot_path = report
        .diagnostics_snapshot_path
        .as_ref()
        .expect("full repair should preserve diagnostics");
    assert!(snapshot_path.starts_with(".areamatrix/diagnostics/index-"));
    assert!(repo.path().join(snapshot_path).is_file());
    assert_eq!(report.outcome, RepairMetadataOutcome::Verified);
    assert_eq!(
        user_file_snapshot(&[&readme, &spec, &root_overview]),
        before
    );

    assert_eq!(
        sorted_list_paths(repo.path()),
        Vec::<String>::new()
    );
    assert_eq!(
        get_latest_scan_session(path_string(repo.path())).expect("read repair scan session"),
        None
    );

    let reindex = reindex_from_filesystem(path_string(repo.path())).expect("run explicit reindex");
    assert_eq!(reindex.inserted, 2);
    assert_eq!(sorted_list_paths(repo.path()), vec!["README.md", "docs/spec.txt"]);
    let tree = parse_tree(repo.path());
    assert_eq!(tree["file_count"], 2);
    assert_eq!(child_by_slug(&tree, "docs")["file_count"], 1);
    assert_latest_reindex_completed(repo.path(), reindex.scan_session_id);
}

#[test]
fn repair_reindex_metadata_validation_metadata_repair_does_not_reindex_user_files() {
    let repo = initialized_repo();
    let unindexed = write_repo_file(repo.path(), "docs/unindexed.txt", b"pending content\n");
    let before = user_file_snapshot(&[&unindexed]);

    let report = repair_metadata(
        path_string(repo.path()),
        repair_options(repo.path(), false),
    )
    .expect("run metadata-only repair");

    assert_eq!(report.diagnostics_snapshot_path, None);
    assert_eq!(report.outcome, RepairMetadataOutcome::Verified);
    assert_eq!(sorted_list_paths(repo.path()), Vec::<String>::new());
    assert_eq!(user_file_snapshot(&[&unindexed]), before);
    assert_eq!(
        get_latest_scan_session(path_string(repo.path())).expect("read latest scan session"),
        None
    );
}

#[test]
fn repair_reindex_metadata_validation_uninitialized_repo_requires_confirmed_repair() {
    let repo = tempfile::tempdir().expect("create uninitialized repository directory");
    let readme = write_repo_file(repo.path(), "README.md", b"# User project\n");
    let before = user_file_snapshot(&[&readme]);

    assert_eq!(
        reindex_from_filesystem(path_string(repo.path())),
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );
    let report = repair_metadata(
        path_string(repo.path()),
        repair_options(repo.path(), true),
    )
    .expect("confirmed repair should initialize missing metadata");

    assert!(repo.path().join(".areamatrix/index.db").is_file());
    assert_eq!(report.diagnostics_snapshot_path, None);
    assert_eq!(report.outcome, RepairMetadataOutcome::Initialized);
    assert_eq!(sorted_list_paths(repo.path()), Vec::<String>::new());
    assert_eq!(
        get_latest_scan_session(path_string(repo.path())).expect("read repair scan session"),
        None
    );
    assert_eq!(user_file_snapshot(&[&readme]), before);

    let reindex = reindex_from_filesystem(path_string(repo.path())).expect("run explicit reindex");
    assert_eq!(reindex.inserted, 1);
    assert_eq!(sorted_list_paths(repo.path()), vec!["README.md"]);
}

#[test]
fn repair_reindex_metadata_validation_rejects_metadata_internal_paths() {
    let repo = initialized_repo();
    let user_file = write_repo_file(repo.path(), "docs/spec.txt", b"spec content\n");
    let before = user_file_snapshot(&[&user_file]);
    let metadata_path = repo.path().join(".areamatrix");

    assert_eq!(
        create_diagnostics_snapshot(path_string(&metadata_path)),
        Err(CoreError::invalid_path("invalid path"))
    );
    assert_eq!(
        reindex_from_filesystem(path_string(&metadata_path)),
        Err(CoreError::invalid_path("invalid path"))
    );
    assert_eq!(
        preflight_repair_metadata(path_string(&metadata_path)),
        Err(CoreError::invalid_path("invalid path"))
    );
    assert_eq!(user_file_snapshot(&[&user_file]), before);
}

#[test]
fn repair_reindex_metadata_validation_missing_index_db_returns_repo_not_initialized() {
    let repo = tempfile::tempdir().expect("create repository directory");
    fs::create_dir(repo.path().join(".areamatrix")).expect("create metadata directory fixture");
    let user_file = write_repo_file(repo.path(), "docs/spec.txt", b"spec content\n");
    let before = user_file_snapshot(&[&user_file]);

    assert_eq!(
        create_diagnostics_snapshot(path_string(repo.path())),
        Err(CoreError::repo_not_initialized(
            "repository not initialized"
        ))
    );

    assert!(!repo.path().join(".areamatrix/diagnostics").exists());
    assert_eq!(user_file_snapshot(&[&user_file]), before);
}
