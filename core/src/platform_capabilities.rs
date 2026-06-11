//! C4-17 platform capability matrix contract types and entry point.

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult};

const MAX_APP_VERSION_LEN: usize = 64;

/// Platform shell requesting a capability matrix.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
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
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
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

/// Returns the C4-17 platform capability matrix.
///
/// The matrix is side-effect free and table driven. It does not inspect repositories,
/// start watchers, test Trash or Recycle Bin integration, query cloud SDKs,
/// refresh security-scoped bookmarks, read user files, or write diagnostics.
/// Limited and unavailable rows carry stable reasons so page consumers can
/// disable unsupported operations without guessing.
///
/// # Errors
///
/// Returns `CoreError::Config { reason }` when the platform id or app version
/// is not a valid contract input.
pub(crate) fn get_platform_capabilities(
    platform: PlatformId,
    app_version: String,
) -> CoreResult<PlatformCapabilities> {
    validate_request(platform, &app_version)?;
    Ok(match platform {
        PlatformId::Macos => macos_capabilities(platform, app_version),
        PlatformId::Ios => ios_capabilities(platform, app_version),
        PlatformId::Windows => windows_capabilities(platform, app_version),
        PlatformId::Linux => linux_capabilities(platform, app_version),
        PlatformId::Unknown => return Err(CoreError::config("platform id is required")),
    })
}

fn validate_request(platform: PlatformId, app_version: &str) -> CoreResult<()> {
    if platform == PlatformId::Unknown {
        return Err(CoreError::config("platform id is required"));
    }
    if app_version.trim().is_empty()
        || !app_version.chars().all(is_valid_app_version_char)
        || app_version.len() > MAX_APP_VERSION_LEN
    {
        return Err(CoreError::config("app version is invalid"));
    }
    Ok(())
}

fn is_valid_app_version_char(character: char) -> bool {
    character.is_ascii_alphanumeric() || matches!(character, '.' | '-' | '_' | '+')
}

fn macos_capabilities(platform: PlatformId, app_version: String) -> PlatformCapabilities {
    build_matrix(
        platform,
        app_version,
        CapabilityRows {
            watcher: available(),
            trash: available(),
            share_extension: not_available(
                "share extension import is not part of the macOS Core contract",
            ),
            cloud_placeholder: limited(
                true,
                true,
                "iCloud placeholder handling requires platform preflight",
            ),
            security_bookmark: available_with_permission(
                "sandboxed shells must keep user-granted repository access",
            ),
        },
    )
}

fn ios_capabilities(platform: PlatformId, app_version: String) -> PlatformCapabilities {
    build_matrix(
        platform,
        app_version,
        CapabilityRows {
            watcher: limited(
                false,
                false,
                "iOS uses foreground refresh instead of a continuous watcher",
            ),
            trash: not_available(
                "iOS does not expose a guaranteed Trash equivalent for repository files",
            ),
            share_extension: available(),
            cloud_placeholder: limited(
                true,
                true,
                "iCloud Drive placeholders require platform permission checks",
            ),
            security_bookmark: available_with_permission(
                "iOS repository access depends on security-scoped URLs",
            ),
        },
    )
}

fn windows_capabilities(platform: PlatformId, app_version: String) -> PlatformCapabilities {
    build_matrix(
        platform,
        app_version,
        CapabilityRows {
            watcher: available(),
            trash: limited(
                true,
                false,
                "Recycle Bin support depends on the selected volume",
            ),
            share_extension: not_available("share extension import is not available on Windows"),
            cloud_placeholder: limited(
                true,
                false,
                "OneDrive placeholder state is platform-reported",
            ),
            security_bookmark: not_available(
                "Windows uses folder picker and ACL permissions instead of bookmarks",
            ),
        },
    )
}

fn linux_capabilities(platform: PlatformId, app_version: String) -> PlatformCapabilities {
    build_matrix(
        platform,
        app_version,
        CapabilityRows {
            watcher: available(),
            trash: limited(
                true,
                false,
                "freedesktop Trash support depends on the desktop and mount",
            ),
            share_extension: not_available("share extension import is not available on Linux"),
            cloud_placeholder: not_available(
                "Linux sync folders do not expose a standard placeholder contract",
            ),
            security_bookmark: not_available(
                "Linux uses POSIX permissions instead of security-scoped bookmarks",
            ),
        },
    )
}

struct CapabilityRows {
    watcher: PlatformCapabilitySupport,
    trash: PlatformCapabilitySupport,
    share_extension: PlatformCapabilitySupport,
    cloud_placeholder: PlatformCapabilitySupport,
    security_bookmark: PlatformCapabilitySupport,
}

fn build_matrix(
    platform: PlatformId,
    app_version: String,
    rows: CapabilityRows,
) -> PlatformCapabilities {
    PlatformCapabilities {
        platform,
        app_version,
        watcher: rows.watcher,
        trash: rows.trash,
        share_extension: rows.share_extension,
        cloud_placeholder: rows.cloud_placeholder,
        security_bookmark: rows.security_bookmark,
    }
}

fn available() -> PlatformCapabilitySupport {
    PlatformCapabilitySupport {
        status: PlatformCapabilityStatus::Available,
        ui_enabled: true,
        requires_permission: false,
        reason: None,
    }
}

fn available_with_permission(reason: &str) -> PlatformCapabilitySupport {
    PlatformCapabilitySupport {
        status: PlatformCapabilityStatus::Available,
        ui_enabled: true,
        requires_permission: true,
        reason: Some(reason.to_owned()),
    }
}

fn limited(ui_enabled: bool, requires_permission: bool, reason: &str) -> PlatformCapabilitySupport {
    PlatformCapabilitySupport {
        status: PlatformCapabilityStatus::Limited,
        ui_enabled,
        requires_permission,
        reason: Some(reason.to_owned()),
    }
}

fn not_available(reason: &str) -> PlatformCapabilitySupport {
    PlatformCapabilitySupport {
        status: PlatformCapabilityStatus::NotAvailable,
        ui_enabled: false,
        requires_permission: false,
        reason: Some(reason.to_owned()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unsupported_rows_are_disabled_by_default() {
        let matrix =
            get_platform_capabilities(PlatformId::Linux, "0.1.0".to_owned()).expect("matrix");

        assert_eq!(matrix.watcher.status, PlatformCapabilityStatus::Available);
        assert!(matrix.watcher.ui_enabled);
        assert_eq!(matrix.trash.status, PlatformCapabilityStatus::Limited);
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
