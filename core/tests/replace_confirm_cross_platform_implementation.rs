use std::{fs, path::Path};

use area_matrix_core::{
    detect_sync_conflicts, import_file, init_repo, preview_sync_conflict_resolution,
    resolve_sync_conflict, CoreError, DuplicateStrategy, ImportDestination, ImportOptions,
    OverviewOutput, RepoInitMode, RepoInitOptions, StorageMode, SyncConflict,
    SyncConflictResolutionPreviewReport, SyncConflictResolutionRequest,
    SyncConflictResolutionStrategy, SyncConflictResolveReport, SyncConflictStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;
use serde_json::Value;

mod support;

use support::system_trash_home::with_test_system_trash;

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

fn source_file(name: &str, bytes: &[u8]) -> tempfile::TempDir {
    let source = tempfile::tempdir().expect("create source directory");
    fs::write(source.path().join(name), bytes).expect("write source file");
    source
}

fn import_options(filename: &str, strategy: DuplicateStrategy) -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("docs".to_owned()),
        override_category: None,
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: strategy,
    }
}

fn import_named_file(
    repo: &Path,
    filename: &str,
    bytes: &[u8],
    strategy: DuplicateStrategy,
) -> area_matrix_core::FileEntry {
    let source = source_file(filename, bytes);
    import_file(
        path_string(repo),
        path_string(&source.path().join(filename)),
        import_options(filename, strategy),
    )
    .expect("import file")
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_row(repo: &Path, file_id: i64) -> (String, String, Option<i64>) {
    open_db(repo)
        .query_row(
            "SELECT path, status, deleted_at FROM files WHERE id = ?1",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read file row")
}

fn change_detail(repo: &Path, file_id: i64, action: &str) -> Value {
    let detail_json: String = open_db(repo)
        .query_row(
            "SELECT detail_json FROM change_log
             WHERE file_id = ?1 AND action = ?2
             ORDER BY id DESC LIMIT 1",
            rusqlite::params![file_id, action],
            |row| row.get(0),
        )
        .expect("read change detail");
    serde_json::from_str(&detail_json).expect("parse change detail")
}

fn conflict_state(repo: &Path) -> Vec<SyncConflict> {
    let value: String = open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = 'sync_conflict_state'",
            [],
            |row| row.get(0),
        )
        .expect("read sync conflict state");
    serde_json::from_str(&value).expect("parse sync conflict state")
}

fn change_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change log rows")
}

fn user_files(repo: &Path) -> Vec<(String, Vec<u8>)> {
    let mut files = Vec::new();
    collect_user_files(repo, repo, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    files
}

fn collect_user_files(repo: &Path, current: &Path, files: &mut Vec<(String, Vec<u8>)>) {
    for entry in fs::read_dir(current).expect("read repository directory") {
        let entry = entry.expect("read repository entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(repo)
            .expect("entry is inside repo")
            .to_string_lossy()
            .replace('\\', "/");
        if relative.starts_with(".areamatrix") {
            continue;
        }
        if path.is_dir() {
            collect_user_files(repo, &path, files);
        } else {
            files.push((relative, fs::read(&path).expect("read user file")));
        }
    }
}

fn setup_sync_replace_conflict() -> (tempfile::TempDir, String, i64) {
    let repo = initialized_repo();
    let existing = import_named_file(
        repo.path(),
        "report.pdf",
        b"existing-version",
        DuplicateStrategy::Ask,
    );
    let conflict_path = repo
        .path()
        .join("docs/report (incoming conflicted copy).pdf");
    fs::write(&conflict_path, b"incoming-version").expect("write incoming conflict copy");
    let conflicts = detect_sync_conflicts(path_string(repo.path())).expect("detect conflicts");
    assert_eq!(conflicts.len(), 1);
    (repo, conflicts[0].conflict_id.clone(), existing.id)
}

fn assert_import_replace_results(
    repo: &Path,
    trash_dir: &Path,
    existing_id: i64,
    replacement_id: i64,
) {
    assert_eq!(
        fs::read(repo.join("docs/report.pdf")).expect("read replacement file"),
        b"confirmed-version"
    );
    assert_eq!(
        fs::read(repo.join("docs/report_1.pdf")).expect("read kept-both file"),
        b"unconfirmed-version"
    );
    assert_eq!(
        fs::read(trash_dir.join("report.pdf")).expect("read trashed existing file"),
        b"existing-version"
    );

    let existing_row = file_row(repo, existing_id);
    assert!(existing_row.0.starts_with("system-trash://replace-"));
    assert_eq!(existing_row.1, "deleted");
    assert!(existing_row.2.is_some());
    assert_eq!(file_row(repo, replacement_id).1, "active");

    let deleted_detail = change_detail(repo, existing_id, "deleted");
    assert_eq!(deleted_detail["safe_replace"], true);
    assert_eq!(deleted_detail["trashed"], true);
    assert_eq!(deleted_detail["reason"], "name_conflict_replace");

    let imported_detail = change_detail(repo, replacement_id, "imported");
    assert_eq!(imported_detail["duplicate_strategy"], "overwrite");
    assert_eq!(imported_detail["replaced_file_id"], existing_id);
    assert_eq!(imported_detail["replaced_path"], "docs/report.pdf");
}

fn assert_sync_replace_preview_requires_confirmation(
    preview: &SyncConflictResolutionPreviewReport,
) {
    assert!(preview.requires_replace_confirmation);
    assert!(!preview.can_apply);
    assert_eq!(
        preview.blocked_reason.as_deref(),
        Some("replace confirmation is required")
    );
    assert_eq!(preview.planned_trash_paths, vec!["docs/report.pdf"]);
    assert_eq!(
        preview
            .replace_plan
            .as_ref()
            .expect("replace plan")
            .backup_target
            .as_deref(),
        Some("Trash")
    );
}

fn assert_unconfirmed_sync_replace_unchanged(
    repo: &Path,
    files_before: &[(String, Vec<u8>)],
    change_count_before: i64,
) {
    assert_eq!(user_files(repo), files_before);
    assert_eq!(change_count(repo), change_count_before);
    assert_eq!(
        conflict_state(repo)[0].status,
        SyncConflictStatus::NeedsReview
    );
}

fn assert_confirmed_sync_replace_results(
    repo: &Path,
    trash_dir: &Path,
    file_id: i64,
    report: &SyncConflictResolveReport,
) {
    assert_eq!(report.status, SyncConflictStatus::Resolved);
    assert_eq!(report.trashed_paths, vec!["docs/report.pdf"]);
    assert!(report.affected_file_ids.contains(&file_id));
    assert_eq!(
        fs::read(repo.join("docs/report.pdf")).expect("read canonical replacement"),
        b"incoming-version"
    );
    assert!(!repo
        .join("docs/report (incoming conflicted copy).pdf")
        .exists());
    assert_eq!(
        fs::read(trash_dir.join("report.pdf")).expect("read trashed canonical file"),
        b"existing-version"
    );
    assert_eq!(conflict_state(repo)[0].status, SyncConflictStatus::Resolved);
}

#[test]
fn replace_confirm_cross_platform_implementation_import_overwrite_is_recoverable() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let existing = import_named_file(
            repo.path(),
            "report.pdf",
            b"existing-version",
            DuplicateStrategy::Skip,
        );

        let kept_both = import_named_file(
            repo.path(),
            "report.pdf",
            b"unconfirmed-version",
            DuplicateStrategy::Skip,
        );
        assert_eq!(kept_both.path, "docs/report_1.pdf");
        assert_eq!(
            fs::read(repo.path().join("docs/report.pdf")).expect("read existing file"),
            b"existing-version"
        );

        let replacement = import_named_file(
            repo.path(),
            "report.pdf",
            b"confirmed-version",
            DuplicateStrategy::Overwrite,
        );

        assert_eq!(replacement.path, "docs/report.pdf");
        assert_import_replace_results(repo.path(), trash_dir, existing.id, replacement.id);
    });
}

#[test]
fn replace_confirm_cross_platform_implementation_sync_use_incoming_requires_confirmation() {
    with_test_system_trash(|trash_dir| {
        let (repo, conflict_id, file_id) = setup_sync_replace_conflict();
        let before_files = user_files(repo.path());
        let before_changes = change_count(repo.path());

        let preview = preview_sync_conflict_resolution(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionStrategy::UseIncoming,
        )
        .expect("preview use incoming");
        assert_sync_replace_preview_requires_confirmation(&preview);

        let token = preview.preview_token.clone().expect("preview token");
        let unconfirmed = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::UseIncoming,
                preview_token: token.clone(),
                replace_confirmed: false,
                replace_confirmation_id: None,
            },
        );
        assert!(matches!(
            unconfirmed,
            Err(CoreError::PermissionDenied { .. })
        ));
        assert_unconfirmed_sync_replace_unchanged(repo.path(), &before_files, before_changes);

        let report = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::UseIncoming,
                preview_token: token,
                replace_confirmed: true,
                replace_confirmation_id: Some("replace-confirm:s4-x-09".to_owned()),
            },
        )
        .expect("resolve confirmed use incoming");
        assert_confirmed_sync_replace_results(repo.path(), trash_dir, file_id, &report);
    });
}
