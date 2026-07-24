@testable import AreaMatrix

extension AppRepoConfigSnapshot {
    static func repositorySettingsConfigFixture(repoPath: String) -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.aiEnabled = true
        }
    }
}

extension ExistingRepositoryMetadataSnapshot {
    static func testFixture(
        schemaVersion: Int64 = 1,
        lastOpenedAt: Int64? = nil,
        configuredRepoPath: String? = nil
    ) -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(
            schemaVersion: schemaVersion,
            lastOpenedAt: lastOpenedAt,
            configuredRepoPath: configuredRepoPath
        )
    }
}

func repositorySettingsCapabilitySupport(
    status: PlatformCapabilityStatusSnapshot = .available,
    uiEnabled: Bool = true,
    requiresPermission: Bool = false,
    reason: String? = nil
) -> PlatformCapabilitySupportSnapshot {
    PlatformCapabilitySupportSnapshot.testFixture(
        status: status,
        uiEnabled: uiEnabled,
        requiresPermission: requiresPermission,
        reason: reason
    )
}

func repositorySettingsCapabilitiesFixture(
    watcher: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport(),
    trash: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport(),
    cloudPlaceholder: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport(),
    securityBookmark: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport()
) -> PlatformCapabilitiesSnapshot {
    PlatformCapabilitiesSnapshot.testFixture(
        appVersion: "1",
        watcher: watcher,
        trash: trash,
        shareExtension: .unavailableFixture(),
        cloudPlaceholder: cloudPlaceholder,
        securityBookmark: securityBookmark
    )
}
