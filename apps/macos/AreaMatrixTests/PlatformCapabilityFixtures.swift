@testable import AreaMatrix
@testable import AreaMatrixCoreContracts

extension PlatformCapabilitySupportSnapshot {
    static func testFixture(
        status: PlatformCapabilityStatusSnapshot = .available,
        uiEnabled: Bool = true,
        requiresPermission: Bool = false,
        reason: String? = nil
    ) -> PlatformCapabilitySupportSnapshot {
        PlatformCapabilitySupportSnapshot(
            status: status,
            uiEnabled: uiEnabled,
            requiresPermission: requiresPermission,
            reason: reason
        )
    }

    static func limitedFixture(
        reason: String = "Requires platform permission."
    ) -> PlatformCapabilitySupportSnapshot {
        .testFixture(status: .limited, uiEnabled: false, requiresPermission: true, reason: reason)
    }

    static func unavailableFixture(reason: String? = nil) -> PlatformCapabilitySupportSnapshot {
        .testFixture(status: .notAvailable, uiEnabled: false, reason: reason)
    }
}

extension PlatformCapabilitiesSnapshot {
    static func testFixture(
        platform: PlatformIdSnapshot = .macos,
        appVersion: String = "1",
        watcher: PlatformCapabilitySupportSnapshot = .testFixture(),
        trash: PlatformCapabilitySupportSnapshot = .testFixture(),
        shareExtension: PlatformCapabilitySupportSnapshot = .unavailableFixture(),
        cloudPlaceholder: PlatformCapabilitySupportSnapshot = .testFixture(),
        securityBookmark: PlatformCapabilitySupportSnapshot = .testFixture()
    ) -> PlatformCapabilitiesSnapshot {
        PlatformCapabilitiesSnapshot(
            platform: platform,
            appVersion: appVersion,
            watcher: watcher,
            trash: trash,
            shareExtension: shareExtension,
            cloudPlaceholder: cloudPlaceholder,
            securityBookmark: securityBookmark
        )
    }
}
