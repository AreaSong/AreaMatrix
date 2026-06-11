use std::{fs, path::Path};

use area_matrix_core::{
    detect_sync_conflicts, import_file, init_repo, preview_sync_conflict_resolution,
    resolve_sync_conflict, CoreError, ImportDestination, ImportOptions, OverviewOutput,
    RepoInitMode, RepoInitOptions, StorageMode, SyncConflict, SyncConflictResolutionRequest,
    SyncConflictResolutionStrategy, SyncConflictStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

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

fn import_repo_file(repo: &Path, target_directory: &str, filename: &str, bytes: &[u8]) -> i64 {
    let source = tempfile::NamedTempFile::new().expect("create source file");
    fs::write(source.path(), bytes).expect("write source file");
    import_file(
        path_string(repo),
        path_string(source.path()),
        ImportOptions {
            mode: StorageMode::Copied,
            destination: ImportDestination::SelectedDirectory,
            target_directory: Some(target_directory.to_owned()),
            override_category: None,
            override_filename: Some(filename.to_owned()),
            duplicate_strategy: area_matrix_core::DuplicateStrategy::Ask,
        },
    )
    .expect("import repository file")
    .id
}

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) {
    let path = repo.join(relative_path);
    fs::create_dir_all(path.parent().expect("fixture has parent directory"))
        .expect("create fixture parent");
    fs::write(path, bytes).expect("write repository file");
}

fn setup_same_name_conflict() -> (tempfile::TempDir, String, i64) {
    let repo = initialized_repo();
    let file_id = import_repo_file(repo.path(), "docs", "report.pdf", b"original");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted",
    );
    let conflicts = detect_sync_conflicts(path_string(repo.path())).expect("detect conflicts");
    assert_eq!(conflicts.len(), 1);
    (repo, conflicts[0].conflict_id.clone(), file_id)
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

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn conflict_state(repo: &Path) -> Vec<SyncConflict> {
    let value: String = open_db(repo)
        .query_row(
            "SELECT value FROM repo_config WHERE key = 'sync_conflict_state'",
            [],
            |row| row.get(0),
        )
        .expect("read sync conflict state");
    serde_json::from_str(&value).expect("sync conflict state parses")
}

fn change_rows(repo: &Path) -> Vec<(String, serde_json::Value)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT action, detail_json FROM change_log ORDER BY id")
        .expect("prepare change log query");
    statement
        .query_map([], |row| {
            let detail_json: String = row.get(1)?;
            Ok((
                row.get(0)?,
                serde_json::from_str(&detail_json).expect("detail json parses"),
            ))
        })
        .expect("query change log")
        .map(|row| row.expect("read change row"))
        .collect()
}

fn active_file_snapshot(repo: &Path, file_id: i64) -> (String, i64, String) {
    open_db(repo)
        .query_row(
            "SELECT path, size_bytes, hash_sha256
             FROM files
             WHERE id = ?1 AND status = 'active'",
            [file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read active file row")
}

fn active_file_records(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare(
            "SELECT id, path, storage_mode, origin
             FROM files
             WHERE status = 'active'
             ORDER BY path ASC, id ASC",
        )
        .expect("prepare active files query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query active files")
        .map(|row| row.expect("read active file row"))
        .collect()
}

fn preview_token(
    repo: &Path,
    conflict_id: &str,
    strategy: SyncConflictResolutionStrategy,
) -> String {
    preview_sync_conflict_resolution(path_string(repo), conflict_id.to_owned(), strategy)
        .expect("preview sync conflict resolution")
        .preview_token
        .expect("preview token is available")
}

#[test]
fn sync_conflict_resolve_implementation_previews_keep_both_read_only() {
    with_test_system_trash(|_trash_dir| {
        let (repo, conflict_id, _file_id) = setup_same_name_conflict();
        let before_files = user_files(repo.path());
        let before_changes = change_rows(repo.path());

        let preview = preview_sync_conflict_resolution(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionStrategy::KeepBoth,
        )
        .expect("preview keep both");

        assert_eq!(preview.conflict_id, conflict_id);
        assert_eq!(
            preview.default_resolution,
            SyncConflictResolutionStrategy::KeepBoth
        );
        assert_eq!(preview.change_log_action, "conflict_resolved_keep_both");
        assert!(preview.can_apply);
        assert!(!preview.destructive);
        assert!(preview.preview_token.is_some());
        assert_eq!(
            preview.kept_paths,
            vec![
                "docs/report.pdf".to_owned(),
                "docs/report (Alice's conflicted copy).pdf".to_owned(),
            ]
        );
        assert_eq!(
            preview.retained_paths,
            vec!["docs/report (Alice's conflicted copy).pdf".to_owned()]
        );
        assert_eq!(user_files(repo.path()), before_files);
        assert_eq!(change_rows(repo.path()), before_changes);
        assert_eq!(
            conflict_state(repo.path())[0].status,
            SyncConflictStatus::NeedsReview
        );
    });
}

#[test]
fn sync_conflict_resolve_implementation_keep_both_resolves_state_without_moving_versions() {
    with_test_system_trash(|_trash_dir| {
        let (repo, conflict_id, _file_id) = setup_same_name_conflict();
        let before_files = user_files(repo.path());
        let token = preview_token(
            repo.path(),
            &conflict_id,
            SyncConflictResolutionStrategy::KeepBoth,
        );

        let report = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::KeepBoth,
                preview_token: token,
                replace_confirmed: false,
                replace_confirmation_id: None,
            },
        )
        .expect("resolve keep both");

        assert_eq!(report.status, SyncConflictStatus::Resolved);
        assert_eq!(report.change_log_action, "conflict_resolved_keep_both");
        assert!(report.trashed_paths.is_empty());
        assert_eq!(user_files(repo.path()), before_files);
        assert_eq!(
            conflict_state(repo.path())[0].status,
            SyncConflictStatus::Resolved
        );

        let changes = change_rows(repo.path());
        assert_eq!(changes.len(), 2);
        assert_eq!(changes[1].0, "external_modified");
        assert_eq!(changes[1].1["kind"], "sync_conflict_resolved");
        assert_eq!(
            changes[1].1["logical_action"],
            "conflict_resolved_keep_both"
        );
        assert_eq!(changes[1].1["conflict_id"], conflict_id);
    });
}

#[test]
fn sync_conflict_resolve_implementation_use_existing_retains_incoming_visible_record() {
    with_test_system_trash(|_trash_dir| {
        let (repo, conflict_id, file_id) = setup_same_name_conflict();
        let before_files = user_files(repo.path());
        let token = preview_token(
            repo.path(),
            &conflict_id,
            SyncConflictResolutionStrategy::UseExisting,
        );

        let report = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::UseExisting,
                preview_token: token,
                replace_confirmed: false,
                replace_confirmation_id: None,
            },
        )
        .expect("resolve use existing");

        assert_eq!(report.status, SyncConflictStatus::Resolved);
        assert_eq!(report.change_log_action, "conflict_resolved_use_existing");
        assert_eq!(
            report.retained_paths,
            vec!["docs/report (Alice's conflicted copy).pdf".to_owned()]
        );
        assert!(report.trashed_paths.is_empty());
        assert_eq!(user_files(repo.path()), before_files);
        assert_eq!(
            active_file_snapshot(repo.path(), file_id).0,
            "docs/report.pdf"
        );

        let active_records = active_file_records(repo.path());
        let retained = active_records
            .iter()
            .find(|row| row.1 == "docs/report (Alice's conflicted copy).pdf")
            .expect("incoming retained active file row");
        assert_eq!(retained.2, "indexed");
        assert_eq!(retained.3, "external");
        assert_eq!(report.affected_file_ids.len(), 2);
        assert!(report.affected_file_ids.contains(&file_id));
        assert!(report.affected_file_ids.contains(&retained.0));

        let changes = change_rows(repo.path());
        assert_eq!(
            changes[1].1["logical_action"],
            "conflict_resolved_use_existing"
        );
        assert_eq!(changes[1].1["retained_paths"][0], retained.1);
        assert_eq!(
            changes[1].1["affected_file_ids"]
                .as_array()
                .expect("affected ids")
                .len(),
            2
        );
        assert_eq!(
            conflict_state(repo.path())[0].status,
            SyncConflictStatus::Resolved
        );
    });
}

#[test]
fn sync_conflict_resolve_implementation_use_incoming_requires_replace_confirmation() {
    with_test_system_trash(|_trash_dir| {
        let (repo, conflict_id, _file_id) = setup_same_name_conflict();
        let before_files = user_files(repo.path());
        let preview = preview_sync_conflict_resolution(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionStrategy::UseIncoming,
        )
        .expect("preview use incoming");

        assert!(preview.destructive);
        assert!(preview.requires_replace_confirmation);
        assert!(!preview.can_apply);
        assert_eq!(
            preview.blocked_reason.as_deref(),
            Some("replace confirmation is required")
        );
        assert_eq!(preview.planned_trash_paths, vec!["docs/report.pdf"]);
        assert!(preview.replace_plan.is_some());

        let result = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id,
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::UseIncoming,
                preview_token: preview.preview_token.expect("preview token"),
                replace_confirmed: false,
                replace_confirmation_id: None,
            },
        );

        assert!(matches!(result, Err(CoreError::PermissionDenied { .. })));
        assert_eq!(user_files(repo.path()), before_files);
        assert_eq!(
            conflict_state(repo.path())[0].status,
            SyncConflictStatus::NeedsReview
        );
    });
}

#[test]
fn sync_conflict_resolve_implementation_use_incoming_moves_existing_to_trash() {
    with_test_system_trash(|trash_dir| {
        let (repo, conflict_id, file_id) = setup_same_name_conflict();
        let token = preview_token(
            repo.path(),
            &conflict_id,
            SyncConflictResolutionStrategy::UseIncoming,
        );

        let report = resolve_sync_conflict(
            path_string(repo.path()),
            conflict_id.clone(),
            SyncConflictResolutionRequest {
                strategy: SyncConflictResolutionStrategy::UseIncoming,
                preview_token: token,
                replace_confirmed: true,
                replace_confirmation_id: Some("replace-confirmed".to_owned()),
            },
        )
        .expect("resolve use incoming");

        assert_eq!(report.status, SyncConflictStatus::Resolved);
        assert_eq!(report.change_log_action, "conflict_resolved_use_incoming");
        assert_eq!(report.trashed_paths, vec!["docs/report.pdf"]);
        assert_eq!(
            fs::read(repo.path().join("docs/report.pdf")).expect("read canonical file"),
            b"conflicted"
        );
        assert!(!repo
            .path()
            .join("docs/report (Alice's conflicted copy).pdf")
            .exists());
        assert_eq!(
            fs::read(trash_dir.join("report.pdf")).expect("read trashed existing file"),
            b"original"
        );

        let (path, size_bytes, hash_sha256) = active_file_snapshot(repo.path(), file_id);
        assert_eq!(path, "docs/report.pdf");
        assert_eq!(size_bytes, 10);
        assert_ne!(hash_sha256, "");
        assert_eq!(
            conflict_state(repo.path())[0].status,
            SyncConflictStatus::Resolved
        );

        let changes = change_rows(repo.path());
        assert_eq!(changes[1].1["kind"], "sync_conflict_resolved");
        assert_eq!(
            changes[1].1["logical_action"],
            "conflict_resolved_use_incoming"
        );
        assert_eq!(changes[1].1["trashed_paths"][0], "docs/report.pdf");
        assert_eq!(changes[1].1["replace_confirmation_id"], "replace-confirmed");
    });
}
