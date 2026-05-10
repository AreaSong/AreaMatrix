const CHECKLIST: &str = include_str!("../../docs/development/stage-1-release-checklist.md");
const RELEASE: &str = include_str!("../../docs/development/release.md");
const BUILD: &str = include_str!("../../docs/development/build.md");
const STAGE1_MVP: &str = include_str!("../../docs/roadmap/stage-1-mvp.md");
const CHANGELOG: &str = include_str!("../../CHANGELOG.md");
const PERFORMANCE_BASELINE: &str =
    include_str!("../../docs/development/stage-1-performance-baseline.md");
const RECOVERY_SCENARIOS: &str = include_str!("../../docs/development/recovery-scenarios.md");
const TESTING: &str = include_str!("../../docs/development/testing.md");
const RELEASE_NOTES_010: &str = include_str!("../../release-notes-0.1.0.md");
const CARGO_TOML: &str = include_str!("../Cargo.toml");
const XCODE_PROJECT: &str = include_str!("../../apps/macos/AreaMatrix.xcodeproj/project.pbxproj");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected release checklist evidence to contain `{needle}`"
    );
}

fn assert_all_contains(haystack: &str, needles: &[&str]) {
    for needle in needles {
        assert_contains(haystack, needle);
    }
}

#[test]
fn release_checklist_answers_alpha_distribution_readiness() {
    assert_all_contains(
        CHECKLIST,
        &[
            "当前结论：**不放行 Stage 1 alpha 分发**",
            "最终集成验收：**不放行**",
            "不得标记为可 alpha 分发",
            "P1-RL-001",
            "P1-RL-002",
            "P1-RL-003",
            "P1-RL-004",
            "P1-RL-005",
        ],
    );
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
    assert_contains(CHECKLIST, "2026-05-10 18:30 CST");
    assert_contains(CHECKLIST, "`./dev release preflight`");
    assert_contains(RELEASE, "`./dev release preflight` 通过");
    assert_contains(BUILD, "release distribution");
    assert_contains(BUILD, "preflight: BLOCKED");
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
    assert_contains(RELEASE, "Developer ID / notarization 后续补证");
    assert_contains(RELEASE, "`./dev release preflight` 通过");
    assert_contains(RELEASE, "xcrun notarytool submit");
    assert_contains(RELEASE, "xcrun stapler staple");
    assert_contains(RELEASE, "干净 Mac 上首次打开通过 Gatekeeper");
    assert_contains(RELEASE, "不付费 local QA build");
    assert_contains(RELEASE, "不能关闭");
    assert_contains(RELEASE, "P1-RL-003");
    assert_contains(RELEASE, "0.1.0-local-qa");
    assert_contains(RELEASE, "Signature=adhoc");
    assert_contains(RELEASE, "TeamIdentifier=not set");
    assert_contains(RELEASE, "不创建 `v0.1.0` tag");
    assert_contains(BUILD, "不付费 local QA 构建");
    assert_contains(BUILD, "CODE_SIGN_IDENTITY=-");
    assert_contains(BUILD, "AreaMatrix-0.1.0-local-qa.dmg");
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
        "No `v0.1.0` tag or GitHub Release has been created.",
    );
    assert_contains(CHANGELOG, "未加入付费 Apple Developer Program");
}

#[test]
fn release_checklist_records_local_qa_artifact_without_alpha_claim() {
    assert_contains(CHECKLIST, "`0.1.0-local-qa`：**可用于内部测试**");
    assert_contains(CHECKLIST, "Stage 1 alpha 可分发");
    assert_contains(CHECKLIST, "Signature=adhoc");
    assert_contains(CHECKLIST, "TeamIdentifier=not set");
    assert_contains(CHECKLIST, "Runtime Version=26.2.0");
    assert_contains(CHECKLIST, "AreaMatrix-0.1.0-local-qa.dmg");
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
    assert_contains(RELEASE, "不得写成干净 Mac 首启");
    assert_contains(BUILD, "不能证明干净 Mac 首启");
    assert_contains(CHECKLIST, "pending，不创建");
    assert_contains(RELEASE_NOTES_010, "Internal QA date: 2026-05-11");
    assert_contains(RELEASE_NOTES_010, "internal local QA artifact");
    assert_contains(RELEASE_NOTES_010, "同机 local QA 首启交互 smoke 已通过");
    assert_contains(CHANGELOG, "0.1.0-local-qa");
}

#[test]
fn release_checklist_keeps_release_build_and_stage_one_docs_aligned() {
    assert_contains(RELEASE, "stage-1-release-checklist.md");
    assert_contains(RELEASE, "不得放行最终集成验收");
    assert_contains(BUILD, "发布构建（Stage 1 alpha 起激活）");
    assert_contains(BUILD, "stage-1-release-checklist.md");
    assert!(
        !BUILD.contains("发布构建（Stage 2 起激活）"),
        "build.md must not contradict Stage 1 alpha release gates"
    );
    assert_all_contains(
        STAGE1_MVP,
        &[
            "准备 alpha 分发",
            "0.1.0 内测版可下载（DMG，已签名 + 公证）",
            "DMG 可在干净 Mac 上首次启动成功",
        ],
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
    assert_contains(RELEASE_NOTES_010, "Validation Snapshot");
    assert_contains(RELEASE_NOTES_010, "Known Issues");
    assert_contains(CHECKLIST, "`CHANGELOG.md` 已切出 `[0.1.0] - 2026-05-10`");
    assert_contains(CHECKLIST, "`release-notes-0.1.0.md`");
    assert_contains(CARGO_TOML, "version = \"0.1.0\"");
    assert_contains(XCODE_PROJECT, "MARKETING_VERSION = 0.1.0");
    assert_contains(XCODE_PROJECT, "CURRENT_PROJECT_VERSION = 202605101812");
    assert_contains(
        CHECKLIST,
        "Xcode `CURRENT_PROJECT_VERSION` 已更新为 `202605101812`",
    );
    assert_contains(CHECKLIST, "当前工作区尚未提交，因此未创建 `v0.1.0` tag");
    assert_contains(CHECKLIST, "不得在未提交 release candidate 上提前打 tag");
}

#[test]
fn release_checklist_rollback_scope_stays_inside_task_expected_paths() {
    for path in [
        "`docs/development/stage-1-release-checklist.md`",
        "`core/tests/stage1_release_checklist.rs`",
        "`docs/development/release.md`",
        "`docs/development/build.md`",
    ] {
        assert_contains(CHECKLIST, path);
    }

    for out_of_scope in ["Core API", "UDL", "DB", "用户文件"] {
        assert_contains(CHECKLIST, out_of_scope);
    }
}
