use std::{fs, path::PathBuf};

use area_matrix_core::{
    get_platform_capabilities, CoreError, CoreResult, ErrorKind, PlatformCapabilities,
    PlatformCapabilityStatus, PlatformCapabilitySupport, PlatformId,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-84-c4-17-validation.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-17-platform-capabilities.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const TESTING_DOC: &str = include_str!("../../docs/development/testing.md");
const PLATFORM_DIFFERENCES_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-02-platform-differences.md");
const LOCAL_FOLDER_NOTICE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-LNX-03-local-folder-notice.md");
const REPOSITORY_SETTINGS_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-08-repository-settings.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const UDL: &str = include_str!("../area_matrix.udl");
const API_RS: &str = include_str!("../src/api.rs");
const PLATFORM_CAPABILITIES_RS: &str = include_str!("../src/platform_capabilities.rs");
const CONTRACT_TEST: &str = include_str!("platform_capabilities_contract_api.rs");
const IMPLEMENTATION_TEST: &str = include_str!("platform_capabilities_implementation.rs");
const FAILURE_TEST: &str = include_str!("platform_capabilities_failure_recovery.rs");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

fn file_snapshot(paths: &[PathBuf]) -> Vec<(PathBuf, Vec<u8>)> {
    paths
        .iter()
        .map(|path| {
            (
                path.clone(),
                fs::read(path).expect("read validation file snapshot"),
            )
        })
        .collect()
}

fn assert_config_reason(error: CoreError, reason: &str) {
    assert_eq!(error.kind(), ErrorKind::Config);
    assert_eq!(error.raw_context(), reason);
    assert_eq!(error.to_error_mapping().raw_context, reason);
}

fn capability_rows(
    matrix: &PlatformCapabilities,
) -> [(&'static str, &PlatformCapabilitySupport); 5] {
    [
        ("watcher", &matrix.watcher),
        ("trash", &matrix.trash),
        ("share_extension", &matrix.share_extension),
        ("cloud_placeholder", &matrix.cloud_placeholder),
        ("security_bookmark", &matrix.security_bookmark),
    ]
}

fn assert_ui_ready_row_invariants(matrix: &PlatformCapabilities) {
    for (name, row) in capability_rows(matrix) {
        match row.status {
            PlatformCapabilityStatus::Available => {
                assert!(
                    row.ui_enabled,
                    "{name} available rows must enable dependent UI"
                );
                if row.requires_permission {
                    assert_non_empty_reason(name, row);
                }
            }
            PlatformCapabilityStatus::Limited => {
                assert_non_empty_reason(name, row);
            }
            PlatformCapabilityStatus::NotAvailable => {
                assert!(!row.ui_enabled, "{name} unavailable rows must disable UI");
                assert!(
                    !row.requires_permission,
                    "{name} unavailable rows must not request permission"
                );
                assert_non_empty_reason(name, row);
            }
            PlatformCapabilityStatus::Unknown => {
                assert!(!row.ui_enabled, "{name} unknown rows must not enable UI");
                assert_non_empty_reason(name, row);
            }
        }
    }
}

fn assert_non_empty_reason(name: &str, row: &PlatformCapabilitySupport) {
    assert!(
        row.reason
            .as_deref()
            .is_some_and(|reason| !reason.trim().is_empty()),
        "{name} row must expose a stable reason"
    );
}

#[test]
fn platform_capabilities_validation_proves_ui_ready_success_matrices() {
    let cases = [
        (PlatformId::Macos, "4.0.0-macos"),
        (PlatformId::Ios, "4.0.0-ios"),
        (PlatformId::Windows, "4.0.0-windows"),
        (PlatformId::Linux, "4.0.0-linux"),
    ];

    for (platform, version) in cases {
        let matrix = get_platform_capabilities(platform, version.to_owned()).expect("valid matrix");

        assert_eq!(matrix.platform, platform);
        assert_eq!(matrix.app_version, version);
        assert_ui_ready_row_invariants(&matrix);
    }

    let ios =
        get_platform_capabilities(PlatformId::Ios, "4.0.0-ios".to_owned()).expect("iOS matrix");
    assert_eq!(ios.watcher.status, PlatformCapabilityStatus::Limited);
    assert!(!ios.watcher.ui_enabled);
    assert_eq!(ios.trash.status, PlatformCapabilityStatus::NotAvailable);
    assert!(!ios.trash.ui_enabled);
    assert_eq!(
        ios.share_extension.status,
        PlatformCapabilityStatus::Available
    );

    let linux = get_platform_capabilities(PlatformId::Linux, "4.0.0-linux".to_owned())
        .expect("Linux matrix");
    assert_eq!(linux.watcher.status, PlatformCapabilityStatus::Available);
    assert_eq!(linux.trash.status, PlatformCapabilityStatus::Limited);
    assert!(linux.trash.ui_enabled);
    assert_eq!(
        linux.cloud_placeholder.status,
        PlatformCapabilityStatus::NotAvailable
    );
    assert!(!linux.cloud_placeholder.ui_enabled);
}

#[test]
fn platform_capabilities_validation_covers_failure_paths_without_side_effects() {
    let repo = tempfile::tempdir().expect("create validation repository");
    let readme = repo.path().join("README.md");
    let db_marker = repo.path().join(".areamatrix/index.db");
    fs::create_dir(repo.path().join(".areamatrix")).expect("create metadata marker directory");
    fs::write(&readme, b"user authored README").expect("write user README");
    fs::write(&db_marker, b"not a database").expect("write db marker");
    let before = file_snapshot(&[readme.clone(), db_marker.clone()]);

    for (platform, version, expected_reason) in [
        (PlatformId::Unknown, "4.0.0", "platform id is required"),
        (PlatformId::Macos, "", "app version is invalid"),
        (PlatformId::Ios, "   ", "app version is invalid"),
        (
            PlatformId::Windows,
            "4.0.0\napi_key=sk-secret",
            "app version is invalid",
        ),
        (PlatformId::Linux, "4.0.0/app", "app version is invalid"),
    ] {
        let error = get_platform_capabilities(platform, version.to_owned())
            .expect_err("invalid input must map to Config");
        assert_config_reason(error, expected_reason);
    }

    let error = get_platform_capabilities(PlatformId::Linux, "v".repeat(65))
        .expect_err("overlong app version must fail");
    assert_config_reason(error, "app version is invalid");

    assert_eq!(file_snapshot(&[readme, db_marker]), before);
    assert!(!repo.path().join("AREAMATRIX.md").exists());
    assert!(!repo.path().join(".areamatrix/generated").exists());
    assert!(!repo.path().join(".areamatrix/staging").exists());
}

#[test]
fn platform_capabilities_validation_locks_api_udl_rust_and_test_evidence() {
    fn assert_get(_: fn(PlatformId, String) -> CoreResult<PlatformCapabilities>) {}
    assert_get(get_platform_capabilities);

    assert_task_docs_and_testing_alignment();
    assert_core_api_udl_and_rust_alignment();
    assert_consumer_scope_alignment();
    assert_existing_test_layers_are_present();
}

fn assert_task_docs_and_testing_alignment() {
    for fragment in [
        "# 4-3/task-84: C4-17 validation",
        "为 C4-17 platform-capabilities 补齐测试和验证证据。",
        "补齐单元测试、集成测试或契约测试，覆盖成功和失败路径。",
        "验证 Core API / UDL / Rust 实现三者一致。",
        "不新增业务功能，只补验证与必要测试 fixture。",
        "./dev check task 4-3/task-84",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-17 platform-capabilities",
        "- S4-X-02 platform-differences",
        "计划新增：`get_platform_capabilities(platform) -> PlatformCapabilities`",
        "platform id、app version。",
        "watcher、trash、share extension、cloud placeholder、security bookmark 支持矩阵。",
        "## DB 变化\n\n- 无。",
        "## 文件系统变化\n\n- 无。",
        "- `Config`",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S4-LNX-03 | local-folder-notice | C4-10, C4-17 | local folder risk",
        "| S4-X-02 | platform-differences | C4-01, C4-17 | capability matrix | UI 不硬猜平台能力",
        "| S4-X-08 | repository-settings | C4-17, C4-20 | cross-platform settings | 不支持项禁用",
        "平台差异必须结构化暴露。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in ["Rust 单元测试", "集成测试目录", "`core/tests/`"] {
        assert_contains(TESTING_DOC, fragment);
    }
}

fn assert_core_api_udl_and_rust_alignment() {
    for fragment in [
        "PlatformCapabilities get_platform_capabilities(",
        "PlatformId platform, string app_version",
        "dictionary PlatformCapabilitySupport",
        "PlatformCapabilityStatus status;",
        "boolean ui_enabled;",
        "boolean requires_permission;",
        "string? reason;",
        "dictionary PlatformCapabilities",
        "PlatformId platform;",
        "string app_version;",
        "PlatformCapabilitySupport watcher;",
        "PlatformCapabilitySupport trash;",
        "PlatformCapabilitySupport share_extension;",
        "PlatformCapabilitySupport cloud_placeholder;",
        "PlatformCapabilitySupport security_bookmark;",
        "enum PlatformId { \"Macos\", \"Ios\", \"Windows\", \"Linux\", \"Unknown\" };",
        "enum PlatformCapabilityStatus { \"Available\", \"Limited\", \"NotAvailable\", \"Unknown\" };",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "pub fn get_platform_capabilities(",
        "platform: PlatformId",
        "app_version: String",
        "CoreResult<PlatformCapabilities>",
        "Returns the C4-17 platform capability matrix for a platform shell.",
        "does not inspect the",
        "Returns `CoreError::Config { reason }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "pub(crate) fn get_platform_capabilities(",
        "validate_request(platform, &app_version)?;",
        "const MAX_APP_VERSION_LEN: usize = 64;",
        "PlatformId::Macos => macos_capabilities(platform, app_version)",
        "PlatformId::Ios => ios_capabilities(platform, app_version)",
        "PlatformId::Windows => windows_capabilities(platform, app_version)",
        "PlatformId::Linux => linux_capabilities(platform, app_version)",
        "PlatformId::Unknown => return Err(CoreError::config(\"platform id is required\"))",
    ] {
        assert_contains(PLATFORM_CAPABILITIES_RS, fragment);
    }
}

fn assert_consumer_scope_alignment() {
    for fragment in [
        "展示能力矩阵：Repository access、File import、File watcher",
        "Trash/Recycle Bin、Share integration、Camera import。",
        "能力未知时显示 `Unknown`，不显示成可用。",
        "不把未来路线图能力显示为当前可用。",
        "本页只说明能力，不直接执行危险操作。",
        "能力矩阵不替代真实权限检测和操作前 preflight",
    ] {
        assert_contains(PLATFORM_DIFFERENCES_PAGE, fragment);
    }

    for fragment in [
        "本地目录是推荐路径",
        "同步目录：需要确认冲突和监听风险。",
        "类型未知：显示 `Unknown`，不猜测。",
        "watcher 风险提示来自 inotify 能力边界。",
    ] {
        assert_contains(LOCAL_FOLDER_NOTICE_PAGE, fragment);
    }

    for fragment in [
        "展示访问状态、watcher 状态、云盘/本地目录状态。",
        "提供 `Platform capabilities` 入口。",
        "明确危险操作不在本页直接执行。",
        "打开页面读取 repo snapshot 和 platform capability snapshot。",
    ] {
        assert_contains(REPOSITORY_SETTINGS_PAGE, fragment);
    }
}

fn assert_existing_test_layers_are_present() {
    for fragment in [
        "platform_capabilities_contract_exports_signature_inputs_outputs_and_errors",
        "platform_capabilities_contract_rejects_invalid_inputs_as_config",
        "platform_capabilities_docs_core_api_udl_and_control_map_stay_aligned",
    ] {
        assert_contains(CONTRACT_TEST, fragment);
    }

    for fragment in [
        "platform_capabilities_implementation_returns_ios_matrix",
        "platform_capabilities_implementation_returns_desktop_matrices",
        "platform_capabilities_implementation_maps_invalid_inputs_to_config",
        "platform_capabilities_implementation_stays_side_effect_free",
    ] {
        assert_contains(IMPLEMENTATION_TEST, fragment);
    }

    for fragment in [
        "platform_capabilities_failure_empty_unknown_and_illegal_inputs_map_to_config",
        "platform_capabilities_failure_does_not_probe_io_db_or_permissions",
        "platform_capabilities_failure_disables_unsupported_dangerous_operations",
        "platform_capabilities_failure_source_has_no_fs_db_network_or_secret_logging_paths",
    ] {
        assert_contains(FAILURE_TEST, fragment);
    }
}
