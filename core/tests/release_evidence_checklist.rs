const CHECKLIST: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/release-checklist.md");
const RELEASE: &str = include_str!("../../docs/development/release.md");
const BUILD: &str = include_str!("../../docs/development/build.md");
const CI_GOVERNANCE: &str = include_str!("../../docs/development/ci-governance.md");
const CHANGELOG: &str = include_str!("../../CHANGELOG.md");
const PERFORMANCE_BASELINE: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/performance-baseline.md");
const RECOVERY_SCENARIOS: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/recovery-scenarios.md");
const TESTING: &str = include_str!("../../docs/development/testing.md");
const RELEASE_NOTES_010: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/release-notes/release-notes-0.1.0.md");
const RELEASE_NOTES_PREVIEW_010: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/release-notes/release-notes-v0.1.0-unnotarized-preview.2.md");
const ALPHA_FEEDBACK_ROUTE: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/alpha-feedback-route.md");
const ALPHA_FEEDBACK_TEMPLATE: &str =
    include_str!("../../.github/ISSUE_TEMPLATE/alpha_feedback.md");
const CARGO_TOML: &str = include_str!("../Cargo.toml");
const XCODE_PROJECT: &str = include_str!("../../apps/macos/AreaMatrix.xcodeproj/project.pbxproj");
const CHECKPOINT_GAPS: &str =
    include_str!("../../workflow/versions/v1-mvp/closeout/checkpoint-gaps.md");
const CHECKPOINT_ACCEPTED_EXCEPTIONS: &str =
    include_str!("../../workflow/versions/v1-mvp/closeout/checkpoint-accepted-exceptions.md");
const CLOSEOUT_YAML: &str = include_str!("../../workflow/versions/v1-mvp/closeout/closeout.yaml");
const V1_RESIDUALS: &str = include_str!("../../workflow/versions/v1-mvp/residuals/residuals.yaml");
const TASK05_RUNNING_SUMMARY: &str = include_str!(
    "../../workflow/versions/v1-mvp/evidence/task-loop-runs/20260510_223424/summary.json"
);

// Archived v1 evidence strings intentionally preserve old distribution-track
// wording. Current long-lived docs are checked below to keep those terms out.
const ARCHIVED_DISTRIBUTION_READINESS: &[&str] = &[
    "当前结论：**不放行 Stage 1 alpha 分发**",
    "最终集成验收：**不放行**",
    "不得标记为可 alpha 分发",
    "`v0.1.0-unnotarized-preview.2`：**可作为 GitHub prerelease 提供给可信测试者**",
    "不代表正式 Stage 1 alpha 可分发",
    "P1-RL-001",
    "P1-RL-002",
    "P1-RL-003",
    "P1-RL-004",
    "P1-RL-005",
];

const ARCHIVED_DISTRIBUTION_TERMS_FORBIDDEN_IN_ACTIVE_DOCS: &[&str] = &[
    "local-qa",
    "local QA build",
    "local QA DMG",
    "unnotarized-preview",
    "GitHub prerelease",
    "--prerelease",
    "Stage 1 alpha",
    "Stage 2",
];

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected release checklist evidence to contain `{needle}`"
    );
}

fn assert_not_contains(haystack: &str, needle: &str) {
    assert!(
        !haystack.contains(needle),
        "expected active release docs not to contain `{needle}`"
    );
}

fn assert_all_contains(haystack: &str, needles: &[&str]) {
    for needle in needles {
        assert_contains(haystack, needle);
    }
}

#[test]
fn release_checklist_answers_archived_distribution_readiness() {
    assert_all_contains(CHECKLIST, ARCHIVED_DISTRIBUTION_READINESS);
}

#[test]
fn release_checklist_tracks_required_gate_statuses() {
    assert_all_contains(
        CHECKLIST,
        &[
            "通过",
            "不通过",
            "不适用",
            "无法验证",
            "CI / check-all",
            "P0 / P1",
            "手工冒烟",
            "性能基线",
            "依赖 dry-run",
            "文档 / API 一致性",
            "CHANGELOG",
            "版本号",
            "签名",
            "公证",
            "DMG",
            "干净 Mac 首启",
            "已知问题",
            "反馈渠道",
        ],
    );
}

#[test]
fn release_checklist_records_validation_closure_from_current_environment() {
    assert_contains(CHECKLIST, "2026-05-11 00:31 CST");
    assert_contains(CHECKLIST, "`./dev check all` 已完整通过");
    assert_contains(CHECKLIST, "universal Core build");
    assert_contains(CHECKLIST, "SwiftFormat 和 SwiftLint 均通过");
    assert_contains(CHECKLIST, "0/226 files require formatting, 3 files skipped");
    assert_contains(CHECKLIST, "Found 0 violations, 0 serious in 228 files");
    assert_contains(CHECKLIST, "本地 check-all 已完整通过");
    assert_contains(CHECKLIST, "依赖 dry-run 已补证");
    assert_contains(CHECKLIST, "cargo update --dry-run");
    assert_contains(CHECKLIST, "not updating lockfile due to dry run");
    assert_contains(BUILD, "missing Rust target 'x86_64-apple-darwin'");
    assert_contains(BUILD, "rustup target add x86_64-apple-darwin");
    assert_contains(BUILD, "static.rust-lang.org");
    assert_contains(BUILD, "Homebrew prefix 与 cache 可写");
    assert_contains(BUILD, "swiftformat");
    assert_contains(BUILD, "swiftlint");
}

#[test]
fn release_checklist_records_current_macos_xctest_evidence_without_release_claim() {
    assert_contains(CHECKLIST, "macOS XCTest");
    assert_contains(CHECKLIST, "`./dev test macos`");
    assert_contains(CHECKLIST, "TEST SUCCEEDED");
    assert_contains(CHECKLIST, "ImportBatchCopyImportModelTests");
    assert_contains(CHECKLIST, "ImportProgressCopyQueueRecoveryTests");
    assert_contains(CHECKLIST, "5 个 `AreaMatrixPerfTests` 全部通过");
    assert_contains(CHECKLIST, "不能替代 Developer ID 签名");
    assert_contains(PERFORMANCE_BASELINE, "2026-05-10 18:12:15 CST");
    assert_contains(PERFORMANCE_BASELINE, "81.355 ms");
    assert_contains(PERFORMANCE_BASELINE, "1,043.521 ms");
    assert_contains(PERFORMANCE_BASELINE, "180.109 MB");
    assert_contains(PERFORMANCE_BASELINE, "真实 `.app` 启动到首屏 release gate");
    assert_contains(PERFORMANCE_BASELINE, "777.606 ms");
    assert_contains(PERFORMANCE_BASELINE, "当前没有 P1 性能 release 阻断项");
}

#[test]
fn release_checklist_records_distribution_preflight_blocker_without_release_claim() {
    assert_contains(CHECKLIST, "2026-07-06 `./dev release preflight`");
    assert_contains(CHECKLIST, "`./dev release preflight`");
    assert_contains(RELEASE, "./dev release status --json --remote");
    assert_contains(RELEASE, "./dev release evidence-audit --json");
    assert_contains(
        RELEASE,
        "不创建 tag、发布产物、关闭 residual 或完成外部验证",
    );
    assert_contains(
        RELEASE,
        "Developer ID 签名、公证、staple、Gatekeeper 和干净 Mac 首启证据齐全",
    );
    assert_contains(RELEASE, "xcrun notarytool submit");
    assert_contains(RELEASE, "xcrun stapler staple");
    assert_contains(RELEASE, "干净 Mac");
    assert_contains(RELEASE, "Developer ID identity");
    assert_contains(
        BUILD,
        "Developer ID 签名、公证、DMG、checksum 和干净 Mac 首启验证",
    );
    assert_contains(BUILD, "状态、审计和产物探针只用于汇总或读取证据");
    assert_contains(
        CI_GOVERNANCE,
        "发布状态、证据审计、签名、公证、DMG 和外部测试属于发布门禁",
    );
    assert_contains(CI_GOVERNANCE, "不是普通 PR 的 CI 结果");
    assert_contains(
        CHECKLIST,
        "no valid Developer ID Application signing identity found",
    );
    assert_contains(
        CHECKLIST,
        "`AC_PASSWORD` notarytool keychain profile 不可用",
    );
    assert_contains(CHECKLIST, "当前无付费 Apple Developer Program");
    assert_contains(CHECKLIST, "local QA build");
    assert_contains(CHECKLIST, "不能替代 Developer ID codesign");
    assert_contains(CHECKLIST, "Developer ID codesign");
    assert_contains(CHECKLIST, "notarytool accepted log");
    assert_contains(CHECKLIST, "DMG checksum");
    assert_contains(
        CHECKLIST,
        "`distribution_requirements.status` 在正式证据不足时仍为 `blocked`",
    );
    assert_contains(CHECKLIST, "默认不执行完整 DMG SHA-256 读取");
    assert_contains(
        RELEASE_NOTES_010,
        "`./dev release preflight` 已补为可复现预检",
    );
    assert_contains(RELEASE_NOTES_010, "只能证明环境 blocked");
    assert_contains(RELEASE_NOTES_010, "不能替代可分发产物");
    assert_contains(RELEASE_NOTES_010, "未加入付费");
    assert_contains(RELEASE_NOTES_010, "# AreaMatrix 0.1.0-local-qa");
    assert_contains(
        RELEASE_NOTES_010,
        "No formal `v0.1.0` tag or GitHub Release has been created for this local QA artifact.",
    );
    assert_contains(
        RELEASE_NOTES_PREVIEW_010,
        "# AreaMatrix 0.1.0 Unnotarized Preview 2",
    );
    assert_contains(RELEASE_NOTES_PREVIEW_010, "not Developer ID signed");
    assert_contains(RELEASE_NOTES_PREVIEW_010, "has not been notarized");
    assert_contains(RELEASE_NOTES_PREVIEW_010, "trusted tester preview");
    assert_contains(CHANGELOG, "未加入付费 Apple Developer Program");
}

#[test]
fn active_release_docs_do_not_reintroduce_v1_distribution_tracks() {
    for active_doc in [RELEASE, BUILD] {
        for stale_term in ARCHIVED_DISTRIBUTION_TERMS_FORBIDDEN_IN_ACTIVE_DOCS {
            assert_not_contains(active_doc, stale_term);
        }
    }

    assert_contains(RELEASE, "workflow/versions/README.md");
    assert_contains(RELEASE, "历史发布记录和未关闭外部条件");
    assert_contains(BUILD, "历史记录通过 [workflow versions]");
}

#[test]
fn release_checklist_records_local_qa_artifact_without_alpha_claim() {
    assert_contains(CHECKLIST, "`0.1.0-local-qa`：**可用于内部测试**");
    assert_contains(CHECKLIST, "Stage 1 alpha 可分发");
    assert_contains(CHECKLIST, "Signature=adhoc");
    assert_contains(CHECKLIST, "TeamIdentifier=not set");
    assert_contains(CHECKLIST, "Runtime Version=26.2.0");
    assert_contains(
        CHECKLIST,
        "workflow/versions/v1-mvp/evidence/artifacts/AreaMatrix-0.1.0-local-qa.dmg",
    );
    assert_contains(
        CHECKLIST,
        "4e52b8e648326aaf3731fc61f12f4d576bbeeeff7a521d0efe528eec032c617b",
    );
    assert_contains(
        CHECKLIST,
        "applicationLaunchToFirstScreen.localQA.dmgConfiguredRepo",
    );
    assert_contains(CHECKLIST, "668.973 ms < 1.5s");
    assert_contains(CHECKLIST, "同机 local QA 首启交互 smoke");
    assert_contains(
        CHECKLIST,
        "AppleScript 返回 `true, 60, 50, 1500, 980, AreaMatrix`",
    );
    assert_contains(CHECKLIST, "scroll_probe=posted events=7 point=900,610");
    assert_contains(CHECKLIST, "pending，不创建");
    assert_contains(RELEASE_NOTES_010, "Internal QA date: 2026-05-11");
    assert_contains(RELEASE_NOTES_010, "internal local QA artifact");
    assert_contains(RELEASE_NOTES_010, "同机 local QA 首启交互 smoke 已通过");
    assert_contains(CHANGELOG, "v1 分发证据归档中的内部验证产物");
    assert_contains(CHANGELOG, "内部验证说明，不再暗示正式分发");
}

#[test]
fn release_checklist_records_unnotarized_preview_without_alpha_claim() {
    assert_contains(CHECKLIST, "未公证预览 DMG");
    assert_contains(CHECKLIST, "v0.1.0-unnotarized-preview.2");
    assert_contains(CHECKLIST, "GitHub prerelease");
    assert_contains(CHECKLIST, "可信测试者");
    assert_contains(CHECKLIST, "prerelease only");
    assert_contains(CHECKLIST, "202606161707");
    assert_contains(
        CHECKLIST,
        "1a4881522acb93282cb6e0252810ea3849c7ab1095e74b8583a40e8018f28aea",
    );
    assert_contains(
        CHECKLIST,
        "d01d44c82e2287c0f1cd12aea4e78ece46301fe2f4709b2598c5710ba89864b2",
    );
    assert_contains(CHECKLIST, "Runtime Version=26.4.0");
    assert_contains(CHECKLIST, "TeamIdentifier=not set");
    assert_contains(CHECKLIST, "不能替代正式 alpha");
    assert_contains(
        RELEASE_NOTES_PREVIEW_010,
        "Do not disable Gatekeeper globally.",
    );
    assert_contains(RELEASE_NOTES_PREVIEW_010, "Signature=adhoc");
    assert_contains(RELEASE_NOTES_PREVIEW_010, "TeamIdentifier=not set");
    assert_contains(
        RELEASE_NOTES_PREVIEW_010,
        "This prerelease does not close P1-RL-003",
    );
    assert_contains(CHANGELOG, "未公证测试者预览产物");
    assert_contains(CHANGELOG, "不是正式分发");
}

#[test]
fn release_checklist_keeps_release_build_and_archive_docs_aligned() {
    assert_contains(RELEASE, "workflow/versions/README.md");
    assert_contains(RELEASE, "历史发布记录和未关闭外部条件");
    assert_contains(BUILD, "## 发布构建");
    assert_contains(BUILD, "workflow/versions/README.md");
    assert_contains(BUILD, "历史记录通过 [workflow versions]");
    assert!(
        !BUILD.contains("发布构建（Stage 2 起激活）"),
        "build.md must not contradict archived v1 alpha release gates"
    );
}

#[test]
fn release_checklist_cites_existing_blocker_evidence() {
    assert_contains(PERFORMANCE_BASELINE, "真实 `.app` 启动到首屏 release 证据");
    assert_contains(PERFORMANCE_BASELINE, "当前没有 P1 性能 release 阻断项");
    assert_contains(RECOVERY_SCENARIOS, "manual_evidence_status: pending");
    assert_contains(RECOVERY_SCENARIOS, "manual_evidence_status: pass");
    assert_contains(RECOVERY_SCENARIOS, "manual_evidence_status: blocked");
    assert_contains(RECOVERY_SCENARIOS, "Stage 1 发布不通过");
    assert_contains(TESTING, "## 手工冒烟清单");
    assert_contains(CHECKLIST, "真实 Release `.app` 启动到首屏证据已补齐");
    assert_contains(CHECKLIST, "M-01 Copy 中断恢复手工证据已通过");
    assert_contains(
        CHECKLIST,
        "M-02 因当前没有 iCloud placeholder 环境而 blocked",
    );
    assert_contains(CHECKLIST, "./dev release icloud-placeholder-evidence");
    assert_contains(CHECKLIST, "默认脱敏的 `lstat` / `mdls` metadata draft");
    assert_contains(CHECKLIST, "不能触发 download 或替代真实 UI retry");
    assert_contains(
        CHECKLIST,
        "./dev release icloud-placeholder-smoke-audit --json",
    );
    assert_contains(CHECKLIST, "`smoke_evidence_gate: BLOCKED`");
    assert_contains(CHECKLIST, "不触发下载 / 读内容 / 写 DB / 写 `.areamatrix/`");
    assert_contains(
        RECOVERY_SCENARIOS,
        "mode: icloud_placeholder_metadata_probe",
    );
    assert_contains(RECOVERY_SCENARIOS, "residual_id: v1-rl-002");
    assert_contains(RECOVERY_SCENARIOS, "closes_residual: false");
    assert_contains(
        RECOVERY_SCENARIOS,
        "blocked_until_real_icloud_download_retry_and_db_evidence_pass",
    );
    assert_contains(RECOVERY_SCENARIOS, "privacy.path_redaction: true");
    assert_contains(RECOVERY_SCENARIOS, "`--include-sensitive-paths`");
    assert_contains(RECOVERY_SCENARIOS, "`download_attempted`");
    assert_contains(RECOVERY_SCENARIOS, "`file_content_read_attempted`");
    assert_contains(RECOVERY_SCENARIOS, "`db_write_attempted`");
    assert_contains(
        RECOVERY_SCENARIOS,
        "对 symlink 只做 `lstat`，不跟随目标执行 `mdls`",
    );
    assert_contains(RECOVERY_SCENARIOS, "不能替代 UI\n    `Download & retry`");
    assert_contains(
        RECOVERY_SCENARIOS,
        "./dev release icloud-placeholder-smoke-audit --json",
    );
    assert_contains(RECOVERY_SCENARIOS, "`smoke_evidence_gate: BLOCKED`");
    assert_contains(RECOVERY_SCENARIOS, "不接收路径、不运行 `mdls`、不触发");
    assert_contains(CHECKLIST, "M-03 权限恢复手工证据已通过");
    assert_contains(CHECKLIST, "Repository needs permission");
    assert_contains(CHECKLIST, "PermissionDenied");
    assert_contains(CHECKLIST, "Reconnect folder");
    assert_contains(CHECKLIST, "未修改系统 TCC 数据库");
    assert_contains(CHECKLIST, "M-04 DB repair 手工证据已通过");
    assert_contains(CHECKLIST, "DB `PRAGMA integrity_check` 返回 `ok`");
    assert_contains(CHECKLIST, "用户文件 checksum 不变");
    assert_contains(CHECKLIST, "根目录未生成 `AREAMATRIX.md`");
}

#[test]
fn release_checklist_records_changelog_and_version_state_without_claiming_release() {
    assert_contains(CHANGELOG, "## [Unreleased]");
    assert_contains(CHANGELOG, "## [0.1.0] - 2026-05-10");
    assert_contains(CHANGELOG, "拆分批量导入执行和 session persistence 代码");
    assert_contains(CHANGELOG, "### Known Issues");
    assert_contains(RELEASE_NOTES_010, "# AreaMatrix 0.1.0-local-qa");
    assert_contains(
        RELEASE_NOTES_PREVIEW_010,
        "# AreaMatrix 0.1.0 Unnotarized Preview 2",
    );
    assert_contains(RELEASE_NOTES_010, "Validation Snapshot");
    assert_contains(RELEASE_NOTES_PREVIEW_010, "Validation Snapshot");
    assert_contains(RELEASE_NOTES_010, "Known Issues");
    assert_contains(RELEASE_NOTES_PREVIEW_010, "Known Issues");
    assert_contains(CHECKLIST, "`CHANGELOG.md` 已切出 `[0.1.0] - 2026-05-10`");
    assert_contains(CHECKLIST, "`workflow/versions/v1-mvp/evidence/release-notes/release-notes-v0.1.0-unnotarized-preview.2.md`");
    assert_contains(CARGO_TOML, "version = \"0.1.0\"");
    assert_contains(XCODE_PROJECT, "MARKETING_VERSION = 0.1.0");
    assert_contains(XCODE_PROJECT, "CURRENT_PROJECT_VERSION = 202605101812");
    assert_contains(CHECKLIST, "build `202606161707`");
    assert_contains(CHECKLIST, "正式 `v0.1.0` tag 尚未创建");
    assert_contains(CHECKLIST, "`ready_to_create_formal_tag: false`");
    assert_contains(
        CHECKLIST,
        "`./dev release final-tag-readiness-audit --json --remote`",
    );
    assert_contains(CHECKLIST, "不得把它当作正式 `v0.1.0` release tag");
}

#[test]
fn alpha_feedback_template_collects_release_review_fields_without_closing_decision() {
    assert_contains(ALPHA_FEEDBACK_TEMPLATE, "name: Alpha Feedback");
    assert_contains(
        ALPHA_FEEDBACK_TEMPLATE,
        "labels: [\"alpha-feedback\", \"needs-triage\"]",
    );
    assert_contains(ALPHA_FEEDBACK_TEMPLATE, "## 测试版本 / Build");
    assert_contains(ALPHA_FEEDBACK_TEMPLATE, "AreaMatrix 版本 / Version");
    assert_contains(ALPHA_FEEDBACK_TEMPLATE, "构建号 / Build");
    assert_contains(ALPHA_FEEDBACK_TEMPLATE, "DMG SHA-256");
    assert_contains(ALPHA_FEEDBACK_TEMPLATE, "## 测试环境 / Environment");
    assert_contains(ALPHA_FEEDBACK_TEMPLATE, "macOS 版本 / macOS version");
    assert_contains(
        ALPHA_FEEDBACK_TEMPLATE,
        "是否为干净用户或干净 Mac / Clean user or clean Mac",
    );
    assert_contains(
        ALPHA_FEEDBACK_TEMPLATE,
        "是否在 iCloud Drive / In iCloud Drive",
    );
    assert_contains(ALPHA_FEEDBACK_TEMPLATE, "iCloud placeholder");
    assert_contains(
        ALPHA_FEEDBACK_TEMPLATE,
        "## 数据安全确认 / Data Safety Check",
    );
    assert_contains(ALPHA_FEEDBACK_TEMPLATE, "用户文件");
    assert_contains(ALPHA_FEEDBACK_TEMPLATE, ".areamatrix/");
    assert_contains(ALPHA_FEEDBACK_TEMPLATE, "DB、staging 或索引损坏");

    assert_contains(CHECKLIST, "Alpha feedback issue template 已存在");
    assert_contains(CHECKLIST, "alpha-feedback-route.md");
    assert_contains(
        CHECKLIST,
        "`./dev release alpha-feedback-decision-audit --json` 已提供只读决策审计",
    );
    assert_contains(CHECKLIST, "`decision_audit.decision_gate: BLOCKED`");
    assert_contains(
        CHECKLIST,
        "trusted tester list、tester invitation、release announcement / Discussion 链接、feedback route 和 triage owner",
    );
    assert_contains(
        CHECKLIST,
        "可信测试者名单来源、tester invitation side effect、正式公告或 Discussion 链接、备用反馈路线、triage owner 和响应 SLO 决策仍未记录",
    );

    assert_contains(ALPHA_FEEDBACK_ROUTE, "当前结论：**不关闭 `v1-rl-006`**");
    assert_contains(
        ALPHA_FEEDBACK_ROUTE,
        "./dev release alpha-feedback-decision-audit --json",
    );
    assert_contains(ALPHA_FEEDBACK_ROUTE, "decision_audit:");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "decision_gate: BLOCKED");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "alpha_feedback_release_decision");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "closes_residual: false");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "trusted_tester_list.status: pending");
    assert_contains(
        ALPHA_FEEDBACK_ROUTE,
        "decision_side_effects.testers_invited: false",
    );
    assert_contains(ALPHA_FEEDBACK_ROUTE, "announcement.status: pending");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "feedback_route.status: pending");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "triage_owner.status: pending");
    assert_contains(
        ALPHA_FEEDBACK_ROUTE,
        "不能由 local QA、未公证预览 DMG、issue template、自动化测试或同机",
    );
}

#[test]
fn task05_incomplete_summary_is_not_release_evidence_pass() {
    assert_contains(TASK05_RUNNING_SUMMARY, "\"run_id\": \"20260510_223424\"");
    assert_contains(TASK05_RUNNING_SUMMARY, "\"status\": \"running\"");
    assert_contains(TASK05_RUNNING_SUMMARY, "\"3-1/task-05\"");
    assert_contains(TASK05_RUNNING_SUMMARY, "\"status\": \"in_progress\"");
    assert_contains(
        TASK05_RUNNING_SUMMARY,
        ".codex/task-loop-logs/20260510_223424/phase-3/3-1-task-05-copy-attempt-2.log",
    );
    assert_contains(
        TASK05_RUNNING_SUMMARY,
        ".codex/task-loop-logs/20260510_223424/phase-3/3-1-task-05-verify-attempt-2.log",
    );
    assert_not_contains(TASK05_RUNNING_SUMMARY, "VERIFY_RESULT: PASS");

    assert_contains(
        CHECKPOINT_GAPS,
        "must not be counted as `VERIFY_RESULT: PASS` evidence",
    );
    assert_contains(
        CHECKPOINT_ACCEPTED_EXCEPTIONS,
        "does not count as `VERIFY_RESULT: PASS`",
    );
    assert_contains(
        CHECKPOINT_ACCEPTED_EXCEPTIONS,
        "must not close a release evidence blocker",
    );
    assert_contains(
        CLOSEOUT_YAML,
        "task05_tracked_incomplete_summaries_excluded_from_pass: 5",
    );
    assert_contains(
        CLOSEOUT_YAML,
        "do not count running/in_progress task-loop summaries",
    );
    assert_contains(
        V1_RESIDUALS,
        "cannot count as VERIFY_RESULT PASS and cannot close release evidence blockers",
    );
}

#[test]
fn release_checklist_rollback_scope_stays_inside_task_expected_paths() {
    for path in [
        "`workflow/versions/v1-mvp/evidence/release-checklist.md`",
        "`workflow/versions/v1-mvp/evidence/icloud-placeholder-smoke-evidence.md`",
        "`workflow/versions/v1-mvp/evidence/release-gate-review-task05.md`",
        "`workflow/versions/v1-mvp/evidence/distribution-signing-notarization.md`",
        "`workflow/versions/v1-mvp/evidence/final-tag-release-evidence.md`",
        "`workflow/versions/v1-mvp/evidence/alpha-feedback-route.md`",
        "`workflow/versions/v1-mvp/residuals/README.md`",
        "`workflow/versions/v1-mvp/residuals/release-evidence.md`",
        "`workflow/versions/v1-mvp/residuals/residuals.yaml`",
        "`workflow/residuals/README.md`",
        "`tasks/indexes/residuals.md`",
        "`core/tests/release_evidence_checklist.rs`",
        "`core/tests/release_evidence_residual_records.rs`",
        "`docs/development/release.md`",
        "`docs/development/build.md`",
        "`docs/development/ci-governance.md`",
    ] {
        assert_contains(CHECKLIST, path);
    }

    for out_of_scope in ["Core API", "UDL", "DB", "用户文件"] {
        assert_contains(CHECKLIST, out_of_scope);
    }
}
