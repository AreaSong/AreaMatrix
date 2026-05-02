use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, list_changes, list_files, load_config, rename_file,
    sync_external_changes, update_config, ChangeFilter, CoreError, DuplicateStrategy,
    ExternalEvent, ExternalEventKind, FileEntry, FileFilter, ImportDestination, ImportOptions,
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

fn empty_file_filter() -> FileFilter {
    FileFilter {
        category: None,
        include_deleted: None,
        imported_after: None,
        imported_before: None,
        limit: 100,
        offset: 0,
    }
}

fn empty_change_filter() -> ChangeFilter {
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

fn import_doc(repo: &Path, name: &str, content: &[u8]) -> FileEntry {
    let (_source_root, source) = source_file(name, content);
    import_file(
        path_string(repo),
        path_string(&source),
        copied_options("docs"),
    )
    .expect("import file and regenerate overview")
}

fn renamed_event(relative_path: &str, fs_event_id: i64) -> ExternalEvent {
    ExternalEvent {
        path: relative_path.to_owned(),
        kind: ExternalEventKind::Renamed,
        fs_event_id,
    }
}

fn read_file(path: &Path) -> String {
    fs::read_to_string(path).expect("read file")
}

fn staging_entries(repo: &Path) -> Vec<PathBuf> {
    fs::read_dir(repo.join(".areamatrix/staging"))
        .expect("read staging directory")
        .map(|entry| entry.expect("read staging entry").path())
        .collect()
}

fn assert_no_failed_import_state(repo: &Path) {
    assert_eq!(
        list_files(path_string(repo), empty_file_filter()).expect("list files after failure"),
        Vec::<FileEntry>::new()
    );
    assert_eq!(
        list_changes(path_string(repo), empty_change_filter()).expect("list changes after failure"),
        Vec::new()
    );
    assert_eq!(staging_entries(repo), Vec::<PathBuf>::new());
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected `{needle}` in:\n{haystack}"
    );
}

fn assert_not_contains(haystack: &str, needle: &str) {
    assert!(
        !haystack.contains(needle),
        "did not expect `{needle}` in:\n{haystack}"
    );
}

#[test]
fn overview_generated_implementation_import_updates_generated_root_and_node_only() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let readme_path = repo.path().join("README.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");

    import_doc(repo.path(), "report.pdf", b"report bytes");

    let generated_root = read_file(&repo.path().join(".areamatrix/generated/root.md"));
    let generated_node = read_file(&repo.path().join(".areamatrix/generated/nodes/docs.md"));
    assert_contains(&generated_root, "AREAMATRIX:BEGIN");
    assert_contains(&generated_root, "docs");
    assert_contains(&generated_root, "1 个文件");
    assert_contains(&generated_node, "report.pdf");
    assert_contains(&generated_node, "12 B");
    assert_eq!(read_file(&readme_path), "user readme\n");
    assert!(!repo.path().join("AREAMATRIX.md").exists());
}

#[test]
fn overview_generated_implementation_root_file_preserves_user_content_when_enabled() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let readme_path = repo.path().join("README.md");
    let root_entry = repo.path().join("AREAMATRIX.md");
    fs::write(&readme_path, "user readme\n").expect("write user README");
    fs::write(&root_entry, "# User overview\n\nmanual notes\n").expect("write user overview");

    let mut config = load_config(path_string(repo.path())).expect("load config");
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    update_config(path_string(repo.path()), config).expect("enable root overview output");
    import_doc(repo.path(), "manual.pdf", b"manual bytes");

    let root_content = read_file(&root_entry);
    assert_contains(&root_content, "# User overview");
    assert_contains(&root_content, "manual notes");
    assert_contains(&root_content, "AREAMATRIX:BEGIN");
    assert_contains(&root_content, "manual.pdf");
    assert_eq!(read_file(&readme_path), "user readme\n");
}

#[test]
fn overview_generated_implementation_root_file_replaces_only_marker_block() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let root_entry = repo.path().join("AREAMATRIX.md");
    fs::write(
        &root_entry,
        "# User overview\n\n<!-- AREAMATRIX:BEGIN old -->\nold managed\n<!-- AREAMATRIX:END -->\n\nmanual tail\n",
    )
    .expect("write existing marked overview");

    let mut config = load_config(path_string(repo.path())).expect("load config");
    config.overview_output = OverviewOutput::RootAreaMatrixFile;
    update_config(path_string(repo.path()), config).expect("enable root overview output");
    import_doc(repo.path(), "contract.pdf", b"contract bytes");

    let root_content = read_file(&root_entry);
    assert_contains(&root_content, "# User overview");
    assert_contains(&root_content, "manual tail");
    assert_contains(&root_content, "contract.pdf");
    assert_not_contains(&root_content, "old managed");
}

#[test]
fn overview_generated_implementation_generated_only_stops_root_file_updates() {
    let repo = initialized_repo(OverviewOutput::RootAreaMatrixFile);
    let root_entry = repo.path().join("AREAMATRIX.md");
    let original_root_entry = read_file(&root_entry);

    let mut config = load_config(path_string(repo.path())).expect("load config");
    config.overview_output = OverviewOutput::GeneratedOnly;
    update_config(path_string(repo.path()), config).expect("disable root overview output");
    import_doc(repo.path(), "notes.pdf", b"notes bytes");

    assert_eq!(read_file(&root_entry), original_root_entry);
    let generated_root = read_file(&repo.path().join(".areamatrix/generated/root.md"));
    assert_contains(&generated_root, "notes.pdf");
}

#[test]
fn overview_generated_implementation_import_rolls_back_copy_when_regeneration_fails() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let generated_dir = repo.path().join(".areamatrix/generated");
    fs::remove_dir_all(&generated_dir).expect("remove generated directory for failure setup");
    fs::write(&generated_dir, b"not a directory").expect("block generated directory path");
    let (_source_root, source) = source_file("blocked.pdf", b"blocked bytes");

    let result = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options("docs"),
    );

    assert!(
        matches!(
            result,
            Err(CoreError::Io | CoreError::Config | CoreError::PermissionDenied)
        ),
        "expected overview regeneration error, got {result:?}"
    );
    assert!(source.exists());
    assert!(!repo.path().join("docs/blocked.pdf").exists());
    assert!(!repo.path().join("docs").exists());
    assert_no_failed_import_state(repo.path());
}

#[test]
fn overview_generated_implementation_import_restores_moved_source_when_regeneration_fails() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let generated_dir = repo.path().join(".areamatrix/generated");
    fs::remove_dir_all(&generated_dir).expect("remove generated directory for failure setup");
    fs::write(&generated_dir, b"not a directory").expect("block generated directory path");
    let (_source_root, source) = source_file("moved.pdf", b"moved bytes");
    let mut options = copied_options("docs");
    options.mode = StorageMode::Moved;

    let result = import_file(path_string(repo.path()), path_string(&source), options);

    assert!(
        matches!(
            result,
            Err(CoreError::Io | CoreError::Config | CoreError::PermissionDenied)
        ),
        "expected overview regeneration error, got {result:?}"
    );
    assert_eq!(
        fs::read(&source).expect("read restored source"),
        b"moved bytes"
    );
    assert!(!repo.path().join("docs/moved.pdf").exists());
    assert_no_failed_import_state(repo.path());
}

#[test]
fn overview_generated_implementation_import_removes_indexed_row_when_regeneration_fails() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let generated_dir = repo.path().join(".areamatrix/generated");
    fs::remove_dir_all(&generated_dir).expect("remove generated directory for failure setup");
    fs::write(&generated_dir, b"not a directory").expect("block generated directory path");
    let (_source_root, source) = source_file("indexed.pdf", b"indexed bytes");
    let mut options = copied_options("docs");
    options.mode = StorageMode::Indexed;

    let result = import_file(path_string(repo.path()), path_string(&source), options);

    assert!(
        matches!(
            result,
            Err(CoreError::Io | CoreError::Config | CoreError::PermissionDenied)
        ),
        "expected overview regeneration error, got {result:?}"
    );
    assert_eq!(
        fs::read(&source).expect("read indexed source"),
        b"indexed bytes"
    );
    assert!(!repo.path().join("docs/indexed.pdf").exists());
    assert_no_failed_import_state(repo.path());
}

#[test]
fn overview_generated_implementation_import_restores_replaced_file_when_regeneration_fails() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let original = import_doc(repo.path(), "replace.pdf", b"old bytes");
    let original_path = repo.path().join(&original.path);
    let original_changes =
        list_changes(path_string(repo.path()), empty_change_filter()).expect("list changes");
    assert_eq!(original_changes.len(), 1);

    let generated_dir = repo.path().join(".areamatrix/generated");
    fs::remove_dir_all(&generated_dir).expect("remove generated directory for failure setup");
    fs::write(&generated_dir, b"not a directory").expect("block generated directory path");
    let (_source_root, source) = source_file("replacement.pdf", b"new bytes");
    let mut options = copied_options("docs");
    options.override_filename = Some("replace.pdf".to_owned());
    options.duplicate_strategy = DuplicateStrategy::Overwrite;

    let result = import_file(path_string(repo.path()), path_string(&source), options);

    assert!(
        matches!(
            result,
            Err(CoreError::Io | CoreError::Config | CoreError::PermissionDenied)
        ),
        "expected overview regeneration error, got {result:?}"
    );
    assert_eq!(
        fs::read(&original_path).expect("read restored file"),
        b"old bytes"
    );
    assert_eq!(fs::read(&source).expect("read copied source"), b"new bytes");
    let files = list_files(path_string(repo.path()), empty_file_filter()).expect("list files");
    assert_eq!(files, vec![original]);
    let changes =
        list_changes(path_string(repo.path()), empty_change_filter()).expect("list changes");
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].action, "imported");
}

#[test]
fn overview_generated_implementation_rename_updates_generated_node_and_root() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    let entry = import_doc(repo.path(), "draft.pdf", b"draft bytes");

    rename_file(path_string(repo.path()), entry.id, "final.pdf".to_owned())
        .expect("rename file and regenerate overview");

    let generated_root = read_file(&repo.path().join(".areamatrix/generated/root.md"));
    let generated_node = read_file(&repo.path().join(".areamatrix/generated/nodes/docs.md"));
    assert_contains(&generated_root, "final.pdf");
    assert_contains(&generated_node, "final.pdf");
    assert_not_contains(&generated_node, "draft.pdf");
}

#[test]
fn overview_generated_implementation_sync_external_rename_updates_generated_overview() {
    let repo = initialized_repo(OverviewOutput::GeneratedOnly);
    import_doc(repo.path(), "external-original.pdf", b"sync rename bytes");
    fs::rename(
        repo.path().join("docs/external-original.pdf"),
        repo.path().join("docs/external-renamed.pdf"),
    )
    .expect("simulate external rename");

    sync_external_changes(
        path_string(repo.path()),
        vec![renamed_event("docs/external-renamed.pdf", 7)],
    )
    .expect("sync external rename and regenerate overview");

    let generated_node = read_file(&repo.path().join(".areamatrix/generated/nodes/docs.md"));
    assert_contains(&generated_node, "external-renamed.pdf");
    assert_not_contains(&generated_node, "external-original.pdf");
}
