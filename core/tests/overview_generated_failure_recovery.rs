use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_changes, list_files, load_config, update_config, ChangeFilter,
    CoreError, DuplicateStrategy, FileEntry, FileFilter, ImportDestination, ImportOptions,
    OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn create_empty_options(overview_output: OverviewOutput) -> RepoInitOptions {
    RepoInitOptions {
        mode: RepoInitMode::CreateEmpty,
        create_default_categories: false,
        overview_output,
    }
}

fn initialized_repo(overview_output: OverviewOutput) -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository");
    init_repo(
        path_string(repo.path()),
        create_empty_options(overview_output),
    )
    .expect("initialize repository");
    repo
}

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn copied_options(category: &str) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some(category.to_owned()),
        override_filename: None,
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn change_filter() -> ChangeFilter {
    ChangeFilter {
        file_id: None,
        category: None,
        action: None,
        since: None,
        until: None,
        limit: 100,
        offset: 0,
    }
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn assert_empty_import_state(repo: &Path) {
    assert_eq!(
        list_files(path_string(repo), file_filter()).expect("list files"),
        Vec::<FileEntry>::new()
    );
    assert_eq!(
        list_changes(path_string(repo), change_filter()).expect("list changes"),
        Vec::new()
    );
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

fn assert_overview_failure(result: Result<FileEntry, CoreError>) {
    assert!(
        matches!(
            result,
            Err(CoreError::Io { .. }
                | CoreError::Config { .. }
                | CoreError::PermissionDenied { .. })
        ),
        "expected generated overview failure, got {result:?}"
    );
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected `{needle}` in:\n{haystack}"
    );
}

#[test]
fn overview_generated_failure_recovery_retry_succeeds_after_generated_blocker_is_cleared() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");

    let generated_dir = repo.path().join(".areamatrix/generated");
    fs::remove_dir_all(&generated_dir).expect("remove generated directory for failure setup");
    fs::write(&generated_dir, b"not a directory").expect("block generated directory path");
    let (_source_root, source) = source_file("retry.pdf", b"retry bytes");

    let failed = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("docs"),
    );

    assert_overview_failure(failed);
    assert_eq!(
        fs::read_to_string(&readme_path).expect("read preserved README"),
        "user readme\n"
    );
    assert!(source.exists());
    assert!(!repo.path().join("docs/retry.pdf").exists());
    assert_empty_import_state(repo.path());

    fs::remove_file(&generated_dir).expect("remove generated directory blocker");
    let retried = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("docs"),
    )
    .expect("retry import after clearing generated output blocker");

    assert_eq!(retried.path, "docs/retry.pdf");
    assert!(source.exists());
    assert_eq!(
        list_files(path_string(repo.path()), file_filter())
            .expect("list files after retry")
            .len(),
        1
    );
    assert_eq!(
        list_changes(path_string(repo.path()), change_filter())
            .expect("list changes after retry")
            .len(),
        1
    );
    let generated_root = fs::read_to_string(repo.path().join(".areamatrix/generated/root.md"))
        .expect("read regenerated root overview");
    let generated_node =
        fs::read_to_string(repo.path().join(".areamatrix/generated/nodes/docs.md"))
            .expect("read regenerated node overview");
    assert_contains(&generated_root, "retry.pdf");
    assert_contains(&generated_node, "retry.pdf");
    assert_eq!(staging_entries(repo.path()), Vec::<PathBuf>::new());
}

#[test]
fn overview_generated_failure_recovery_root_entry_conflict_rolls_back_import() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let readme_path = repo.path().join("README.md");
    let root_entry = repo.path().join("AREAMATRIX.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::create_dir(&root_entry).expect("create user-owned root entry blocker");

    let mut config = load_config(path_string(repo.path())).expect("load config");
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    update_config(path_string(repo.path()), config).expect("enable root overview output");
    let (_source_root, source) = source_file("root-blocked.pdf", b"root blocked");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("docs"),
    );

    assert_overview_failure(result);
    assert!(root_entry.is_dir());
    assert_eq!(
        fs::read_to_string(&readme_path).expect("read preserved README"),
        "user readme\n"
    );
    assert!(source.exists());
    assert!(!repo.path().join("docs/root-blocked.pdf").exists());
    assert_empty_import_state(repo.path());
}

#[cfg(unix)]
#[test]
fn overview_generated_failure_recovery_permission_denied_keeps_state_clean() {
    use std::{io, os::unix::fs::PermissionsExt};

    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let nodes_dir = repo.path().join(".areamatrix/generated/nodes");
    fs::create_dir_all(&nodes_dir).expect("create generated nodes directory");
    let original_permissions = fs::metadata(&nodes_dir)
        .expect("read generated nodes permissions")
        .permissions();
    let mut blocked_permissions = original_permissions.clone();
    blocked_permissions.set_mode(0o555);
    fs::set_permissions(&nodes_dir, blocked_permissions)
        .expect("remove generated nodes write permissions");

    let probe = nodes_dir.join("permission-probe.tmp");
    match fs::write(&probe, b"probe") {
        Ok(()) => {
            fs::remove_file(&probe).expect("remove permission probe");
            fs::set_permissions(&nodes_dir, original_permissions)
                .expect("restore generated nodes permissions");
            return;
        }
        Err(error) if error.kind() == io::ErrorKind::PermissionDenied => {}
        Err(_) => {
            fs::set_permissions(&nodes_dir, original_permissions)
                .expect("restore generated nodes permissions");
            return;
        }
    }

    let (_source_root, source) = source_file("permission.pdf", b"permission bytes");
    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("docs"),
    );

    fs::set_permissions(&nodes_dir, original_permissions)
        .expect("restore generated nodes permissions");

    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert!(source.exists());
    assert!(!repo.path().join("docs/permission.pdf").exists());
    assert!(!repo.path().join("docs").exists());
    assert_empty_import_state(repo.path());
}
