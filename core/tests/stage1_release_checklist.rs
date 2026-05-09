const CHECKLIST: &str = include_str!("../../docs/development/stage-1-release-checklist.md");
const RELEASE: &str = include_str!("../../docs/development/release.md");
const BUILD: &str = include_str!("../../docs/development/build.md");
const STAGE1_MVP: &str = include_str!("../../docs/roadmap/stage-1-mvp.md");
const CHANGELOG: &str = include_str!("../../CHANGELOG.md");
const PERFORMANCE_BASELINE: &str =
    include_str!("../../docs/development/stage-1-performance-baseline.md");
const RECOVERY_SCENARIOS: &str = include_str!("../../docs/development/recovery-scenarios.md");
const TESTING: &str = include_str!("../../docs/development/testing.md");
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
            "不得\n标记为可 alpha 分发",
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
fn release_checklist_records_validation_blockers_from_current_environment() {
    assert_contains(
        CHECKLIST,
        "macOS checks 在构建前因缺少 `uniffi-bindgen` 停止",
    );
    assert_contains(CHECKLIST, "缺少根 `Cargo.toml`");
    assert_contains(CHECKLIST, "无法解析 `index.crates.io`");
    assert_contains(CHECKLIST, "check-all 未完整通过");
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
    assert_contains(
        PERFORMANCE_BASELINE,
        "真实 `.app` 启动到首屏 release 证据缺失",
    );
    assert_contains(PERFORMANCE_BASELINE, "P1 release 阻断项");
    assert_contains(RECOVERY_SCENARIOS, "manual_evidence_status: pending");
    assert_contains(RECOVERY_SCENARIOS, "Stage 1 发布不通过");
    assert_contains(TESTING, "## 手工冒烟清单");
    assert_contains(CHECKLIST, "真实 Release `.app` 启动到首屏证据缺失");
    assert_contains(CHECKLIST, "M-01..M-04 手工恢复冒烟均为 pending");
}

#[test]
fn release_checklist_records_changelog_and_version_state_without_claiming_release() {
    assert_contains(CHANGELOG, "## [Unreleased]");
    assert_contains(CHECKLIST, "`CHANGELOG.md` 仍停留在 `[Unreleased]`");
    assert_contains(CARGO_TOML, "version = \"0.1.0\"");
    assert_contains(XCODE_PROJECT, "MARKETING_VERSION = 0.1.0");
    assert_contains(
        CHECKLIST,
        "`core/Cargo.toml` 与 Xcode `MARKETING_VERSION` 当前为 `0.1.0`",
    );
    assert_contains(CHECKLIST, "release tag 未确认");
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
