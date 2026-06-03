use area_matrix_core::{
    record_watcher_health, CoreError, CoreResult, ExternalEventKind, PlatformWatcherBackend,
    PlatformWatcherEventSample, PlatformWatcherHealthReason, PlatformWatcherHealthSignal,
    PlatformWatcherSnapshot, PlatformWatcherStatus,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-56-c4-12-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-12-platform-watcher-status.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const WIN_WATCHER_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-04-watcher-status.md");
const LNX_WATCHER_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-LNX-04-watcher-status.md");
const RESCAN_CONFIRM_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-07-rescan-confirm.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const WATCHER_RS: &str = include_str!("../src/platform_watcher_status.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn watcher_signal() -> PlatformWatcherHealthSignal {
    PlatformWatcherHealthSignal {
        backend: PlatformWatcherBackend::ReadDirectoryChangesW,
        status: PlatformWatcherStatus::Running,
        watched_path: "C:\\Users\\me\\Documents\\AreaMatrix".to_owned(),
        last_event_id: Some(184),
        last_event_at: Some(1_777_300_000),
        last_sync_event_id: Some(183),
        last_sync_at: Some(1_777_300_005),
        last_rescan_at: Some(1_777_299_900),
        pending_event_count: 1,
        watch_count: Some(128),
        error_summary: Some("OneDrive may generate bursts of file events.".to_owned()),
        health_reasons: vec![PlatformWatcherHealthReason::CloudSyncNoise],
        recent_events: vec![PlatformWatcherEventSample {
            path: "docs/report.pdf".to_owned(),
            kind: ExternalEventKind::Modified,
            fs_event_id: 184,
            occurred_at: Some(1_777_300_000),
        }],
        reported_at: 1_777_300_010,
    }
}

#[test]
fn platform_watcher_status_contract_exports_signature_inputs_outputs_and_errors() {
    fn assert_record(
        _: fn(String, PlatformWatcherHealthSignal) -> CoreResult<PlatformWatcherSnapshot>,
    ) {
    }
    assert_record(record_watcher_health);

    let signal = watcher_signal();
    assert_eq!(
        signal.backend,
        PlatformWatcherBackend::ReadDirectoryChangesW
    );
    assert_eq!(signal.status, PlatformWatcherStatus::Running);
    assert_eq!(signal.pending_event_count, 1);
    assert_eq!(signal.watch_count, Some(128));
    assert_eq!(
        signal.health_reasons,
        vec![PlatformWatcherHealthReason::CloudSyncNoise]
    );
    assert_eq!(signal.recent_events[0].kind, ExternalEventKind::Modified);

    let snapshot = PlatformWatcherSnapshot {
        repo_path: "C:\\Users\\me\\Documents\\AreaMatrix".to_owned(),
        backend: signal.backend.clone(),
        status: signal.status.clone(),
        watched_path: signal.watched_path.clone(),
        last_event_id: signal.last_event_id,
        last_event_at: signal.last_event_at,
        last_sync_event_id: signal.last_sync_event_id,
        last_sync_at: signal.last_sync_at,
        last_rescan_at: signal.last_rescan_at,
        pending_event_count: signal.pending_event_count,
        watch_count: signal.watch_count,
        error_summary: signal.error_summary.clone(),
        health_reasons: signal.health_reasons.clone(),
        recent_events: signal.recent_events.clone(),
        reported_at: signal.reported_at,
    };
    assert_eq!(snapshot.status, PlatformWatcherStatus::Running);
    assert_eq!(snapshot.last_sync_event_id, Some(183));
    assert_eq!(snapshot.recent_events.len(), 1);

    let documented_errors = [
        CoreError::db("watcher health metadata unavailable"),
        CoreError::io("watcher health metadata io unavailable"),
    ];
    assert_eq!(documented_errors.len(), 2);
}

#[test]
fn platform_watcher_status_contract_rejects_invalid_input_without_fake_success() {
    assert!(matches!(
        record_watcher_health(String::new(), watcher_signal()),
        Err(CoreError::Db { .. })
    ));

    let mut invalid = watcher_signal();
    invalid.pending_event_count = -1;
    assert!(matches!(
        record_watcher_health("/tmp/repo".to_owned(), invalid),
        Err(CoreError::Db { .. })
    ));

    let valid_without_persistence = record_watcher_health("/tmp/repo".to_owned(), watcher_signal());
    assert!(matches!(
        valid_without_persistence,
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn platform_watcher_status_docs_core_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-56: C4-12 contract-api",
        "为 C4-12 platform-watcher-status 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
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
        "- `Db`",
        "- `Io`",
        "Windows/Linux watcher 状态可被 UI 查询。",
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

    for fragment in [
        "PlatformWatcherSnapshot record_watcher_health(",
        "string repo_path, PlatformWatcherHealthSignal signal",
        "dictionary PlatformWatcherHealthSignal",
        "PlatformWatcherBackend backend;",
        "PlatformWatcherStatus status;",
        "string watched_path;",
        "i64? last_event_id;",
        "i64? last_sync_event_id;",
        "i64 pending_event_count;",
        "i64? watch_count;",
        "string? error_summary;",
        "sequence<PlatformWatcherHealthReason> health_reasons;",
        "sequence<PlatformWatcherEventSample> recent_events;",
        "dictionary PlatformWatcherSnapshot",
        "string repo_path;",
        "enum PlatformWatcherBackend { \"ReadDirectoryChangesW\", \"Inotify\", \"Unknown\" };",
        "enum PlatformWatcherStatus { \"Starting\", \"Running\", \"Paused\", \"Error\", \"Unavailable\" };",
        "\"LimitExceeded\"",
        "\"NetworkMount\"",
        "\"CloudSyncNoise\"",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `record_watcher_health(repo, signal)` | sync/watcher | √ | Db / Io |",
        "### `record_watcher_health(repoPath, signal) throws -> PlatformWatcherSnapshot`",
        "C4-12 的平台 watcher 状态入口",
        "S4-WIN-04 watcher-status",
        "S4-LNX-04 watcher-status",
        "不触发 `sync_external_changes`",
        "不推进 fs event cursor",
        "Run rescan now",
        "必须进入",
        "S4-X-07 rescan-confirm",
        "本合同不新增 control map 之外的页面能力。",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in ["`Db { message }`", "`Io { message }`"] {
        assert_contains(ERROR_CODES, fragment);
    }
}

#[test]
fn platform_watcher_status_documents_consumers_and_scope_boundaries() {
    for fragment in [
        "显示当前 watcher 状态：Running、Starting、Paused、Error、Unavailable。",
        "显示监听路径和最近事件时间。",
        "显示待处理事件数量和最近一次 scan 时间。",
        "提供 `Run rescan now` 入口，但点击后必须先进入 `S4-X-07 rescan-confirm`。",
        "OneDrive 路径：增加说明",
        "Rescan running：显示进度，不允许并发启动第二次 rescan。",
    ] {
        assert_contains(WIN_WATCHER_PAGE, fragment);
    }

    for fragment in [
        "显示 inotify watcher 当前状态。",
        "显示监听路径、watch 数量、最近事件、最近扫描时间。",
        "显示 inotify limit 相关错误。",
        "提供 `Run rescan now` 入口，但点击后必须先进入 `S4-X-07 rescan-confirm`。",
        "页面不会请求 sudo，也不会自动修改系统配置。",
    ] {
        assert_contains(LNX_WATCHER_PAGE, fragment);
    }

    for fragment in [
        "Windows/Linux watcher 页的 rescan 必须先进入本确认页。",
        "确认前必须看到 dry-run 影响预览。",
        "页面明确说明不移动、不删除、不覆盖用户文件。",
        "rescan summary 可审计",
    ] {
        assert_contains(RESCAN_CONFIRM_PAGE, fragment);
    }

    for fragment in [
        "Records platform watcher health for Windows and Linux watcher-status pages.",
        "Manual rescan remains C4-19",
        "confirmation flow before any indexing write",
        "Returns `CoreError::Db { message }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C4-12 platform watcher status contract types and entry point.",
        "Platform watcher backend that produced a health signal.",
        "Current lifecycle state for a platform watcher.",
        "Structured reason that explains watcher degradation without parsing text.",
        "Recent watcher event sample for diagnostic previews.",
        "Platform-provided watcher health signal accepted by Core.",
        "Normalized watcher snapshot returned to Windows and Linux watcher pages.",
        "Core accepts only a sanitized health signal",
        "must not start watchers",
        "trigger manual rescan",
        "mutate user files",
        "watcher health metadata is unavailable",
    ] {
        assert_contains(WATCHER_RS, fragment);
    }

    for fragment in [
        "PlatformWatcherBackend",
        "PlatformWatcherEventSample",
        "PlatformWatcherHealthReason",
        "PlatformWatcherHealthSignal",
        "PlatformWatcherSnapshot",
        "PlatformWatcherStatus",
    ] {
        assert_contains(LIB_RS, fragment);
    }
}
