use std::{fs, path::Path};

use area_matrix_core::{
    create_diagnostics_snapshot, get_latest_scan_session, init_repo, list_files, list_tree_json,
    repair_metadata, FileFilter, FileOrigin, OverviewOutput, RepairOptions, RepoInitMode,
    RepoInitOptions, ScanSessionKind, ScanSessionStatus, StorageMode,
};
use pretty_assertions::assert_eq;
use serde_json::Value;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");

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
    .expect("initialize repository metadata");
    repo
}

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) -> std::path::PathBuf {
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

fn sorted_list_paths(repo: &Path) -> Vec<String> {
    let mut paths = list_files(path_string(repo), empty_filter())
        .expect("list files after metadata repair metadata repair")
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

fn parse_tree(repo: &Path) -> Value {
    let tree_json = list_tree_json(path_string(repo), "en".to_owned())
        .expect("reload tree after metadata repair repair");
    serde_json::from_str(&tree_json).expect("parse tree JSON")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn repair_reindex_metadata_integration_verify_matches_docs_api_udl_and_consuming_pages() {
    for fragment in [
        "ReindexReport reindex_from_filesystem(string repo_path);",
        "DiagnosticsSnapshot create_diagnostics_snapshot(string repo_path);",
        "RepairReport repair_metadata(string repo_path, RepairOptions options);",
        "dictionary RepairOptions",
        "dictionary DiagnosticsSnapshot",
        "dictionary RepairReport",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    assert_contains(CORE_API, "metadata repair only");
    assert_contains(CORE_API, "不移动、不重命名、不删除用户文件");
}

#[test]
fn repair_reindex_metadata_integration_verify_confirmed_repair_reloads_list_and_tree() {
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

    let diagnostics =
        create_diagnostics_snapshot(path_string(repo.path())).expect("export diagnostics first");
    assert!(diagnostics
        .snapshot_path
        .starts_with(".areamatrix/diagnostics/index-"));
    assert_eq!(sorted_list_paths(repo.path()), Vec::<String>::new());
    assert_eq!(
        user_file_snapshot(&[&readme, &spec, &root_overview]),
        before
    );

    let report = repair_metadata(
        path_string(repo.path()),
        RepairOptions {
            full_rescan: true,
            preserve_diagnostics_snapshot: true,
        },
    )
    .expect("run user-confirmed full metadata repair");

    let snapshot_path = report
        .diagnostics_snapshot_path
        .as_ref()
        .expect("repair should preserve diagnostics before mutation");
    assert!(snapshot_path.starts_with(".areamatrix/diagnostics/index-"));
    assert!(repo.path().join(snapshot_path).is_file());
    assert!(report.scan_session_id.is_some());
    assert_eq!(report.inserted, 2);
    assert_eq!(report.updated, 0);
    assert!(report.skipped >= 1);
    assert_eq!(report.errors, Vec::<String>::new());
    assert_eq!(
        user_file_snapshot(&[&readme, &spec, &root_overview]),
        before
    );

    assert_eq!(
        sorted_list_paths(repo.path()),
        vec!["README.md", "docs/spec.txt"]
    );
    let tree = parse_tree(repo.path());
    assert_eq!(tree["file_count"], 2);
    let docs_node = tree["children"]
        .as_array()
        .expect("tree children should be an array")
        .iter()
        .find(|child| child["slug"] == "docs")
        .expect("tree should include docs node after repair");
    assert_eq!(docs_node["file_count"], 1);

    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session")
        .expect("confirmed repair should create a scan session");
    assert_eq!(Some(session.id), report.scan_session_id);
    assert_eq!(session.kind, ScanSessionKind::Reindex);
    assert_eq!(session.status, ScanSessionStatus::Completed);
}

#[test]
fn repair_reindex_metadata_integration_verify_corrupted_db_full_rescan_rebuilds_index() {
    let repo = initialized_repo();
    let readme = write_repo_file(repo.path(), "README.md", b"# User project\n");
    let before = user_file_snapshot(&[&readme]);
    let db_path = repo.path().join(".areamatrix/index.db");
    fs::write(&db_path, b"not a sqlite database").expect("corrupt AreaMatrix metadata fixture");

    let report = repair_metadata(
        path_string(repo.path()),
        RepairOptions {
            full_rescan: true,
            preserve_diagnostics_snapshot: true,
        },
    )
    .expect("confirmed full rescan should rebuild corrupted metadata");

    let snapshot_path = report
        .diagnostics_snapshot_path
        .as_ref()
        .expect("corrupted metadata repair should keep diagnostics");
    assert!(snapshot_path.starts_with(".areamatrix/diagnostics/index-"));
    assert_eq!(
        fs::read(repo.path().join(snapshot_path)).expect("read preserved diagnostics snapshot"),
        b"not a sqlite database"
    );
    assert!(report.scan_session_id.is_some());
    assert_eq!(report.inserted, 1);
    assert_eq!(report.updated, 0);
    assert_eq!(report.errors, Vec::<String>::new());
    assert_eq!(user_file_snapshot(&[&readme]), before);
    assert_eq!(sorted_list_paths(repo.path()), vec!["README.md"]);

    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session")
        .expect("corrupted metadata repair should create a scan session");
    assert_eq!(Some(session.id), report.scan_session_id);
    assert_eq!(session.kind, ScanSessionKind::Reindex);
    assert_eq!(session.status, ScanSessionStatus::Completed);
}
