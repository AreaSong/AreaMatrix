//! C4-17 platform capability matrix contract types and entry point.

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

const MAX_APP_VERSION_LEN: usize = 64;

/// Platform shell requesting a capability matrix.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum PlatformId {
    /// macOS shell.
    Macos,
    /// iOS shell.
    Ios,
    /// Windows shell.
    Windows,
    /// Linux shell.
    Linux,
    /// Platform has not been identified by the caller.
    Unknown,
}

/// UI-ready support state for one platform capability.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum PlatformCapabilityStatus {
    /// Capability is available for the requested platform.
    Available,
    /// Capability is available only with documented restrictions.
    Limited,
    /// Capability is not available for the requested platform.
    NotAvailable,
    /// Capability cannot be determined from the current contract state.
    Unknown,
}

/// Support row for one platform capability.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PlatformCapabilitySupport {
    /// Structured support state rendered by platform settings and help pages.
    pub status: PlatformCapabilityStatus,
    /// Whether the UI may enable operations that depend on this capability.
    pub ui_enabled: bool,
    /// Whether the platform layer must obtain user permission before use.
    pub requires_permission: bool,
    /// Stable reason for unavailable, limited, or unknown states.
    pub reason: Option<String>,
}

/// Platform capability matrix consumed by Stage 4 platform pages.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PlatformCapabilities {
    /// Platform shell that requested the matrix.
    pub platform: PlatformId,
    /// Caller app version used to bind diagnostics to a platform build.
    pub app_version: String,
    /// Filesystem watcher support.
    pub watcher: PlatformCapabilitySupport,
    /// Trash or Recycle Bin support for destructive confirmations.
    pub trash: PlatformCapabilitySupport,
    /// Share extension or share sheet import support.
    pub share_extension: PlatformCapabilitySupport,
    /// Cloud placeholder detection support.
    pub cloud_placeholder: PlatformCapabilitySupport,
    /// Security-scoped bookmark or equivalent persisted permission support.
    pub security_bookmark: PlatformCapabilitySupport,
}

/// Returns the C4-17 platform capability matrix contract.
///
/// The contract is side-effect free. It does not inspect repositories, start
/// watchers, test Trash/Recycle Bin integration, query cloud SDKs, refresh
/// security-scoped bookmarks, read user files, or write diagnostics. Unknown
/// rows are disabled by default so page consumers do not treat unsupported or
/// unimplemented capabilities as available.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when the platform id or app version
/// is not a valid contract input.
pub(crate) fn get_platform_capabilities(
    platform: PlatformId,
    app_version: String,
) -> CoreResult<PlatformCapabilities> {
    validate_request(&platform, &app_version)?;
    Ok(PlatformCapabilities {
        platform,
        app_version,
        watcher: unknown_support("watcher support is not reported by this Core contract"),
        trash: unknown_support("trash support is not reported by this Core contract"),
        share_extension: unknown_support(
            "share extension support is not reported by this Core contract",
        ),
        cloud_placeholder: unknown_support(
            "cloud placeholder support is not reported by this Core contract",
        ),
        security_bookmark: unknown_support(
            "security bookmark support is not reported by this Core contract",
        ),
    })
}

fn validate_request(platform: &PlatformId, app_version: &str) -> CoreResult<()> {
    if matches!(platform, PlatformId::Unknown) {
        return Err(CoreError::config("platform id is required"));
    }
    if app_version.trim().is_empty()
        || app_version.contains('\0')
        || app_version.len() > MAX_APP_VERSION_LEN
    {
        return Err(CoreError::config("app version is invalid"));
    }
    Ok(())
}

fn unknown_support(reason: &str) -> PlatformCapabilitySupport {
    PlatformCapabilitySupport {
        status: PlatformCapabilityStatus::Unknown,
        ui_enabled: false,
        requires_permission: false,
        reason: Some(reason.to_owned()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_contract_rows_are_disabled_by_default() {
        let matrix =
            get_platform_capabilities(PlatformId::Linux, "0.1.0".to_owned()).expect("matrix");

        assert_eq!(matrix.watcher.status, PlatformCapabilityStatus::Unknown);
        assert!(!matrix.watcher.ui_enabled);
        assert_eq!(matrix.trash.status, PlatformCapabilityStatus::Unknown);
        assert!(!matrix.share_extension.ui_enabled);
        assert!(!matrix.cloud_placeholder.ui_enabled);
        assert!(!matrix.security_bookmark.ui_enabled);
    }

    #[test]
    fn invalid_contract_inputs_return_config_errors() {
        assert!(matches!(
            get_platform_capabilities(PlatformId::Unknown, "0.1.0".to_owned()),
            Err(CoreError::Config { .. })
        ));
        assert!(matches!(
            get_platform_capabilities(PlatformId::Ios, " ".to_owned()),
            Err(CoreError::Config { .. })
        ));
    }
}
