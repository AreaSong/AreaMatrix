use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    init_repo, list_icloud_conflicts, CoreError, ICloudConflictPair, ICloudConflictStatus,
    OverviewOutput, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::Connection;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-25-list-icloud-conflicts.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const S1_36_ICLOUD_CONFLICT_LIST: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-36-icloud-conflict-list.md");
const S1_25_ICLOUD_CONFLICT_MIN: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-25-icloud-conflict-min.md");
const API_RS: &str = include_str!("../src/api.rs");
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const ICLOUD_CONFLICTS_RS: &str = include_str!("../src/icloud_conflicts.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document or source to contain `{needle}`"
    );
}

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

fn write_repo_file(repo: &Path, relative_path: &str, bytes: &[u8]) -> PathBuf {
    let path = repo.join(relative_path);
    let parent = path
        .parent()
        .expect("repository fixture should have parent");
    fs::create_dir_all(parent).expect("create fixture parent directory");
    fs::write(&path, bytes).expect("write repository fixture file");
    path
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn active_file_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM files WHERE status = 'active'",
            [],
            |row| row.get(0),
        )
        .expect("count active file rows")
}

fn change_log_count(repo: &Path) -> i64 {
    open_db(repo)
        .query_row("SELECT COUNT(*) FROM change_log", [], |row| row.get(0))
        .expect("count change_log rows")
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
            .expect("snapshot path should stay under repository root")
            .to_path_buf();
        let file_type = entry.file_type().expect("read snapshot file type");
        if file_type.is_dir() {
            snapshot.insert(relative, None);
            collect_snapshot(root, &path, snapshot);
        } else if file_type.is_file() {
            snapshot.insert(relative, Some(fs::read(path).expect("read snapshot file")));
        }
    }
}

fn conflict_by_path<'a>(
    conflicts: &'a [ICloudConflictPair],
    conflicted_copy_path: &str,
) -> &'a ICloudConflictPair {
    conflicts
        .iter()
        .find(|conflict| conflict.conflicted_copy_path == conflicted_copy_path)
        .unwrap_or_else(|| panic!("expected conflict `{conflicted_copy_path}`"))
}

#[test]
fn list_icloud_conflicts_integration_verify_docs_api_udl_and_consumers_stay_aligned() {
    assert_c1_25_capability_spec();
    assert_core_api_and_udl_contract();
    assert_stage_one_consumers();
    assert_rust_entry_points_are_real_read_only_wiring();
}

fn assert_c1_25_capability_spec() {
    for fragment in [
        "# C1-25 list-icloud-conflicts",
        "- S1-36 icloud-conflict-list",
        "- S1-25 icloud-conflict-min",
        "计划新增：`list_icloud_conflicts(repo_path) -> sequence<ICloudConflictPair>`",
        "冲突组列表：原始版本、conflicted copy、修改时间、状态。",
        "只读扫描 iCloud conflicted copy。",
        "列表页不删除、不移动任何冲突副本。",
        "`ICloudPlaceholder`",
        "`PermissionDenied`",
        "`Io`",
        "`Db`",
        "空态、加载失败、识别不确定状态均可结构化表达。",
        "Resolve 入口只处理单项，不在列表页静默合并。",
        "不确定冲突必须标记 `Needs review`。",
        "可视化 diff 增强属于 Stage 2 的 C2-17。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }
}

fn assert_core_api_and_udl_contract() {
    for fragment in [
        "sequence<ICloudConflictPair> list_icloud_conflicts(string repo_path);",
        "dictionary ICloudConflictPair",
        "string conflict_id;",
        "string? original_path;",
        "string conflicted_copy_path;",
        "i64? original_modified_at;",
        "i64 conflicted_modified_at;",
        "ICloudConflictStatus status;",
        "string? uncertainty_reason;",
        "enum ICloudConflictStatus { \"NeedsReview\", \"Resolved\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `list_icloud_conflicts(repoPath) throws -> [ICloudConflictPair]`",
        "只扫描 iCloud conflicted copy 和可选 conflict state metadata。",
        "不删除、不移动、不重命名、不覆盖、不合并任何原始文件或冲突副本。",
        "不触发 iCloud placeholder 下载",
        "不写 `files` 记录",
        "`ICloudPlaceholder`：关键 metadata 或冲突副本仍是未下载占位符。",
        "空态返回空数组",
        "`status = NeedsReview`",
        "- `list_icloud_conflicts`（扫描 iCloud conflicted copy）",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_stage_one_consumers() {
    for fragment in [
        "| S1-36 | icloud-conflict-list | C1-25 | `list_icloud_conflicts`",
        "read conflicted copies only",
        "| S1-25 | icloud-conflict-min | C1-01, C1-21 |",
        "iCloud placeholder probe",
        "标记为 Real Core 的页面，最终验收不得用 mock、fixture 或静态占位通过。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "Review conflicts",
        "AreaMatrix will not delete any version automatically.",
        "显示每组冲突的两个版本、修改时间和位置。",
        "Resolve 只打开单项解决 sheet，不在列表页直接删除或移动任何版本。",
        "No iCloud conflicts found",
        "Checking iCloud conflicts...",
        "Needs review",
        "诊断导出不包含用户文件内容，不自动上传。",
    ] {
        assert_contains(S1_36_ICLOUD_CONFLICT_LIST, fragment);
    }

    for fragment in [
        "入口：`S1-36 icloud-conflict-list` 的 `Resolve...`",
        "AreaMatrix will not delete any version automatically.",
        "默认保留两份。",
        "Apply 前不移动、不删除、不重命名任何文件。",
        "Cancel 和失败路径不会改动文件。",
    ] {
        assert_contains(S1_25_ICLOUD_CONFLICT_MIN, fragment);
    }
}

fn assert_rust_entry_points_are_real_read_only_wiring() {
    for fragment in [
        "pub fn list_icloud_conflicts(repo_path: String)",
        "C1-25 owns the read-only contract for S1-36",
        "must not delete, move, rename, overwrite, merge, or download",
        "Single-item resolution remains a later explicit action",
        "CoreError::ICloudPlaceholder",
        "CoreError::PermissionDenied",
        "CoreError::Io",
        "CoreError::Db",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Lifecycle state for an iCloud conflicted copy pair.",
        "Read-only iCloud conflicted copy pair returned to Swift.",
        "Stable identifier for later single-item resolution.",
        "Repository-relative original path when it can be identified.",
        "Reason shown when pairing is uncertain and needs user review.",
    ] {
        assert_contains(DOMAIN_RS, fragment);
    }

    for fragment in [
        "WalkDir::new(&repo)",
        ".follow_links(false)",
        ".same_file_system(true)",
        "filter_entry(|entry| should_descend(&repo, entry))",
        "conflicts.sort_by",
        "ICloudConflictStatus::NeedsReview",
        "reject_placeholder_path",
        "AREA_MATRIX_DIR",
    ] {
        assert_contains(ICLOUD_CONFLICTS_RS, fragment);
    }
}

#[test]
fn list_icloud_conflicts_integration_verify_real_core_supports_s1_36_consumption() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/report.pdf", b"original report");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf",
        b"conflicted report",
    );
    write_repo_file(
        repo.path(),
        "finance/invoice (Bob's conflicted copy).pdf",
        b"conflicted invoice",
    );

    let before_snapshot = snapshot_tree(repo.path());
    let before_active = active_file_count(repo.path());
    let before_log = change_log_count(repo.path());
    let conflicts = list_icloud_conflicts(path_string(repo.path())).expect("list conflicts");

    assert_eq!(conflicts.len(), 2);
    assert_eq!(conflicts, {
        let mut sorted = conflicts.clone();
        sorted.sort_by(|left, right| {
            right
                .conflicted_modified_at
                .cmp(&left.conflicted_modified_at)
                .then_with(|| left.conflicted_copy_path.cmp(&right.conflicted_copy_path))
        });
        sorted
    });

    let report = conflict_by_path(&conflicts, "docs/report (Alice's conflicted copy).pdf");
    assert_eq!(report.conflict_id, report.conflicted_copy_path);
    assert_eq!(report.original_path.as_deref(), Some("docs/report.pdf"));
    assert!(report.original_modified_at.is_some());
    assert!(report.conflicted_modified_at > 0);
    assert_eq!(report.status, ICloudConflictStatus::NeedsReview);
    assert_eq!(report.uncertainty_reason, None);

    let invoice = conflict_by_path(&conflicts, "finance/invoice (Bob's conflicted copy).pdf");
    assert_eq!(invoice.original_path, None);
    assert_eq!(invoice.original_modified_at, None);
    assert_eq!(invoice.status, ICloudConflictStatus::NeedsReview);
    assert_eq!(
        invoice.uncertainty_reason.as_deref(),
        Some("original version not found")
    );

    assert_eq!(snapshot_tree(repo.path()), before_snapshot);
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);
}

#[test]
fn list_icloud_conflicts_integration_verify_placeholder_failure_is_read_only() {
    let repo = initialized_repo();
    write_repo_file(repo.path(), "docs/report.pdf", b"original");
    write_repo_file(
        repo.path(),
        "docs/report (Alice's conflicted copy).pdf.icloud",
        b"placeholder marker",
    );

    let before_snapshot = snapshot_tree(repo.path());
    let before_active = active_file_count(repo.path());
    let before_log = change_log_count(repo.path());
    let result = list_icloud_conflicts(path_string(repo.path()));

    assert!(matches!(result, Err(CoreError::ICloudPlaceholder { .. })));
    assert_eq!(snapshot_tree(repo.path()), before_snapshot);
    assert_eq!(active_file_count(repo.path()), before_active);
    assert_eq!(change_log_count(repo.path()), before_log);
}
