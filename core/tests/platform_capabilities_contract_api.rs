use area_matrix_core::{
    get_platform_capabilities, CoreError, CoreResult, PlatformCapabilities,
    PlatformCapabilityStatus, PlatformCapabilitySupport, PlatformId,
};
use pretty_assertions::assert_eq;

const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const ERROR_CODES: &str = include_str!("../../docs/api/error-codes.md");
#[path = "support/api_contract_source.rs"]
mod api_contract_source;

use api_contract_source::API_RS;
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
fn platform_capabilities_contract_returns_structured_matrix_without_platform_probe() {
    let matrix =
        get_platform_capabilities(PlatformId::Windows, "0.1.0".to_owned()).expect("matrix");

    assert_eq!(matrix.platform, PlatformId::Windows);
    assert_eq!(matrix.app_version, "0.1.0");
    assert_eq!(matrix.watcher.status, PlatformCapabilityStatus::Available);
    assert!(matrix.watcher.ui_enabled);
    assert_eq!(matrix.trash.status, PlatformCapabilityStatus::Limited);
    assert!(matrix.trash.ui_enabled);
    assert_eq!(
        matrix.share_extension.status,
        PlatformCapabilityStatus::NotAvailable
    );
    assert!(!matrix.share_extension.ui_enabled);
    assert_eq!(
        matrix.cloud_placeholder.status,
        PlatformCapabilityStatus::Limited
    );
    assert_eq!(
        matrix.security_bookmark.status,
        PlatformCapabilityStatus::NotAvailable
    );
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
        "platform capabilities 的平台能力矩阵入口",
        "`platform differences surface`",
        "`Linux local-folder notice surface`",
        "`repository settings surface`",
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
        "Returns the platform capability matrix for a platform shell.",
        "Limited, unavailable, or",
        "unknown capability rows carry stable reasons",
        "does not inspect the",
        "repository, start watchers",
        "Returns `CoreError::Config { reason }`",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "Platform capability matrix contract types and entry point.",
        "does not inspect repositories",
        "Limited and unavailable rows",
        "disable unsupported operations without guessing",
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
