use std::{fs, path::Path};

use area_matrix_core::{
    get_fs_event_cursor, init_repo, record_watcher_health, set_fs_event_cursor, CoreError,
    CoreResult, ExternalEventKind, OverviewOutput, PlatformWatcherBackend,
    PlatformWatcherEventSample, PlatformWatcherHealthReason, PlatformWatcherHealthSignal,
    PlatformWatcherSnapshot, PlatformWatcherStatus, RepoInitMode, RepoInitOptions,
};
use pretty_assertions::assert_eq;
use rusqlite::{Connection, OptionalExtension};

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-59-c4-12-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-12-platform-watcher-status.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const WIN_WATCHER_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-04-watcher-status.md");
const LNX_WATCHER_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-LNX-04-watcher-status.md");
const RESCAN_CONFIRM_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-07-rescan-confirm.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const WATCHER_RS: &str = include_str!("../src/platform_watcher_status.rs");
const DB_WATCHER_RS: &str = include_str!("../src/db/platform_watcher_status.rs");
const CONTRACT_TEST: &str = include_str!("platform_watcher_status_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("platform_watcher_status_implementation.rs");
const FAILURE_TEST: &str = include_str!("platform_watcher_status_failure_recovery.rs");

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
    .expect("initialize repository for watcher validation");
    repo
}

fn watcher_signal(repo: &Path) -> PlatformWatcherHealthSignal {
    PlatformWatcherHealthSignal {
        backend: PlatformWatcherBackend::ReadDirectoryChangesW,
        status: PlatformWatcherStatus::Running,
        watched_path: path_string(repo),
        last_event_id: Some(300),
        last_event_at: Some(1_777_600_000),
        last_sync_event_id: Some(295),
        last_sync_at: Some(1_777_600_010),
        last_rescan_at: Some(1_777_599_000),
        pending_event_count: 2,
        watch_count: Some(96),
        error_summary: Some("OneDrive may generate bursts of file events.".to_owned()),
        health_reasons: vec![PlatformWatcherHealthReason::CloudSyncNoise],
        recent_events: vec![
            PlatformWatcherEventSample {
                path: "docs/report.pdf".to_owned(),
                kind: ExternalEventKind::Modified,
                fs_event_id: 299,
                occurred_at: Some(1_777_599_990),
            },
            PlatformWatcherEventSample {
                path: "docs/spec.md".to_owned(),
                kind: ExternalEventKind::Renamed,
                fs_event_id: 300,
                occurred_at: Some(1_777_600_000),
            },
        ],
        reported_at: 1_777_600_020,
    }
}

fn repo_config_value(repo: &Path, key: &str) -> Option<String> {
    Connection::open(repo.join(".areamatrix/index.db"))
        .expect("open repository database")
        .query_row(
            "SELECT value FROM repo_config WHERE key = ?1",
            [key],
            |row| row.get(0),
        )
        .optional()
        .expect("query repo_config value")
}

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn platform_watcher_status_validation_proves_ui_ready_snapshot_without_side_effects() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user owned\n").expect("write user file");
    set_fs_event_cursor(path_string(repo.path()), 250).expect("seed fs event cursor");
    let before_user_file = fs::read(repo.path().join("README.md")).expect("read user file");

    let snapshot = record_watcher_health(path_string(repo.path()), watcher_signal(repo.path()))
        .expect("record UI-ready watcher snapshot");

    assert_eq!(snapshot.repo_path, path_string(repo.path()));
    assert_eq!(
        snapshot.backend,
        PlatformWatcherBackend::ReadDirectoryChangesW
    );
    assert_eq!(snapshot.status, PlatformWatcherStatus::Running);
    assert_eq!(snapshot.watched_path, path_string(repo.path()));
    assert_eq!(snapshot.last_event_id, Some(300));
    assert_eq!(snapshot.last_sync_event_id, Some(295));
    assert_eq!(snapshot.last_rescan_at, Some(1_777_599_000));
    assert_eq!(snapshot.pending_event_count, 2);
    assert_eq!(snapshot.watch_count, Some(96));
    assert_eq!(
        snapshot.error_summary.as_deref(),
        Some("OneDrive may generate bursts of file events.")
    );
    assert_eq!(
        snapshot.health_reasons,
        vec![PlatformWatcherHealthReason::CloudSyncNoise]
    );
    assert_eq!(snapshot.recent_events.len(), 2);
    assert_eq!(snapshot.recent_events[1].kind, ExternalEventKind::Renamed);
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read cursor"),
        Some(250)
    );
    assert_eq!(
        fs::read(repo.path().join("README.md")).expect("read user file"),
        before_user_file
    );

    let stored = repo_config_value(repo.path(), "platform_watcher_health")
        .expect("stored watcher health metadata");
    let stored: serde_json::Value = serde_json::from_str(&stored).expect("parse watcher metadata");
    assert_eq!(stored["backend"], "ReadDirectoryChangesW");
    assert_eq!(stored["status"], "Running");
    assert_eq!(stored["last_sync_event_id"], 295);
    assert_eq!(stored["recent_events"][1]["kind"], "Renamed");
    assert!(!stored.to_string().contains("user owned"));
}

#[test]
fn platform_watcher_status_validation_covers_failures_without_partial_writes() {
    let repo = initialized_repo();
    fs::write(repo.path().join("README.md"), b"user owned\n").expect("write user file");
    set_fs_event_cursor(path_string(repo.path()), 44).expect("seed fs event cursor");
    record_watcher_health(path_string(repo.path()), watcher_signal(repo.path()))
        .expect("record baseline watcher metadata");
    let before_user_file = fs::read(repo.path().join("README.md")).expect("read user file");
    let before_metadata = repo_config_value(repo.path(), "platform_watcher_health");

    let mut invalid = watcher_signal(repo.path());
    invalid.recent_events[0].fs_event_id = -1;
    assert!(matches!(
        record_watcher_health(path_string(repo.path()), invalid),
        Err(CoreError::Db { .. })
    ));
    assert!(matches!(
        record_watcher_health("   ".to_owned(), watcher_signal(repo.path())),
        Err(CoreError::Db { .. })
    ));

    assert_eq!(
        repo_config_value(repo.path(), "platform_watcher_health"),
        before_metadata
    );
    assert_eq!(
        get_fs_event_cursor(path_string(repo.path())).expect("read cursor"),
        Some(44)
    );
    assert_eq!(
        fs::read(repo.path().join("README.md")).expect("read user file"),
        before_user_file
    );

    let uninitialized = tempfile::tempdir().expect("create uninitialized repository directory");
    assert!(matches!(
        record_watcher_health(
            path_string(uninitialized.path()),
            watcher_signal(uninitialized.path())
        ),
        Err(CoreError::Db { .. })
    ));
    assert!(!uninitialized.path().join(".areamatrix").exists());
}

#[test]
fn platform_watcher_status_validation_locks_api_udl_rust_and_test_evidence() {
    fn assert_record(
        _: fn(String, PlatformWatcherHealthSignal) -> CoreResult<PlatformWatcherSnapshot>,
    ) {
    }
    fn assert_get_cursor(_: fn(String) -> CoreResult<Option<i64>>) {}
    fn assert_set_cursor(_: fn(String, i64) -> CoreResult<()>) {}

    assert_record(record_watcher_health);
    assert_get_cursor(get_fs_event_cursor);
    assert_set_cursor(set_fs_event_cursor);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_consumer_scope_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-59: C4-12 validation",
        "为 C4-12 platform-watcher-status 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-59",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-12 platform-watcher-status",
        "- S4-WIN-04 watcher-status",
        "- S4-LNX-04 watcher-status",
        "- `sync_external_changes`",
        "- `get_fs_event_cursor`",
        "- `set_fs_event_cursor`",
        "计划新增：`record_watcher_health`",
        "platform watcher events 和 health signal。",
        "watcher 状态、last sync、error summary。",
        "更新 cursor 和 watcher health metadata。",
        "Core 不监听文件系统，只消费平台层事件。",
        "事件失败不推进 cursor。",
        "手动 rescan 需进入确认页。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-WIN-04 | watcher-status | C4-12, C4-19 | watcher health / rescan | Windows watcher 在平台层",
        "| S4-LNX-04 | watcher-status | C4-12, C4-19 | watcher health / rescan | inotify 在平台层",
        "Rust Core 复用，平台层负责 picker、权限、watcher 和系统集成。",
        "初始化、接管、Replace、Remove record、rescan 都必须确认后执行。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    assert_core_api_and_udl_alignment();
    assert_rust_surface_alignment();
    assert_error_alignment();
}

fn assert_core_api_and_udl_alignment() {
    for fragment in [
        "SyncResult sync_external_changes(string repo_path, sequence<ExternalEvent> events);",
        "i64? get_fs_event_cursor(string repo_path);",
        "void set_fs_event_cursor(string repo_path, i64 last_event_id);",
        "PlatformWatcherSnapshot record_watcher_health(",
        "string repo_path, PlatformWatcherHealthSignal signal",
        "dictionary PlatformWatcherHealthSignal",
        "PlatformWatcherBackend backend;",
        "PlatformWatcherStatus status;",
        "i64? last_sync_event_id;",
        "i64 pending_event_count;",
        "sequence<PlatformWatcherEventSample> recent_events;",
        "dictionary PlatformWatcherSnapshot",
        "enum PlatformWatcherBackend { \"ReadDirectoryChangesW\", \"Inotify\", \"Unknown\" };",
        "enum PlatformWatcherStatus { \"Starting\", \"Running\", \"Paused\", \"Error\", \"Unavailable\" };",
        "\"PermissionDenied\", \"PathMissing\", \"BackendUnavailable\", \"DatabaseLocked\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `record_watcher_health(repoPath, signal) throws -> PlatformWatcherSnapshot`",
        "C4-12 的平台 watcher 状态入口",
        "不触发 `sync_external_changes`，不推进 fs event cursor",
        "不读取用户文件正文，不触发 iCloud/OneDrive 下载",
        "Run rescan now",
        "S4-X-07，不由 C4-12 直接触发",
        "| `record_watcher_health(repo, signal)` | sync/watcher | √ | Db / Io |",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

fn assert_rust_surface_alignment() {
    for fragment in [
        "pub fn record_watcher_health(",
        "PlatformWatcherHealthSignal",
        "Core must",
        "not start platform watchers",
        "trigger manual rescan",
        "move/delete/rename/overwrite user",
        "pub(crate) fn record_watcher_health(",
        "validate_signal(&repo_path, &signal)?;",
        "db::upsert_platform_watcher_health",
        "pub(crate) fn upsert_platform_watcher_health",
        "ON CONFLICT(key) DO UPDATE",
    ] {
        assert!(
            API_RS.contains(fragment)
                || WATCHER_RS.contains(fragment)
                || DB_WATCHER_RS.contains(fragment)
        );
    }
}

fn assert_error_alignment() {
    for fragment in ["`Db { message }`", "`Io { message }`"] {
        assert_contains(ERROR_CODES, fragment);
    }
}

fn assert_consumer_scope_alignment() {
    for fragment in [
        "显示当前 watcher 状态：Running、Starting、Paused、Error、Unavailable。",
        "OneDrive 路径：增加说明",
        "Run rescan now",
        "S4-X-07 rescan-confirm",
    ] {
        assert_contains(WIN_WATCHER_PAGE, fragment);
    }

    for fragment in [
        "显示 inotify watcher 当前状态。",
        "显示 inotify limit 相关错误。",
        "页面不会请求 sudo，也不会自动修改系统配置。",
        "Run rescan now",
    ] {
        assert_contains(LNX_WATCHER_PAGE, fragment);
    }

    for fragment in [
        "Windows/Linux watcher 页的 rescan 必须先进入本确认页。",
        "dry-run 期间不写 DB、不写 change log、不修改任何文件。",
        "页面明确说明不移动、不删除、不覆盖用户文件。",
    ] {
        assert_contains(RESCAN_CONFIRM_PAGE, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "platform_watcher_status_contract_exports_signature_inputs_outputs_and_errors",
        "platform_watcher_status_docs_core_api_udl_and_control_map_stay_aligned",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "platform_watcher_status_implementation_records_snapshot_metadata_without_advancing_cursor",
        "platform_watcher_status_implementation_updates_existing_health_metadata_only",
        "platform_watcher_status_implementation_rejects_invalid_signal_without_persistence",
        "platform_watcher_status_implementation_maps_missing_metadata_to_db_error",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "platform_watcher_status_accepts_empty_state_without_side_effects",
        "platform_watcher_status_rejects_illegal_input_without_partial_metadata",
        "platform_watcher_status_records_permission_reason_as_structured_health_state",
        "platform_watcher_status_maps_metadata_permission_to_io_without_overwriting_snapshot",
        "platform_watcher_status_maps_db_schema_failure_without_user_file_or_cursor_changes",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
