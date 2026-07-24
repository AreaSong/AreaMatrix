use std::{fs, path::Path};

use area_matrix_core::{
    create_diagnostics_snapshot, get_latest_scan_session, init_repo, list_files,
    preflight_repair_metadata, reindex_from_filesystem, repair_metadata, FileFilter, FileOrigin,
    OverviewOutput, RepairMetadataLocaleState, RepairMetadataOutcome, RepairOptions, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options() -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output: OverviewOutput::GeneratedOnly,
        locale_policy: area_matrix_core::RepositoryLocalePolicy::FollowInterface,
        content_locale: area_matrix_core::ContentLocale::En,
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

fn repair_options(repo: &Path, preserve_snapshot: bool) -> RepairOptions {
    let preflight =
        preflight_repair_metadata(path_string(repo)).expect("preflight metadata repair");
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

#[test]
fn repair_reindex_metadata_implementation_indexes_files_without_touching_user_content() {
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
    let before = user_file_snapshot(&[&readme, &spec, &root_overview]);

    let report =
        reindex_from_filesystem(path_string(repo.path())).expect("reindex repository metadata");

    assert!(report.scan_session_id.is_some());
    assert_eq!(report.inserted, 2);
    assert_eq!(report.updated, 0);
    assert!(report.skipped >= 1);
    assert_eq!(report.errors, Vec::<String>::new());
    assert_eq!(
        user_file_snapshot(&[&readme, &spec, &root_overview]),
        before
    );

    let mut files = list_files(path_string(repo.path()), empty_filter()).expect("list files");
    files.sort_by(|left, right| left.path.cmp(&right.path));
    assert_eq!(
        files
            .iter()
            .map(|file| file.path.as_str())
            .collect::<Vec<_>>(),
        vec!["README.md", "docs/spec.txt"]
    );
    assert!(files.iter().all(|file| file.origin == FileOrigin::External));
    assert!(files
        .iter()
        .all(|file| file.storage_mode == StorageMode::Indexed));
    assert!(files.iter().all(|file| file.source_path.is_none()));
}

#[test]
fn repair_reindex_metadata_implementation_updates_changed_metadata_in_place() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    let docs = repo.path().join("docs");
    let spec = docs.join("spec.txt");
    fs::create_dir(&docs).expect("create docs directory");
    fs::write(&spec, "old content\n").expect("write initial user document");
    reindex_from_filesystem(path_string(repo.path())).expect("initial reindex");
    let initial = list_files(path_string(repo.path()), empty_filter())
        .expect("list initial files")
        .remove(0);

    fs::write(&spec, "new content\n").expect("simulate user editing file before reindex");
    let report = reindex_from_filesystem(path_string(repo.path())).expect("reindex changed file");

    assert_eq!(report.inserted, 0);
    assert_eq!(report.updated, 1);
    assert_eq!(report.errors, Vec::<String>::new());
    let updated = list_files(path_string(repo.path()), empty_filter())
        .expect("list updated files")
        .remove(0);
    assert_eq!(updated.id, initial.id);
    assert_eq!(updated.path, "docs/spec.txt");
    assert_ne!(updated.hash_sha256, initial.hash_sha256);
    assert_eq!(
        fs::read_to_string(&spec).expect("read preserved user document"),
        "new content\n"
    );
}

#[test]
fn repair_reindex_metadata_implementation_creates_diagnostics_snapshot_under_metadata() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    let readme = repo.path().join("README.md");
    fs::write(&readme, "# User project\n").expect("write user README");
    let before = fs::read_to_string(&readme).expect("read README before diagnostics");

    let snapshot =
        create_diagnostics_snapshot(path_string(repo.path())).expect("create diagnostics snapshot");

    assert!(snapshot
        .snapshot_path
        .starts_with(".areamatrix/diagnostics/index-"));
    assert!(repo.path().join(&snapshot.snapshot_path).is_file());
    assert_eq!(
        fs::read_to_string(&readme).expect("read README after diagnostics"),
        before
    );
    assert!(snapshot.created_at > 0);
}

#[test]
fn repair_reindex_metadata_implementation_preserves_snapshot_without_implicit_rescan() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    init_repo(path_string(repo.path()), create_empty_options()).expect("initialize repository");
    fs::create_dir(repo.path().join("docs")).expect("create docs directory");
    fs::write(repo.path().join("docs/spec.txt"), "spec content\n").expect("write document");

    let report = repair_metadata(path_string(repo.path()), repair_options(repo.path(), true))
        .expect("verify healthy metadata");

    let snapshot_path = report
        .diagnostics_snapshot_path
        .as_ref()
        .expect("snapshot path should be returned");
    assert!(snapshot_path.starts_with(".areamatrix/diagnostics/index-"));
    assert!(repo.path().join(snapshot_path).is_file());
    assert_eq!(report.outcome, RepairMetadataOutcome::Verified);
    assert_eq!(
        get_latest_scan_session(path_string(repo.path())).expect("read latest scan session"),
        None
    );
    assert_eq!(
        list_files(path_string(repo.path()), empty_filter()).expect("list files after repair"),
        Vec::new()
    );

    let reindex = reindex_from_filesystem(path_string(repo.path())).expect("run explicit reindex");
    assert_eq!(reindex.inserted, 1);
    let files = list_files(path_string(repo.path()), empty_filter()).expect("list reindexed files");
    assert_eq!(files.len(), 1);
    assert_eq!(files[0].path, "docs/spec.txt");
    assert_eq!(files[0].origin, FileOrigin::External);
}

#[test]
fn repair_reindex_metadata_implementation_initializes_metadata_without_implicit_rescan() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let readme = repo.path().join("README.md");
    let docs = repo.path().join("docs");
    let spec = docs.join("spec.txt");
    fs::create_dir(&docs).expect("create docs directory");
    fs::write(&readme, "# User project\n").expect("write user README");
    fs::write(&spec, "spec content\n").expect("write user document");
    let before = user_file_snapshot(&[&readme, &spec]);

    let report = repair_metadata(path_string(repo.path()), repair_options(repo.path(), true))
        .expect("initialize missing metadata");

    assert!(repo.path().join(".areamatrix/index.db").is_file());
    assert_eq!(report.diagnostics_snapshot_path, None);
    assert_eq!(report.outcome, RepairMetadataOutcome::Initialized);
    assert_eq!(user_file_snapshot(&[&readme, &spec]), before);
    assert_eq!(
        list_files(path_string(repo.path()), empty_filter())
            .expect("list initialized metadata files")
            .len(),
        0
    );
    assert_eq!(
        get_latest_scan_session(path_string(repo.path())).expect("read latest scan session"),
        None
    );

    let reindex = reindex_from_filesystem(path_string(repo.path())).expect("run explicit reindex");
    assert_eq!(reindex.inserted, 2);
    assert_eq!(user_file_snapshot(&[&readme, &spec]), before);
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
