use std::{fs, path::Path};

use area_matrix_core::{
    get_latest_scan_session, init_repo, list_files, preview_manual_rescan, reindex_from_filesystem,
    resume_scan_session, FileAvailabilityStatus, FileFilter, FileOrigin,
    ManualRescanPreviewItemKind, OverviewOutput, RepoInitMode, RepoInitOptions, ScanSessionKind,
    ScanSessionStatus, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

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

#[test]
fn manual_rescan_indexes_files_without_mutating_user_content() {
    let fixture = rescan_fixture();

    let report = reindex_from_filesystem(path_string(fixture.repo.path())).expect("manual rescan");

    assert!(report.scan_session_id.is_some());
    assert_eq!(report.inserted, 2);
    assert_eq!(report.updated, 0);
    assert!(report.skipped >= 2);
    assert_eq!(report.errors, Vec::<String>::new());
    fixture.assert_user_files_unchanged();

    let session = get_latest_scan_session(path_string(fixture.repo.path()))
        .expect("read latest scan session")
        .expect("manual rescan session should exist");
    assert_completed_reindex_session(&session, &report);

    let files = indexed_files(fixture.repo.path());
    assert_eq!(
        files
            .iter()
            .map(|file| file.path.as_str())
            .collect::<Vec<_>>(),
        vec!["README.md", "docs/spec.txt"]
    );
    assert_eq!(files[0].category, "__root__");
    assert_eq!(files[1].category, "docs");
}

#[test]
fn manual_rescan_preview_is_read_only_and_matches_confirm_page_counts() {
    let fixture = rescan_fixture();

    let preview =
        preview_manual_rescan(path_string(fixture.repo.path())).expect("preview manual rescan");

    assert_eq!(preview.added, 2);
    assert_eq!(preview.updated, 0);
    assert_eq!(preview.missing_or_deleted_from_fs, 0);
    assert_eq!(preview.conflicts, 0);
    assert_eq!(preview.unreadable, 0);
    assert_eq!(preview.unknown, 0);
    assert!(!preview.snapshot_id.is_empty());
    assert!(!preview.is_stale);
    assert!(preview
        .items
        .iter()
        .any(|item| item.relative_path == "README.md"));
    fixture.assert_user_files_unchanged();
    assert_eq!(indexed_paths(fixture.repo.path()), Vec::<String>::new());
    assert_eq!(
        scan_session_count(fixture.repo.path()),
        0,
        "dry-run preview must not create scan sessions"
    );
}

#[test]
fn manual_rescan_updates_changed_metadata_in_place_and_skips_stable_files() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    let docs = repo.path().join("docs");
    let spec = docs.join("spec.txt");
    fs::create_dir(&docs).expect("create docs directory");
    fs::write(repo.path().join("README.md"), "# User project\n").expect("write README");
    fs::write(&spec, "old content\n").expect("write initial user document");
    reindex_from_filesystem(path_string(repo.path())).expect("initial manual rescan");
    let initial = indexed_files(repo.path());
    let spec_before = initial
        .iter()
        .find(|file| file.path == "docs/spec.txt")
        .expect("spec should be indexed before update");

    fs::write(&spec, "new content\n").expect("simulate user editing file before rescan");
    let after_edit = fs::read(&spec).expect("read edited user document");
    let report = reindex_from_filesystem(path_string(repo.path())).expect("manual rescan update");

    assert_eq!(report.inserted, 0);
    assert_eq!(report.updated, 1);
    assert!(report.skipped >= 1);
    assert_eq!(report.errors, Vec::<String>::new());
    assert_eq!(
        fs::read(&spec).expect("read preserved edited user document"),
        after_edit
    );

    let updated = indexed_files(repo.path());
    let spec_after = updated
        .iter()
        .find(|file| file.path == "docs/spec.txt")
        .expect("spec should remain indexed after update");
    assert_eq!(spec_after.id, spec_before.id);
    assert_eq!(spec_after.path, "docs/spec.txt");
    assert_ne!(spec_after.hash_sha256, spec_before.hash_sha256);
    assert_eq!(spec_after.origin, FileOrigin::External);
    assert_eq!(spec_after.storage_mode, StorageMode::Indexed);
}

#[test]
fn manual_rescan_reports_missing_metadata_without_deleting_records() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    let spec = repo.path().join("docs/spec.txt");
    fs::create_dir_all(spec.parent().expect("spec should have parent")).expect("create docs");
    fs::write(&spec, "present before initial rescan\n").expect("write user document");
    reindex_from_filesystem(path_string(repo.path())).expect("initial manual rescan");
    fs::remove_file(&spec).expect("simulate user removing file outside AreaMatrix");

    let preview =
        preview_manual_rescan(path_string(repo.path())).expect("preview missing metadata");
    assert_eq!(preview.missing_or_deleted_from_fs, 1);
    assert_eq!(preview.added, 0);
    assert!(preview
        .items
        .iter()
        .any(|item| item.relative_path == "docs/spec.txt"));

    let report =
        reindex_from_filesystem(path_string(repo.path())).expect("rescan missing metadata");
    assert_eq!(report.missing, 1);
    assert_eq!(report.conflicts, 0);
    assert_eq!(report.unreadable, 0);
    assert_eq!(report.unknown, 0);

    let files = indexed_files(repo.path());
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].path, "docs/spec.txt");
    assert_eq!(
        files[0].availability_status,
        FileAvailabilityStatus::Missing
    );
}

#[test]
fn manual_rescan_reports_duplicate_hash_conflict_without_mutating_user_files() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    let original = repo.path().join("docs/original.txt");
    let copy = repo.path().join("docs/copy.txt");
    fs::create_dir_all(original.parent().expect("original should have parent"))
        .expect("create docs");
    fs::write(&original, "same content\n").expect("write original user document");
    reindex_from_filesystem(path_string(repo.path())).expect("seed original metadata");
    fs::write(&copy, "same content\n").expect("write external duplicate user document");
    let before = user_file_snapshot(&[&original, &copy]);

    let preview =
        preview_manual_rescan(path_string(repo.path())).expect("preview duplicate conflict");
    assert_eq!(preview.conflicts, 1);
    assert_eq!(preview.renamed_candidates, 0);
    assert!(preview.items.iter().any(|item| {
        item.kind == ManualRescanPreviewItemKind::Conflict && item.relative_path == "docs/copy.txt"
    }));

    let report =
        reindex_from_filesystem(path_string(repo.path())).expect("rescan duplicate conflict");
    assert_eq!(report.conflicts, 1);
    assert_eq!(report.unreadable, 0);
    assert_eq!(report.unknown, 0);
    assert_eq!(report.errors, Vec::<String>::new());
    assert_eq!(user_file_snapshot(&[&original, &copy]), before);

    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read conflict scan session")
        .expect("manual rescan should persist conflict session");
    assert_eq!(session.conflicts, 1);
    assert_eq!(
        indexed_paths(repo.path()),
        vec!["docs/copy.txt", "docs/original.txt"]
    );
}

#[test]
fn manual_rescan_resume_completed_session_returns_empty_report_without_rescanning() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    fs::write(repo.path().join("README.md"), "# User project\n").expect("write README");
    reindex_from_filesystem(path_string(repo.path())).expect("manual rescan");
    let completed = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session")
        .expect("manual rescan session should exist");

    fs::write(repo.path().join("later.txt"), "created after completion\n")
        .expect("write later user file");
    let report = resume_scan_session(path_string(repo.path()), completed.id)
        .expect("resume completed manual rescan session");

    assert_eq!(report.scan_session_id, Some(completed.id));
    assert_eq!(report.inserted, 0);
    assert_eq!(report.updated, 0);
    assert_eq!(report.missing, 0);
    assert_eq!(report.conflicts, 0);
    assert_eq!(report.unreadable, 0);
    assert_eq!(report.unknown, 0);
    assert_eq!(report.skipped, 0);
    assert_eq!(report.errors, Vec::<String>::new());
    assert_eq!(indexed_paths(repo.path()), vec!["README.md"]);
    assert_eq!(
        fs::read_to_string(repo.path().join("later.txt")).expect("read later user file"),
        "created after completion\n"
    );
}

fn scan_session_count(repo_path: &Path) -> i64 {
    Connection::open(repo_path.join(".areamatrix/index.db"))
        .expect("open repository database")
        .query_row("SELECT COUNT(*) FROM scan_sessions", [], |row| row.get(0))
        .expect("count scan sessions")
}

fn indexed_files(repo_path: &Path) -> Vec<area_matrix_core::FileEntry> {
    let mut files = list_files(path_string(repo_path), empty_filter()).expect("list indexed files");
    files.sort_by(|left, right| left.path.cmp(&right.path));
    for file in &files {
        assert_eq!(file.origin, FileOrigin::External);
        assert_eq!(file.storage_mode, StorageMode::Indexed);
        assert_eq!(file.source_path, None);
    }
    files
}

fn indexed_paths(repo_path: &Path) -> Vec<String> {
    indexed_files(repo_path)
        .into_iter()
        .map(|file| file.path)
        .collect()
}

struct RescanFixture {
    repo: tempfile::TempDir,
    user_paths: Vec<std::path::PathBuf>,
    user_snapshot: Vec<(String, Vec<u8>)>,
}

impl RescanFixture {
    fn assert_user_files_unchanged(&self) {
        let paths = self
            .user_paths
            .iter()
            .map(|path| path.as_path())
            .collect::<Vec<_>>();
        assert_eq!(user_file_snapshot(&paths), self.user_snapshot);
    }
}

fn rescan_fixture() -> RescanFixture {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");

    let readme = repo.path().join("README.md");
    let docs = repo.path().join("docs");
    let spec = docs.join("spec.txt");
    let root_overview = repo.path().join("AREAMATRIX.md");
    fs::create_dir(&docs).expect("create docs directory");
    fs::write(&readme, "# User project\n").expect("write user README");
    fs::write(&spec, "spec content\n").expect("write user document");
    fs::write(&root_overview, "user-authored overview\n").expect("write root overview");
    fs::write(repo.path().join(".DS_Store"), "finder metadata").expect("write finder metadata");
    fs::write(repo.path().join("scratch.tmp"), "temporary").expect("write temporary file");
    fs::write(
        repo.path().join(".areamatrix/generated/manual.md"),
        "generated overview",
    )
    .expect("write generated overview fixture");

    let user_paths = vec![readme, spec, root_overview];
    let snapshot_paths = user_paths
        .iter()
        .map(|path| path.as_path())
        .collect::<Vec<_>>();
    let user_snapshot = user_file_snapshot(&snapshot_paths);
    RescanFixture {
        repo,
        user_paths,
        user_snapshot,
    }
}

fn assert_completed_reindex_session(
    session: &area_matrix_core::ScanSession,
    report: &area_matrix_core::ReindexReport,
) {
    assert_eq!(Some(session.id), report.scan_session_id);
    assert_eq!(session.kind, ScanSessionKind::Reindex);
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert_eq!(session.inserted, report.inserted);
    assert_eq!(session.updated, report.updated);
    assert_eq!(session.missing, report.missing);
    assert_eq!(session.conflicts, report.conflicts);
    assert_eq!(session.unreadable, report.unreadable);
    assert_eq!(session.unknown, report.unknown);
    assert_eq!(session.skipped, report.skipped);
    assert_eq!(session.finished_at, Some(session.updated_at));
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
