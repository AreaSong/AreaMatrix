use area_matrix_core::{
    get_platform_capabilities, CoreError, PlatformCapabilityStatus, PlatformCapabilitySupport,
    PlatformId,
};
use pretty_assertions::assert_eq;

const IMPLEMENTATION: &str = include_str!("../src/platform_capabilities.rs");

fn assert_row(
    row: &PlatformCapabilitySupport,
    status: PlatformCapabilityStatus,
    ui_enabled: bool,
    requires_permission: bool,
    reason_fragment: Option<&str>,
) {
    assert_eq!(row.status, status);
    assert_eq!(row.ui_enabled, ui_enabled);
    assert_eq!(row.requires_permission, requires_permission);
    match reason_fragment {
        Some(fragment) => assert!(
            row.reason
                .as_deref()
                .is_some_and(|reason| reason.contains(fragment)),
            "expected reason to contain {fragment:?}, got {:?}",
            row.reason
        ),
        None => assert_eq!(row.reason, None),
    }
}

#[test]
fn platform_capabilities_implementation_returns_ios_matrix() {
    let matrix =
        get_platform_capabilities(PlatformId::Ios, "4.0.0-ios".to_owned()).expect("matrix");

    assert_eq!(matrix.platform, PlatformId::Ios);
    assert_eq!(matrix.app_version, "4.0.0-ios");
    assert_row(
        &matrix.watcher,
        PlatformCapabilityStatus::Limited,
        false,
        false,
        Some("foreground refresh"),
    );
    assert_row(
        &matrix.trash,
        PlatformCapabilityStatus::NotAvailable,
        false,
        false,
        Some("Trash equivalent"),
    );
    assert_row(
        &matrix.share_extension,
        PlatformCapabilityStatus::Available,
        true,
        false,
        None,
    );
    assert_row(
        &matrix.cloud_placeholder,
        PlatformCapabilityStatus::Limited,
        true,
        true,
        Some("iCloud Drive"),
    );
    assert_row(
        &matrix.security_bookmark,
        PlatformCapabilityStatus::Available,
        true,
        true,
        Some("security-scoped URLs"),
    );
}

#[test]
fn platform_capabilities_implementation_returns_desktop_matrices() {
    let windows =
        get_platform_capabilities(PlatformId::Windows, "4.0.0-win".to_owned()).expect("matrix");
    assert_row(
        &windows.watcher,
        PlatformCapabilityStatus::Available,
        true,
        false,
        None,
    );
    assert_row(
        &windows.trash,
        PlatformCapabilityStatus::Limited,
        true,
        false,
        Some("Recycle Bin"),
    );
    assert_row(
        &windows.share_extension,
        PlatformCapabilityStatus::NotAvailable,
        false,
        false,
        Some("Windows"),
    );
    assert_row(
        &windows.cloud_placeholder,
        PlatformCapabilityStatus::Limited,
        true,
        false,
        Some("OneDrive"),
    );
    assert_row(
        &windows.security_bookmark,
        PlatformCapabilityStatus::NotAvailable,
        false,
        false,
        Some("ACL permissions"),
    );

    let linux =
        get_platform_capabilities(PlatformId::Linux, "4.0.0-linux".to_owned()).expect("matrix");
    assert_row(
        &linux.watcher,
        PlatformCapabilityStatus::Available,
        true,
        false,
        None,
    );
    assert_row(
        &linux.trash,
        PlatformCapabilityStatus::Limited,
        true,
        false,
        Some("freedesktop Trash"),
    );
    assert_row(
        &linux.share_extension,
        PlatformCapabilityStatus::NotAvailable,
        false,
        false,
        Some("Linux"),
    );
    assert_row(
        &linux.cloud_placeholder,
        PlatformCapabilityStatus::NotAvailable,
        false,
        false,
        Some("standard placeholder"),
    );
    assert_row(
        &linux.security_bookmark,
        PlatformCapabilityStatus::NotAvailable,
        false,
        false,
        Some("POSIX permissions"),
    );
}

#[test]
fn platform_capabilities_implementation_returns_macos_matrix() {
    let matrix =
        get_platform_capabilities(PlatformId::Macos, "4.0.0-macos".to_owned()).expect("matrix");

    assert_row(
        &matrix.watcher,
        PlatformCapabilityStatus::Available,
        true,
        false,
        None,
    );
    assert_row(
        &matrix.trash,
        PlatformCapabilityStatus::Available,
        true,
        false,
        None,
    );
    assert_row(
        &matrix.share_extension,
        PlatformCapabilityStatus::NotAvailable,
        false,
        false,
        Some("macOS"),
    );
    assert_row(
        &matrix.cloud_placeholder,
        PlatformCapabilityStatus::Limited,
        true,
        true,
        Some("iCloud placeholder"),
    );
    assert_row(
        &matrix.security_bookmark,
        PlatformCapabilityStatus::Available,
        true,
        true,
        Some("user-granted repository access"),
    );
}

#[test]
fn platform_capabilities_implementation_maps_invalid_inputs_to_config() {
    assert!(matches!(
        get_platform_capabilities(PlatformId::Unknown, "4.0.0".to_owned()),
        Err(CoreError::Config { .. })
    ));
    assert!(matches!(
        get_platform_capabilities(PlatformId::Linux, " ".to_owned()),
        Err(CoreError::Config { .. })
    ));
    assert!(matches!(
        get_platform_capabilities(PlatformId::Windows, "x".repeat(65)),
        Err(CoreError::Config { .. })
    ));
}

#[test]
fn platform_capabilities_implementation_stays_side_effect_free() {
    for forbidden in [
        "std::fs",
        "std::path",
        "PathBuf",
        "rusqlite",
        "db::",
        "Command::",
        "read_dir",
        "metadata(",
    ] {
        assert!(
            !IMPLEMENTATION.contains(forbidden),
            "C4-17 must not probe filesystem or DB via {forbidden}"
        );
    }
}
