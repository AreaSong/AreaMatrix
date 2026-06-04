use area_matrix_core::{
    get_platform_capabilities, CoreError, CoreResult, PlatformCapabilities,
    PlatformCapabilityStatus, PlatformCapabilitySupport, PlatformId,
};
use pretty_assertions::assert_eq;

const TASK: &str = include_str!(
    "../../tasks/prompts/phase-4/4-3-stage4-multiplatform/task-81-c4-17-contract-api.md"
);
const CAPABILITY_SPEC: &str = include_str!(
    "../../docs/core/capability-specs/stage-4-multiplatform/C4-17-platform-capabilities.md"
);
const CONTROL_MAP: &str = include_str!("../../docs/architecture/stage-4-control-map.md");
const PLATFORM_DIFFERENCES_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-02-platform-differences.md");
const LOCAL_FOLDER_NOTICE_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-LNX-03-local-folder-notice.md");
const REPOSITORY_SETTINGS_PAGE: &str =
    include_str!("../../docs/ux/page-specs/stage-4-multiplatform/S4-X-08-repository-settings.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
const API_RS: &str = include_str!("../src/api.rs");
const LIB_RS: &str = include_str!("../src/lib.rs");
const PLATFORM_CAPABILITIES_RS: &str = include_str!("../src/platform_capabilities.rs");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected text to contain `{needle}`"
    );
}

#[test]
fn platform_capabilities_contract_exports_signature_inputs_outputs_and_errors() {
    fn assert_get(_: fn(PlatformId, String) -> CoreResult<PlatformCapabilities>) {}
    assert_get(get_platform_capabilities);

    let support = PlatformCapabilitySupport {
        status: PlatformCapabilityStatus::Limited,
        ui_enabled: true,
        requires_permission: true,
        reason: Some("requires user permission".to_owned()),
    };
    let matrix = PlatformCapabilities {
        platform: PlatformId::Linux,
        app_version: "0.1.0".to_owned(),
        watcher: support.clone(),
        trash: support.clone(),
        share_extension: support.clone(),
        cloud_placeholder: support.clone(),
        security_bookmark: support,
    };

    assert_eq!(matrix.platform, PlatformId::Linux);
    assert_eq!(matrix.watcher.status, PlatformCapabilityStatus::Limited);
    assert!(matrix.trash.ui_enabled);
    assert!(matrix.security_bookmark.requires_permission);

    let documented_errors = [CoreError::config("platform capability input is invalid")];
    assert_eq!(documented_errors.len(), 1);
}

#[test]
fn platform_capabilities_contract_returns_safe_unknown_matrix_without_platform_probe() {
    let matrix =
        get_platform_capabilities(PlatformId::Windows, "0.1.0".to_owned()).expect("matrix");

    assert_eq!(matrix.platform, PlatformId::Windows);
    for row in [
        &matrix.watcher,
        &matrix.trash,
        &matrix.share_extension,
        &matrix.cloud_placeholder,
        &matrix.security_bookmark,
    ] {
        assert_eq!(row.status, PlatformCapabilityStatus::Unknown);
        assert!(!row.ui_enabled);
        assert!(!row.requires_permission);
        assert!(row
            .reason
            .as_deref()
            .is_some_and(|reason| { reason.contains("not reported by this Core contract") }));
    }
}

#[test]
fn platform_capabilities_contract_rejects_invalid_inputs_as_config() {
    assert!(matches!(
        get_platform_capabilities(PlatformId::Unknown, "0.1.0".to_owned()),
        Err(CoreError::Config { .. })
    ));
    assert!(matches!(
        get_platform_capabilities(PlatformId::Ios, String::new()),
        Err(CoreError::Config { .. })
    ));
    assert!(matches!(
        get_platform_capabilities(PlatformId::Macos, "\0".to_owned()),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn platform_capabilities_docs_core_api_udl_and_control_map_stay_aligned() {
    for fragment in [
        "# 4-3/task-81: C4-17 contract-api",
        "为 C4-17 platform-capabilities 对齐 Core API / UDL 合同，不实现业务逻辑。",
        "只补合同、类型、桥接声明或文档缺口，不实现相邻能力。",
    ] {
        assert_contains(TASK, fragment);
    }

    for fragment in [
        "# C4-17 platform-capabilities",
        "- S4-X-02 platform-differences",
        "计划新增：`get_platform_capabilities(platform) -> PlatformCapabilities`",
        "platform id、app version。",
        "watcher、trash、share extension、cloud placeholder、security bookmark 支持矩阵。",
        "- `Config`",
        "UI 显示的平台差异来自结构化能力。",
        "不支持的危险操作必须在 UI 层禁用。",
        "文案不承诺平台不存在的能力。",
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

    for fragment in [
        "PlatformCapabilities get_platform_capabilities(",
        "PlatformId platform, string app_version",
        "dictionary PlatformCapabilitySupport",
        "PlatformCapabilityStatus status;",
        "boolean ui_enabled;",
        "boolean requires_permission;",
        "string? reason;",
        "dictionary PlatformCapabilities",
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
        "| `get_platform_capabilities(platform, app_version)` | platform | √ | Config |",
        "### `get_platform_capabilities(platform: PlatformId, appVersion: String) throws -> PlatformCapabilities`",
        "C4-17 的平台能力矩阵入口",
        "`S4-X-02 platform-differences`",
        "`S4-LNX-03 local-folder-notice`",
        "`S4-X-08 repository-settings`",
        "不启动 watcher",
        "不检测 Trash / Recycle Bin",
        "不触发 iCloud placeholder 下载",
        "不刷新 security-scoped bookmark",
        "本合同不新增 control map 之外的页面能力",
        "`Unknown` 必须显示为未知",
        "`Config`：`platform = Unknown`",
    ] {
        assert_contains(CORE_API, fragment);
    }

    assert_contains(ERROR_CODES, "`Config { reason }`");
}

#[test]
fn platform_capabilities_documents_consumers_and_scope_boundaries() {
    for fragment in [
        "展示能力矩阵：Repository access、File import、File watcher、Cloud provider、Trash/Recycle Bin、Share integration、Camera import。",
        "能力未知时显示 `Unknown`，不显示成可用。",
        "不把未来路线图能力显示为当前可用。",
        "本页只说明能力，不直接执行危险操作。",
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

    for fragment in [
        "Returns the C4-17 platform capability matrix for a platform shell.",
        "Unknown capability rows",
        "disabled by default",
        "does not inspect the",
        "repository, start watchers",
        "Returns `CoreError::Config { reason }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "C4-17 platform capability matrix contract types and entry point.",
        "does not inspect repositories",
        "not reported by this Core contract",
        "Returns `CoreError::Config { reason }`",
    ] {
        assert_contains(PLATFORM_CAPABILITIES_RS, fragment);
    }

    for fragment in [
        "PlatformCapabilities",
        "PlatformCapabilityStatus",
        "PlatformCapabilitySupport",
        "PlatformId",
    ] {
        assert_contains(LIB_RS, fragment);
    }
}
