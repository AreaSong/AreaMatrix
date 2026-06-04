use area_matrix_core::{
    get_latest_scan_session, reindex_from_filesystem, resume_scan_session, CoreError, CoreResult,
    ReindexReport, ScanSession, ScanSessionKind, ScanSessionStatus,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-91-c4-19-contract-api.md"
);
const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-4-multiplatform/C4-19-manual-rescan.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const RESCAN_CONFIRM_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-07-rescan-confirm.md");
const WIN_WATCHER_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-WIN-04-watcher-status.md");
const LNX_WATCHER_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-LNX-04-watcher-status.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const DOMAIN_RS: &str = include_str!("../src/domain.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn assert_contains_normalized(haystack: &str, needle: &str) {
    let normalized_haystack = normalize_text(haystack);
    let normalized_needle = needle.split_whitespace().collect::<Vec<_>>().join(" ");
    assert!(
        normalized_haystack.contains(&normalized_needle),
        "expected normalized text to contain `{needle}`"
    );
}

fn normalize_text(text: &str) -> String {
    text.lines()
        .map(|line| {
            line.trim_start()
                .strip_prefix("///")
                .or_else(|| line.trim_start().strip_prefix("//"))
                .unwrap_or(line.trim_start())
                .trim_start()
        })
        .collect::<Vec<_>>()
        .join(" ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

#[test]
fn manual_rescan_contract_exports_documented_signatures_outputs_and_errors() {
    fn assert_reindex(_: fn(String) -> CoreResult<ReindexReport>) {}
    fn assert_latest(_: fn(String) -> CoreResult<Option<ScanSession>>) {}
    fn assert_resume(_: fn(String, i64) -> CoreResult<ReindexReport>) {}

    assert_reindex(reindex_from_filesystem);
    assert_latest(get_latest_scan_session);
    assert_resume(resume_scan_session);

    let report = ReindexReport {
        scan_session_id: Some(419),
        inserted: 3,
        updated: 2,
        skipped: 1,
        errors: vec!["docs/unreadable.pdf: permission denied".to_owned()],
    };
    assert_eq!(report.scan_session_id, Some(419));
    assert_eq!(report.inserted + report.updated + report.skipped, 6);

    let session = ScanSession {
        id: 419,
        kind: ScanSessionKind::Reindex,
        status: ScanSessionStatus::Completed,
        last_path: Some("docs/report.pdf".to_owned()),
        inserted: report.inserted,
        updated: report.updated,
        skipped: report.skipped,
        started_at: 1_777_800_000,
        updated_at: 1_777_800_060,
        finished_at: Some(1_777_800_060),
        errors: report.errors.clone(),
    };
    assert_eq!(session.kind, ScanSessionKind::Reindex);
    assert_eq!(session.status, ScanSessionStatus::Completed);
    assert_eq!(session.finished_at, Some(1_777_800_060));
    assert_eq!(session.errors, report.errors);

    let documented_errors = [
        CoreError::permission_denied("permission denied"),
        CoreError::db("database error"),
        CoreError::io("io error"),
    ];
    assert_eq!(documented_errors.len(), 3);
}

#[test]
fn manual_rescan_docs_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-91: C4-19 contract-api",
        "为 C4-19 manual-rescan 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-19 manual-rescan",
        "- S4-X-07 rescan-confirm",
        "- S4-WIN-04 watcher-status",
        "- S4-LNX-04 watcher-status",
        "- `reindex_from_filesystem`",
        "- `get_latest_scan_session`",
        "- `resume_scan_session`",
        "repo path、rescan scope。",
        "ReindexReport 和 scan session。",
        "写 scan_sessions。",
        "upsert files metadata。",
        "只读扫描 repo。",
        "不移动、不删除、不覆盖用户文件。",
        "- `PermissionDenied`",
        "- `Db`",
        "- `Io`",
        "手动 rescan 前必须确认影响。",
        "扫描失败可恢复或继续。",
        "不覆盖 README 和 generated 边界。",
        "后台定时重扫策略后续拆分。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-WIN-04 | watcher-status | C4-12, C4-19 | watcher health / rescan | Windows watcher 在平台层",
        "| S4-LNX-04 | watcher-status | C4-12, C4-19 | watcher health / rescan | inotify 在平台层",
        "| S4-X-07 | rescan-confirm | C4-19 | manual rescan | 只读扫描，不改用户文件",
        "初始化、接管、Replace、Remove record、rescan 都必须确认后执行。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "ReindexReport reindex_from_filesystem(string repo_path);",
        "ScanSession? get_latest_scan_session(string repo_path);",
        "ReindexReport resume_scan_session(string repo_path, i64 scan_session_id);",
        "dictionary ReindexReport",
        "i64? scan_session_id;",
        "i64 inserted;",
        "i64 updated;",
        "i64 skipped;",
        "sequence<string> errors;",
        "dictionary ScanSession",
        "ScanSessionKind kind;",
        "ScanSessionStatus status;",
        "string? last_path;",
        "i64 started_at;",
        "i64 updated_at;",
        "i64? finished_at;",
        "enum ScanSessionKind { \"Adopt\", \"Reindex\" };",
        "enum ScanSessionStatus { \"Running\", \"Completed\", \"Paused\", \"Failed\", \"Interrupted\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "| `reindex_from_filesystem(repo)` | repo | √ | Io / Db |",
        "| `get_latest_scan_session(repo)` | repo | √ | Db |",
        "| `resume_scan_session(repo, id)` | repo | √ | Io / Db |",
        "### `reindex_from_filesystem(repoPath: String) throws -> ReindexReport`",
        "### `get_latest_scan_session(repoPath: String) throws -> ScanSession?`",
        "### `resume_scan_session(repoPath: String, scanSessionId: Int64) throws -> ReindexReport`",
        "只允许写 `.areamatrix/index.db` 与 scan session metadata。",
        "不移动、不重命名、不删除、不覆盖、不 Trash 用户文件。",
    ] {
        assert_contains(CORE_API, fragment);
    }
}

#[test]
fn manual_rescan_documents_consumers_scope_and_side_effect_boundaries() {
    for fragment in [
        "Windows/Linux watcher 页的 rescan 必须先进入本确认页。",
        "显示将要重扫的 repo 路径、预计范围和原因。",
        "`Scope: entire repository`",
        "确认前必须看到 dry-run 影响预览。",
        "页面明确说明不移动、不删除、不覆盖用户文件。",
        "成功结果显示新增、更新、缺失、冲突、不可读、跳过数量。",
        "rescan summary 可审计",
        "本页不承诺撤回 Core 已提交的索引更新",
    ] {
        assert_contains(RESCAN_CONFIRM_PAGE, fragment);
    }

    for fragment in [
        "提供 `Run rescan now` 入口，但点击后必须先进入 `S4-X-07 rescan-confirm`。",
        "禁用条件：repo path missing、DB locked、已有 rescan 运行",
    ] {
        assert_contains(WIN_WATCHER_PAGE, fragment);
        assert_contains(LNX_WATCHER_PAGE, fragment);
    }
    assert_contains(
        WIN_WATCHER_PAGE,
        "Rescan running：显示进度，不允许并发启动第二次 rescan。",
    );
    assert_contains(LNX_WATCHER_PAGE, "Rescan running：禁用再次 rescan。");

    for fragment in [
        "C4-19 also uses this entry point for Windows/Linux manual rescan after",
        "S4-X-07 has shown the high-risk confirmation",
        "The C4-19 scope is the entire repository",
        "partial subtree rescan and preview/dry-run APIs are not exposed",
        "Consumers combine the returned [`ReindexReport`] with",
        "[`get_latest_scan_session`] to render the rescan summary",
        "C4-19 consumers use the same read-only session contract",
        "display manual rescan progress, completion, failure, interruption, and retry state",
        "resumes an interrupted or failed entire-repository manual rescan",
        "must not bypass confirmation, start a concurrent rescan, or expose",
    ] {
        assert_contains_normalized(API_RS, fragment);
    }

    for fragment in [
        "C4-19 manual rescan consumers use this as the post-confirmation summary",
        "entire-repository scan",
        "keeps detailed preview and review classification out of the report",
        "C4-19 manual rescan consumers use `kind`, `status`, counters, timestamps",
        "without parsing logs or inspecting user files",
    ] {
        assert_contains_normalized(DOMAIN_RS, fragment);
    }

    for fragment in [
        "C4-19 manual-rescan reuses the full repository reindex entry point",
        "The scope is the entire repository",
        "partial subtree rescan and dry-run preview are not exposed",
        "must not",
        "move, delete, rename, overwrite, trash, or download user files",
        "C4-19 consumers read the latest scan session",
        "C4-19 resumes an interrupted or failed whole-repository manual rescan",
    ] {
        assert_contains_normalized(UDL, fragment);
    }

    for error_name in ["PermissionDenied", "Db", "Io"] {
        assert_contains(CAPABILITY_SPEC, error_name);
        assert_contains(ERROR_CODES, error_name);
        assert_contains(API_RS, error_name);
        assert_contains(UDL, error_name);
    }

    for out_of_scope in ["record_watcher_health", "sync_external_changes", "replace"] {
        assert!(
            !CAPABILITY_SPEC.contains(out_of_scope),
            "C4-19 spec should not expose `{out_of_scope}`"
        );
    }
}
