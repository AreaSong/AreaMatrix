use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    batch_add_tags, delete_file, import_file, init_repo, list_undo_actions, move_to_category,
    rename_file, undo_action, CoreError, CoreResult, DuplicateStrategy, ErrorKind,
    ErrorRecoverability, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode, UndoActionRecord, UndoActionResult, UndoActionStatus,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde_json::Value;

mod support;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-2-experience/C2-07-undo-action-log.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-2-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const UNDO_RS: &str = include_str!("../src/undo.rs");
const DB_UNDO_RS: &str = include_str!("../src/db/undo.rs");
const FILE_ACTIONS_RS: &str = include_str!("../src/db/undo/file_actions.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");

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

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn import_options(mode: StorageMode, category: &str, filename: &str) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some(category.to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn file_rows(repo: &Path) -> Vec<(i64, String, String, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT id, path, category, status FROM files ORDER BY id")
        .expect("prepare file row query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("query file rows")
        .map(|row| row.expect("read file row"))
        .collect()
}

fn tag_rows(repo: &Path) -> Vec<(i64, String)> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT file_id, tag FROM tags ORDER BY file_id, tag")
        .expect("prepare tag row query");
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("query tag rows")
        .map(|row| row.expect("read tag row"))
        .collect()
}

fn undo_status(repo: &Path, action_id: &str) -> String {
    open_db(repo)
        .query_row(
            "SELECT status FROM undo_actions WHERE token = ?1",
            params![action_id],
            |row| row.get(0),
        )
        .expect("read undo action status")
}

fn only_undo_token(repo: &Path, kind: &str) -> String {
    open_db(repo)
        .query_row(
            "SELECT token FROM undo_actions WHERE kind = ?1 ORDER BY created_at DESC, token DESC",
            params![kind],
            |row| row.get(0),
        )
        .expect("read undo token")
}

fn undo_inverse(repo: &Path, token: &str) -> Value {
    let inverse_json: String = open_db(repo)
        .query_row(
            "SELECT inverse_json FROM undo_actions WHERE token = ?1",
            params![token],
            |row| row.get(0),
        )
        .expect("read undo inverse");
    serde_json::from_str(&inverse_json).expect("parse undo inverse")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_all_contains(haystack: &str, needles: &[&str]) {
    for needle in needles {
        assert_contains(haystack, needle);
    }
}

fn assert_error_mapping(error: &CoreError, kind: ErrorKind, recoverability: ErrorRecoverability) {
    let mapping = error.to_error_mapping();
    assert_eq!(mapping.kind, kind);
    assert_eq!(mapping.recoverability, recoverability);
}

fn assert_undo_signatures() {
    fn assert_list_signature(_: fn(String) -> CoreResult<Vec<UndoActionRecord>>) {}
    fn assert_undo_signature(_: fn(String, String) -> CoreResult<UndoActionResult>) {}
    assert_list_signature(list_undo_actions);
    assert_undo_signature(undo_action);
}

fn assert_capability_and_control_map_alignment() {
    assert_all_contains(
        CAPABILITY_SPEC,
        &[
            "# C2-07 undo-action-log",
            "`list_undo_actions`",
            "`undo_action(repo_path, action_id)`",
            "Undo 执行结果和刷新建议。",
            "外部变化不可撤销时必须明确显示。",
            "Undo 失败不破坏当前状态。",
        ],
    );

    assert_all_contains(
        CONTROL_MAP,
        &[
            "| S2-10 | undo-toast | C2-07 | undo action | undo_actions",
            "| S2-11 | undo-history | C2-07 | list/execute undo | undo_actions",
            "| S2-09 | batch-add-tags | C2-06, C2-07 | batch tag mutation | tags, undo_actions",
            "| S2-12 | batch-change-category | C2-08, C2-07 | preview + batch move",
            "| S2-13 | batch-delete-confirm | C2-09, C2-07 | preview + Trash delete",
            "| S2-14 | batch-rename | C2-10, C2-07 | preview + rename",
            "批量操作必须有 preview、确认、执行报告和 undo/action log。",
        ],
    );
}

fn assert_api_and_udl_alignment() {
    for fragment in &[
        "sequence<UndoActionRecord> list_undo_actions(string repo_path);",
        "UndoActionResult undo_action(string repo_path, string action_id);",
        "dictionary UndoActionRecord",
        "string action_id;",
        "string kind;",
        "i64 affected_count;",
        "sequence<string> affected_file_names;",
        "UndoActionStatus status;",
        "boolean can_undo;",
        "string? disabled_reason;",
        "dictionary UndoActionResult",
        "sequence<string> refresh_targets;",
        "enum UndoActionStatus { \"Pending\", \"Executed\", \"Expired\", \"Blocked\" };",
    ] {
        assert_contains(CORE_API, *fragment);
        assert_contains(UDL, *fragment);
    }
}

fn assert_rust_export_and_boundary_alignment() {
    assert_all_contains(
        LIB_RS,
        &[
            "pub use undo::{",
            "list_undo_actions",
            "undo_action",
            "UndoActionRecord",
            "UndoActionResult",
            "UndoActionStatus",
        ],
    );

    assert_all_contains(
        UNDO_RS,
        &[
            "pub fn list_undo_actions(",
            "pub fn undo_action(",
            "Listing is metadata-only",
            "stack execution stays with C2-18",
            "Failed undo must not corrupt",
            "partially mark an action as executed",
        ],
    );
}

fn create_success_path_actions(repo: &Path) -> (i64, String) {
    let (_first_root, first_source) = source_file("first.pdf", b"first bytes");
    let (_second_root, second_source) = source_file("second.pdf", b"second bytes");
    let first = import_file(
        path_string(repo),
        path_string(&first_source),
        import_options(StorageMode::Copied, "finance", "first.pdf"),
    )
    .expect("import first file");
    let second = import_file(
        path_string(repo),
        path_string(&second_source),
        import_options(StorageMode::Copied, "docs", "second.pdf"),
    )
    .expect("import second file");

    let tag_report = batch_add_tags(
        path_string(repo),
        vec![first.id, second.id],
        vec!["Urgent".to_owned()],
    )
    .expect("create batch tag undo action");
    let tag_token = tag_report.undo_token.expect("batch tags create undo");
    rename_file(path_string(repo), first.id, "renamed.pdf".to_owned())
        .expect("create rename undo action");
    move_to_category(path_string(repo), second.id, "finance".to_owned())
        .expect("create move undo action");
    (first.id, tag_token)
}

fn assert_pending_actions_cover_all_supported_success_kinds(repo: &Path) {
    let actions = list_undo_actions(path_string(repo)).expect("list undo actions");
    let mut kinds = actions
        .iter()
        .map(|action| action.kind.as_str())
        .collect::<Vec<_>>();
    kinds.sort_unstable();
    assert_eq!(kinds, vec!["batch_add_tags", "move_files", "rename_files"]);
    assert!(actions.iter().all(|action| action.can_undo));
    assert!(actions
        .iter()
        .all(|action| action.status == UndoActionStatus::Pending));
    assert!(actions
        .iter()
        .all(|action| action.disabled_reason.is_none()));
}

fn assert_success_undo_refresh_contracts(repo: &Path, first_id: i64, tag_token: String) {
    let rename_token = only_undo_token(repo, "rename_files");
    let rename_result = undo_action(path_string(repo), rename_token.clone()).expect("undo rename");
    assert_eq!(rename_result.status, UndoActionStatus::Executed);
    assert_eq!(
        rename_result.refresh_targets,
        vec!["files", "undo_actions", "change_log", "selection"]
    );
    assert_eq!(
        file_rows(repo)
            .into_iter()
            .find(|(id, _, _, _)| *id == first_id)
            .expect("first file row after rename undo")
            .1,
        "finance/first.pdf"
    );

    let tag_result = undo_action(path_string(repo), tag_token).expect("undo batch tags");
    assert_eq!(
        tag_result.refresh_targets,
        vec!["files", "tags", "undo_actions", "change_log"]
    );
    assert!(tag_rows(repo).is_empty());
}

#[test]
fn undo_action_log_validation_locks_core_api_udl_and_rust_alignment() {
    assert_undo_signatures();
    assert_capability_and_control_map_alignment();
    assert_api_and_udl_alignment();
    assert_rust_export_and_boundary_alignment();
}

#[test]
fn undo_action_log_validation_covers_success_paths_and_refresh_contract() {
    let repo = initialized_repo();
    let (first_id, tag_token) = create_success_path_actions(repo.path());

    assert_pending_actions_cover_all_supported_success_kinds(repo.path());
    assert_success_undo_refresh_contracts(repo.path(), first_id, tag_token);
}

fn create_delete_restore_action(repo: &Path) -> String {
    let (_source_root, source) = source_file("trash-me.pdf", b"trash bytes");
    let entry = import_file(
        path_string(repo),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "trash-me.pdf"),
    )
    .expect("import file before delete");
    delete_file(path_string(repo), entry.id).expect("create delete undo action");
    only_undo_token(repo, "trash_delete")
}

fn assert_delete_action_points_to_test_trash(repo: &Path, token: &str, trash_dir: &Path) -> String {
    let inverse = undo_inverse(repo, token);
    let trash_path = inverse["trash_path"]
        .as_str()
        .expect("delete undo stores trash path")
        .to_owned();
    assert!(trash_path.starts_with(&path_string(trash_dir)));
    assert_eq!(
        list_undo_actions(path_string(repo)).expect("list actions")[0].kind,
        "trash_delete"
    );
    trash_path
}

fn assert_delete_restore_failure_keeps_retryable_state(repo: &Path, token: &str, trash_path: &str) {
    let before_files = file_rows(repo);
    let before_tags = tag_rows(repo);
    fs::remove_file(trash_path).expect("remove trash item");
    fs::create_dir(trash_path).expect("replace trash item with directory");

    let error = undo_action(path_string(repo), token.to_owned())
        .expect_err("changed trash item blocks restore");

    assert_error_mapping(&error, ErrorKind::Io, ErrorRecoverability::Retryable);
    assert_eq!(undo_status(repo, token), "pending");
    assert_eq!(file_rows(repo), before_files);
    assert_eq!(tag_rows(repo), before_tags);
}

fn assert_delete_restore_retry_succeeds(repo: &Path, token: &str, trash_path: &str) {
    fs::remove_dir(trash_path).expect("remove simulated bad trash directory");
    fs::write(trash_path, b"trash bytes").expect("restore trash fixture");
    let result = undo_action(path_string(repo), token.to_owned())
        .expect("retry succeeds after trash recovers");

    assert_eq!(result.status, UndoActionStatus::Executed);
    assert_eq!(
        result.refresh_targets,
        vec!["files", "undo_actions", "change_log", "selection", "tree"]
    );
    assert_eq!(undo_status(repo, token), "executed");
    assert!(repo.join("docs/trash-me.pdf").exists());
    assert!(!Path::new(trash_path).exists());
}

#[test]
fn undo_action_log_validation_covers_delete_restore_and_failure_no_partial_execution() {
    support::system_trash_home::with_test_system_trash(|trash_dir| {
        let repo = initialized_repo();
        let token = create_delete_restore_action(repo.path());
        let trash_path = assert_delete_action_points_to_test_trash(repo.path(), &token, trash_dir);

        assert_delete_restore_failure_keeps_retryable_state(repo.path(), &token, &trash_path);
        assert_delete_restore_retry_succeeds(repo.path(), &token, &trash_path);
    });
}

#[test]
fn undo_action_log_validation_covers_external_change_blocking_without_mutation() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("external.pdf", b"external bytes");
    let entry = import_file(
        path_string(repo.path()),
        path_string(&source),
        import_options(StorageMode::Copied, "docs", "external.pdf"),
    )
    .expect("import file before rename");
    rename_file(path_string(repo.path()), entry.id, "after.pdf".to_owned())
        .expect("create rename undo");
    let token = only_undo_token(repo.path(), "rename_files");
    fs::remove_file(repo.path().join("docs/after.pdf")).expect("simulate external file removal");
    let before_files = file_rows(repo.path());
    let before_tags = tag_rows(repo.path());

    let actions = list_undo_actions(path_string(repo.path())).expect("list blocked action");

    assert_eq!(actions[0].status, UndoActionStatus::Blocked);
    assert!(!actions[0].can_undo);
    assert_eq!(
        actions[0].disabled_reason.as_deref(),
        Some("File no longer exists")
    );

    let error = undo_action(path_string(repo.path()), token.clone())
        .expect_err("external removal cannot be undone safely");

    assert_error_mapping(
        &error,
        ErrorKind::FileNotFound,
        ErrorRecoverability::RefreshRequired,
    );
    assert_eq!(undo_status(repo.path(), &token), "pending");
    assert_eq!(file_rows(repo.path()), before_files);
    assert_eq!(tag_rows(repo.path()), before_tags);
}

#[test]
fn undo_action_log_validation_locks_persistence_and_testing_evidence() {
    assert_all_contains(
        DB_UNDO_RS,
        &[
            "ensure_undo_metadata_ready",
            "load_undo_actions",
            "execute_undo_action_row",
            "execute_batch_tag_action",
            "mark_action_status",
            "UndoActionStatus::Blocked",
        ],
    );

    assert_all_contains(
        FILE_ACTIONS_RS,
        &[
            "restore_file_state",
            "restore_deleted_file",
            "pending_file_block_reason",
            "execute_file_action",
            "insert_file_undo_change",
            "File changed after action",
            "Trash item changed",
        ],
    );

    assert_all_contains(
        TESTING_DOC,
        &[
            "集成测试目录",
            "`core/tests/`",
            "关键测试场景",
            "DB / Migration",
            "崩溃测试",
            "测试反模式",
        ],
    );
}
