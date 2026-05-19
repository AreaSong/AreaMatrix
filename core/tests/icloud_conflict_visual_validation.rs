use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_icloud_conflicts, list_undo_actions, preview_conflict_versions,
    resolve_icloud_conflict, CoreError, CoreResult, ICloudConflictPreviewReport,
    ICloudConflictResolution, ICloudConflictResolveReport, ICloudConflictStatus,
    ICloudConflictVersionRole, OverviewOutput, RepoInitMode, RepoInitOptions, UndoActionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

mod support;

use support::system_trash_home::with_test_system_trash;

const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-2-experience/C2-16-icloud-conflict-visual.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const ICLOUD_CONFLICTS_RS: &str = include_str!("../src/icloud_conflicts.rs");
const UDL: &str = include_str!("../area_matrix.udl");
const CONFLICT_ID: &str = "docs/report (Alice's conflicted copy).pdf";
const C2_16_CONTROL_MAP_ROW: &str = concat!(
    "| S2-20 | icloud-conflict-visual | C2-16, C1-25 | ",
    "conflict preview/resolve | conflict state, Trash",
);

#[derive(Debug, Eq, PartialEq)]
struct ConflictValidationSnapshot {
    tree: BTreeMap<PathBuf, Option<Vec<u8>>>,
    conflict_change_count: i64,
    undo_action_count: i64,
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository");
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
    fs::create_dir_all(path.parent().expect("fixture path has parent"))
        .expect("create fixture parent");
    fs::write(&path, bytes).expect("write fixture file");
    path
}

fn seed_complete_conflict(repo: &Path) -> (PathBuf, PathBuf) {
    let original = write_repo_file(repo, "docs/report.pdf", b"original");
    let conflicted = write_repo_file(repo, CONFLICT_ID, b"conflicted");
    (original, conflicted)
}

fn snapshot(repo: &Path) -> ConflictValidationSnapshot {
    ConflictValidationSnapshot {
        tree: snapshot_tree(repo),
        conflict_change_count: conflict_resolution_change_count(repo),
        undo_action_count: undo_action_count(repo),
    }
}

fn snapshot_tree(root: &Path) -> BTreeMap<PathBuf, Option<Vec<u8>>> {
    let mut snapshot = BTreeMap::new();
    collect_snapshot(root, root, &mut snapshot);
    snapshot
}

fn collect_snapshot(
    root: &Path,
    current: &Path,
    snapshot: &mut BTreeMap<PathBuf, Option<Vec<u8>>>,
) {
    for entry in fs::read_dir(current).expect("read snapshot directory") {
        let entry = entry.expect("read snapshot entry");
        let path = entry.path();
        let relative = path
            .strip_prefix(root)
            .expect("snapshot path stays in repo")
            .to_path_buf();
        let file_type = entry.file_type().expect("read snapshot file type");
        if file_type.is_dir() {
            snapshot.insert(relative, None);
            collect_snapshot(root, &path, snapshot);
        } else if file_type.is_file() {
            snapshot.insert(relative, Some(fs::read(&path).expect("read snapshot file")));
        }
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn conflict_resolution_change_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*)
             FROM change_log
             WHERE action = 'external_modified'
               AND json_extract(detail_json, '$.kind') = 'icloud_conflict_resolved'",
            [],
            |row| row.get(0),
        )
        .expect("count iCloud conflict resolution changes")
}

fn undo_action_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM undo_actions", [], |row| row.get(0))
        .expect("count undo actions")
}

fn install_resolution_log_failure(repo: &Path) {
    open_db(repo)
        .execute_batch(
            "CREATE TRIGGER fail_icloud_resolution_validation_log
             BEFORE INSERT ON change_log
             WHEN NEW.action = 'external_modified'
              AND json_extract(NEW.detail_json, '$.kind') = 'icloud_conflict_resolved'
             BEGIN
               SELECT RAISE(ABORT, 'forced icloud validation log failure');
             END;",
        )
        .expect("install forced iCloud resolution failure");
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_capability_and_control_docs_alignment() {
    for fragment in [
        "# C2-16 icloud-conflict-visual",
        "版本 metadata、预览摘要、解决报告。",
        "冲突解决失败时保持 unresolved。",
        "不自动删除任一版本。",
        "预览失败不能继续 destructive resolution。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
    assert_contains(CONTROL_MAP, C2_16_CONTROL_MAP_ROW);
    assert_contains(TESTING_DOC, "集成测试");
}

fn assert_core_api_and_udl_alignment() {
    for fragment in [
        "ICloudConflictPreviewReport preview_conflict_versions(",
        "ICloudConflictResolveReport resolve_icloud_conflict(",
        "dictionary ICloudConflictVersionMetadata",
        "dictionary ICloudConflictPreviewReport",
        "dictionary ICloudConflictResolveReport",
        "enum ICloudConflictResolution { \"KeepBoth\", \"KeepOriginal\", \"KeepConflictedCopy\" };",
        "ICloudPlaceholder",
        "PermissionDenied",
        "Conflict",
        "Io",
        "Db",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }
}

fn assert_rust_contract_alignment() {
    for fragment in [
        "pub fn preview_conflict_versions(",
        "pub fn resolve_icloud_conflict(",
        "C2-16 iCloud conflict versions",
        "On any failure the conflict must remain unresolved",
    ] {
        assert_contains(API_RS, fragment);
    }
    for fragment in [
        "pub struct ICloudConflictPreviewReport",
        "pub struct ICloudConflictResolveReport",
        "pub enum ICloudConflictResolution",
        "Default safe choice; must remain KeepBoth.",
        "Versions moved to Trash; empty for KeepBoth.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }
    for fragment in [
        "preview_conflict_versions",
        "resolve_icloud_conflict",
        "ensure_resolution_enabled",
        "resolve_destructive",
    ] {
        assert_contains(ICLOUD_CONFLICTS_RS, fragment);
    }
}

#[test]
fn icloud_conflict_visual_validation_preview_is_ui_ready_and_read_only() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        seed_complete_conflict(repo.path());
        let before = snapshot(repo.path());

        let preview = preview_conflict_versions(path_string(repo.path()), CONFLICT_ID.to_owned())
            .expect("preview iCloud conflict");

        assert_eq!(
            preview.default_resolution,
            ICloudConflictResolution::KeepBoth
        );
        assert!(preview.metadata_complete);
        assert!(preview.can_keep_both);
        assert!(preview.can_resolve_destructive);
        assert_eq!(preview.blocked_reason, None);
        assert_eq!(preview.versions.len(), 2);
        assert_eq!(snapshot(repo.path()), before);
        assert!(trash_dir.exists());
    });
}

#[test]
fn icloud_conflict_visual_validation_keep_both_marks_resolved_without_moving_versions() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        let (original, conflicted) = seed_complete_conflict(repo.path());

        let report = resolve_icloud_conflict(
            path_string(repo.path()),
            CONFLICT_ID.to_owned(),
            ICloudConflictResolution::KeepBoth,
        )
        .expect("resolve keep both");

        assert_eq!(report.status, ICloudConflictStatus::Resolved);
        assert_eq!(report.trashed_paths, Vec::<String>::new());
        assert_eq!(
            fs::read(&original).expect("read kept original"),
            b"original"
        );
        assert_eq!(
            fs::read(&conflicted).expect("read kept conflicted copy"),
            b"conflicted"
        );
        let conflicts = list_icloud_conflicts(path_string(repo.path())).expect("list conflicts");
        assert_eq!(conflicts[0].status, ICloudConflictStatus::Resolved);
        assert_eq!(conflict_resolution_change_count(repo.path()), 1);
    });
}

#[test]
fn icloud_conflict_visual_validation_destructive_resolution_uses_trash_and_blocked_undo() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (original, conflicted) = seed_complete_conflict(repo.path());
        let report = resolve_icloud_conflict(
            path_string(repo.path()),
            CONFLICT_ID.to_owned(),
            ICloudConflictResolution::KeepOriginal,
        )
        .expect("resolve destructive keep original");

        assert_eq!(report.status, ICloudConflictStatus::Resolved);
        assert_eq!(report.kept_paths, vec!["docs/report.pdf".to_owned()]);
        assert_eq!(report.trashed_paths, vec![CONFLICT_ID.to_owned()]);
        assert_eq!(fs::read(&original).expect("read original"), b"original");
        assert!(!conflicted.exists());
        assert_eq!(
            fs::read(trash_dir.join("report (Alice's conflicted copy).pdf"))
                .expect("read trashed conflicted copy"),
            b"conflicted"
        );
        let undo_actions = list_undo_actions(path_string(repo.path())).expect("list undo actions");
        assert_eq!(undo_actions.len(), 1);
        assert_eq!(undo_actions[0].status, UndoActionStatus::Blocked);
        assert!(!undo_actions[0].can_undo);
        let conflicts = list_icloud_conflicts(path_string(repo.path())).expect("list conflicts");
        assert!(conflicts.is_empty());
        assert_eq!(conflict_resolution_change_count(repo.path()), 1);
    });
}

#[test]
fn icloud_conflict_visual_validation_preview_contains_both_version_metadata() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        seed_complete_conflict(repo.path());

        let preview = preview_conflict_versions(path_string(repo.path()), CONFLICT_ID.to_owned())
            .expect("preview iCloud conflict");

        assert!(preview.versions.iter().any(|version| {
            version.role == ICloudConflictVersionRole::Original
                && version.path == "docs/report.pdf"
                && version.hash_sha256.is_some()
                && version.preview_summary.is_some()
        }));
        assert!(preview.versions.iter().any(|version| {
            version.role == ICloudConflictVersionRole::ConflictedCopy
                && version.path == "docs/report (Alice's conflicted copy).pdf"
                && version.hash_sha256.is_some()
                && version.preview_summary.is_some()
        }));
    });
}

#[test]
fn icloud_conflict_visual_validation_db_failure_rolls_back_and_stays_unresolved() {
    with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let (original, conflicted) = seed_complete_conflict(repo.path());
        install_resolution_log_failure(repo.path());
        let before = snapshot(repo.path());

        let result = resolve_icloud_conflict(
            path_string(repo.path()),
            CONFLICT_ID.to_owned(),
            ICloudConflictResolution::KeepOriginal,
        );

        assert!(matches!(result, Err(CoreError::Db { .. })));
        assert_eq!(snapshot(repo.path()), before);
        assert_eq!(fs::read(original).expect("read original"), b"original");
        assert_eq!(
            fs::read(conflicted).expect("read conflicted copy"),
            b"conflicted"
        );
        assert!(!trash_dir
            .join("report (Alice's conflicted copy).pdf")
            .exists());
        let conflicts = list_icloud_conflicts(path_string(repo.path())).expect("list conflicts");
        assert_eq!(conflicts[0].status, ICloudConflictStatus::NeedsReview);
    });
}

#[test]
fn icloud_conflict_visual_validation_incomplete_metadata_blocks_destructive_resolution() {
    with_test_system_trash(|_trash_dir| {
        let repo = initialized_repo();
        write_repo_file(repo.path(), CONFLICT_ID, b"conflicted without original");
        let before = snapshot(repo.path());

        let preview = preview_conflict_versions(path_string(repo.path()), CONFLICT_ID.to_owned())
            .expect("preview incomplete conflict");
        let result = resolve_icloud_conflict(
            path_string(repo.path()),
            CONFLICT_ID.to_owned(),
            ICloudConflictResolution::KeepConflictedCopy,
        );

        assert!(!preview.metadata_complete);
        assert!(preview.can_keep_both);
        assert!(!preview.can_resolve_destructive);
        assert!(matches!(result, Err(CoreError::Conflict { .. })));
        assert_eq!(snapshot(repo.path()), before);
    });
}

#[test]
fn icloud_conflict_visual_validation_core_api_udl_and_rust_stay_aligned() {
    fn assert_preview_signature(_: fn(String, String) -> CoreResult<ICloudConflictPreviewReport>) {}
    fn assert_resolve_signature(
        _: fn(String, String, ICloudConflictResolution) -> CoreResult<ICloudConflictResolveReport>,
    ) {
    }
    assert_preview_signature(preview_conflict_versions);
    assert_resolve_signature(resolve_icloud_conflict);

    assert_capability_and_control_docs_alignment();
    assert_core_api_and_udl_alignment();
    assert_rust_contract_alignment();
}
