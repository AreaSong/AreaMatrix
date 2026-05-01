use std::{fs, path::Path};

use area_matrix_core::{
    get_latest_scan_session, init_repo, list_files, resume_scan_session, FileFilter, FileOrigin,
    OverviewOutput, RepoInitMode, RepoInitOptions, ScanSessionKind, ScanSessionStatus, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn adopt_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::AdoptExisting,
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
fn adopt_existing_repo_indexes_user_files_without_changing_them() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let readme = repo.path().join("README.md");
    let docs = repo.path().join("docs");
    fs::create_dir(&docs).expect("create docs directory");
    let spec = docs.join("spec.txt");
    let root_areamatrix = repo.path().join("AREAMATRIX.md");
    fs::write(&readme, "# User project\n").expect("write user README");
    fs::write(&spec, "spec content\n").expect("write user document");
    fs::write(&root_areamatrix, "user-authored overview\n").expect("write user AREAMATRIX");
    fs::write(repo.path().join(".DS_Store"), "finder metadata").expect("write metadata");
    fs::write(repo.path().join("scratch.tmp"), "temporary").expect("write temp file");
    fs::create_dir(repo.path().join(".git")).expect("create git directory");
    fs::write(repo.path().join(".git/config"), "[core]\n").expect("write git config");

    init_repo(path_string(repo.path()), adopt_options()).expect("adopt existing repository");

    assert_eq!(
        fs::read_to_string(&readme).expect("read preserved README"),
        "# User project\n"
    );
    assert_eq!(
        fs::read_to_string(&spec).expect("read preserved document"),
        "spec content\n"
    );
    assert_eq!(
        fs::read_to_string(&root_areamatrix).expect("read preserved AREAMATRIX"),
        "user-authored overview\n"
    );

    let mut files =
        list_files(path_string(repo.path()), empty_filter()).expect("list adopted files");
    files.sort_by(|left, right| left.path.cmp(&right.path));
    let paths = files
        .iter()
        .map(|file| file.path.as_str())
        .collect::<Vec<_>>();
    assert_eq!(paths, vec!["README.md", "docs/spec.txt"]);

    let readme_entry = files
        .iter()
        .find(|file| file.path == "README.md")
        .expect("README should be indexed");
    assert_eq!(readme_entry.category, "__root__");
    assert_eq!(readme_entry.storage_mode, StorageMode::Indexed);
    assert_eq!(readme_entry.origin, FileOrigin::Adopted);
    assert_eq!(readme_entry.source_path, None);

    let docs_entry = files
        .iter()
        .find(|file| file.path == "docs/spec.txt")
        .expect("docs file should be indexed");
    assert_eq!(docs_entry.category, "docs");
    assert_eq!(docs_entry.storage_mode, StorageMode::Indexed);
    assert_eq!(docs_entry.origin, FileOrigin::Adopted);

    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session")
        .expect("adopt scan session should exist");
    assert_eq!(session.kind, ScanSessionKind::Adopt);
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert_eq!(session.last_path, Some("docs/spec.txt".to_owned()));
    assert_eq!(session.inserted, 2);
    assert_eq!(session.updated, 0);
    assert!(session.skipped >= 2);
    assert_eq!(session.errors, Vec::<String>::new());
}

#[test]
fn adopt_existing_repo_completed_resume_returns_empty_report() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    fs::write(repo.path().join("README.md"), "# User project\n").expect("write user README");
    init_repo(path_string(repo.path()), adopt_options()).expect("adopt existing repository");
    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session")
        .expect("adopt scan session should exist");

    let report = resume_scan_session(path_string(repo.path()), session.id)
        .expect("resume completed session");

    assert_eq!(report.scan_session_id, Some(session.id));
    assert_eq!(report.inserted, 0);
    assert_eq!(report.updated, 0);
    assert_eq!(report.skipped, 0);
    assert_eq!(report.errors, Vec::<String>::new());
}

#[test]
fn adopt_existing_repo_resume_interrupted_session_continues_after_last_path() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    fs::create_dir(repo.path().join("docs")).expect("create docs directory");
    fs::write(repo.path().join("README.md"), "# User project\n").expect("write README");
    fs::write(repo.path().join("docs/old.txt"), "old\n").expect("write old file");
    init_repo(path_string(repo.path()), adopt_options()).expect("adopt existing repository");
    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session")
        .expect("adopt scan session should exist");
    mark_session_interrupted(repo.path(), session.id);
    fs::write(repo.path().join("alpha-before.txt"), "before\n").expect("write earlier file");
    fs::write(repo.path().join("docs/zz-new.txt"), "new\n").expect("write later file");

    let report = resume_scan_session(path_string(repo.path()), session.id)
        .expect("resume interrupted adopt session");

    assert_eq!(report.scan_session_id, Some(session.id));
    assert_eq!(report.inserted, 3);
    assert_eq!(report.updated, 0);
    assert_eq!(report.skipped, 0);
    assert_eq!(report.errors, Vec::<String>::new());

    let mut paths = list_files(path_string(repo.path()), empty_filter())
        .expect("list files after resume")
        .into_iter()
        .map(|file| file.path)
        .collect::<Vec<_>>();
    paths.sort();
    assert_eq!(paths, vec!["README.md", "docs/old.txt", "docs/zz-new.txt"]);

    let resumed_session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session after resume")
        .expect("adopt scan session should still exist");
    assert_eq!(
        resumed_session.last_path,
        Some("docs/zz-new.txt".to_owned())
    );
}

#[test]
fn adopt_existing_repo_resume_keeps_last_path_when_only_ignored_paths_remain() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    fs::create_dir(repo.path().join("docs")).expect("create docs directory");
    fs::write(repo.path().join("README.md"), "# User project\n").expect("write README");
    fs::write(repo.path().join("docs/old.txt"), "old\n").expect("write old file");
    init_repo(path_string(repo.path()), adopt_options()).expect("adopt existing repository");
    let session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session")
        .expect("adopt scan session should exist");
    mark_session_interrupted(repo.path(), session.id);
    fs::write(repo.path().join("zz-after.tmp"), "ignored\n").expect("write ignored file");

    let report = resume_scan_session(path_string(repo.path()), session.id)
        .expect("resume interrupted adopt session");

    assert_eq!(report.scan_session_id, Some(session.id));
    assert_eq!(report.inserted, 2);
    assert_eq!(report.updated, 0);
    assert_eq!(report.skipped, 1);
    assert_eq!(report.errors, Vec::<String>::new());

    let resumed_session = get_latest_scan_session(path_string(repo.path()))
        .expect("read latest scan session after skipped-only resume")
        .expect("adopt scan session should still exist");
    assert_eq!(resumed_session.last_path, Some("docs/old.txt".to_owned()));
}

fn mark_session_interrupted(repo_path: &Path, scan_session_id: i64) {
    let connection =
        Connection::open(repo_path.join(".areamatrix/index.db")).expect("open repository db");
    connection
        .execute(
            "UPDATE scan_sessions
             SET status = 'interrupted', finished_at = NULL
             WHERE id = ?1",
            [scan_session_id],
        )
        .expect("mark scan session interrupted");
}
