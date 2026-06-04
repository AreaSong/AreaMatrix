use std::{fs, path::PathBuf};

use area_matrix_core::{
    get_platform_capabilities, CoreError, ErrorKind, ErrorRecoverability, ErrorSeverity,
    PlatformCapabilities, PlatformCapabilityStatus, PlatformId,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-83-c4-17-failure-edge.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-17-platform-capabilities.md"
);
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const TRANSACTIONAL_IMPORT: &str = include_str!("../../docs/architecture/transactional-import.md");
const TROUBLESHOOTING: &str = include_str!("../../docs/development/troubleshooting.md");
const IMPLEMENTATION: &str = include_str!("../src/platform_capabilities.rs");

fn snapshot(paths: &[PathBuf]) -> Vec<(PathBuf, Vec<u8>)> {
    paths
        .iter()
        .map(|path| {
            (
                path.clone(),
                fs::read(path).expect("read user file snapshot"),
            )
        })
        .collect()
}

fn assert_config_error(error: CoreError, expected_reason: &str) {
    let mapping = error.to_error_mapping();

    assert_eq!(error.kind(), ErrorKind::Config);
    assert_eq!(mapping.kind, ErrorKind::Config);
    assert_eq!(mapping.severity, ErrorSeverity::Medium);
    assert_eq!(
        mapping.recoverability,
        ErrorRecoverability::UserActionRequired
    );
    assert_eq!(error.raw_context(), expected_reason);
    assert_eq!(mapping.raw_context, expected_reason);
}

fn assert_no_disabled_row_is_exposed_as_enabled(matrix: &PlatformCapabilities) {
    for row in [
        &matrix.watcher,
        &matrix.trash,
        &matrix.share_extension,
        &matrix.cloud_placeholder,
        &matrix.security_bookmark,
    ] {
        if row.status == PlatformCapabilityStatus::NotAvailable {
            assert!(!row.ui_enabled);
            assert!(row
                .reason
                .as_deref()
                .is_some_and(|reason| !reason.is_empty()));
        }
        if row.status == PlatformCapabilityStatus::Limited {
            assert!(row
                .reason
                .as_deref()
                .is_some_and(|reason| !reason.is_empty()));
        }
    }
}

#[test]
fn platform_capabilities_failure_empty_unknown_and_illegal_inputs_map_to_config() {
    let cases = [
        (
            PlatformId::Unknown,
            "4.0.0",
            "platform id is required",
            "unknown platform",
        ),
        (
            PlatformId::Linux,
            "",
            "app version is invalid",
            "empty version",
        ),
        (
            PlatformId::Linux,
            "   ",
            "app version is invalid",
            "blank version",
        ),
        (
            PlatformId::Macos,
            "4.0.0\napi_key=sk-secret",
            "app version is invalid",
            "newline and secret-shaped input",
        ),
        (
            PlatformId::Windows,
            "4.0.0/app",
            "app version is invalid",
            "path-like version",
        ),
    ];

    for (platform, version, expected_reason, label) in cases {
        let error = get_platform_capabilities(platform, version.to_owned()).expect_err(label);
        assert_config_error(error, expected_reason);
    }

    let too_long = "v".repeat(65);
    let error = get_platform_capabilities(PlatformId::Ios, too_long)
        .expect_err("overlong app version must fail");
    assert_config_error(error, "app version is invalid");
}

#[test]
fn platform_capabilities_failure_does_not_probe_io_db_or_permissions() {
    let repo = tempfile::tempdir().expect("create user-controlled directory");
    let readme = repo.path().join("README.md");
    let metadata = repo.path().join(".areamatrix");
    let db_path = metadata.join("index.db");
    fs::write(&readme, b"user authored content").expect("write user file");
    fs::create_dir(&metadata).expect("create metadata directory");
    fs::write(&db_path, b"not a sqlite database").expect("write corrupted db marker");
    let before = snapshot(&[readme.clone(), db_path.clone()]);

    let matrix = get_platform_capabilities(PlatformId::Linux, "4.0.0-linux".to_owned())
        .expect("capability matrix should not open repo state");
    let error = get_platform_capabilities(PlatformId::Linux, "bad/version".to_owned())
        .expect_err("invalid version should fail before any external probe");

    assert_eq!(matrix.platform, PlatformId::Linux);
    assert_config_error(error, "app version is invalid");
    assert_eq!(snapshot(&[readme, db_path]), before);
    assert!(!repo.path().join("AREAMATRIX.md").exists());
    assert!(!metadata.join("generated").exists());
    assert!(!metadata.join("staging").exists());
}

#[test]
fn platform_capabilities_failure_disables_unsupported_dangerous_operations() {
    for platform in [
        PlatformId::Macos,
        PlatformId::Ios,
        PlatformId::Windows,
        PlatformId::Linux,
    ] {
        let matrix =
            get_platform_capabilities(platform, "4.0.0".to_owned()).expect("valid platform matrix");
        assert_no_disabled_row_is_exposed_as_enabled(&matrix);
    }

    let ios = get_platform_capabilities(PlatformId::Ios, "4.0.0".to_owned()).expect("iOS matrix");
    assert_eq!(ios.trash.status, PlatformCapabilityStatus::NotAvailable);
    assert!(!ios.trash.ui_enabled);

    let linux =
        get_platform_capabilities(PlatformId::Linux, "4.0.0".to_owned()).expect("Linux matrix");
    assert_eq!(
        linux.cloud_placeholder.status,
        PlatformCapabilityStatus::NotAvailable
    );
    assert!(!linux.cloud_placeholder.ui_enabled);
}

#[test]
fn platform_capabilities_failure_source_has_no_fs_db_network_or_secret_logging_paths() {
    for forbidden in [
        "std::fs",
        "std::path",
        "PathBuf",
        "rusqlite",
        "db::",
        "read_dir",
        "metadata(",
        "Command::",
        "reqwest",
        "ureq",
        "tracing::",
        "println!",
        "api_key",
        "token",
        "secret",
    ] {
        assert!(
            !IMPLEMENTATION.contains(forbidden),
            "C4-17 capability matrix must stay side-effect free; found {forbidden}"
        );
    }
}

#[test]
fn platform_capabilities_failure_docs_record_recovery_and_scope_boundaries() {
    for fragment in [
        "覆盖空态、非法输入、权限、IO/DB 错误和错误码映射。",
        "必须证明失败不留下半成品。",
        "不得用吞错或静默降级掩盖失败。",
    ] {
        assert!(TASK.contains(fragment));
    }

    for fragment in [
        "## 文件系统变化\n\n- 无。",
        "## DB 变化\n\n- 无。",
        "- `Config`",
    ] {
        assert!(CAPABILITY_SPEC.contains(fragment));
    }

    for fragment in [
        "只返回平台能力合同，不读取 repo、不写 DB、不触碰用户文件。",
        "不启动 watcher",
        "不检测 Trash / Recycle Bin",
        "不触发 iCloud placeholder 下载",
        "不刷新 security-scoped bookmark",
        "`Config`：`platform = Unknown`，或 `appVersion` 为空、过长、含非法字符。",
    ] {
        assert!(CORE_API.contains(fragment));
    }

    for fragment in [
        "| `Config { reason }` | classifier.yaml 解析失败、必填字段缺失",
        "CoreError::Config { reason }",
    ] {
        assert!(ERROR_CODES.contains(fragment));
    }

    for fragment in [
        "失败的 import 不留下 DB 记录或最终目录中的半文件",
        "任何步骤失败：`ROLLBACK` + `StagingGuard` 自动删除 staging 文件",
    ] {
        assert!(TRANSACTIONAL_IMPORT.contains(fragment));
    }

    for fragment in [
        "CoreError.PermissionDenied",
        "CoreError.Db(\"database is locked\")",
    ] {
        assert!(TROUBLESHOOTING.contains(fragment));
    }
}
