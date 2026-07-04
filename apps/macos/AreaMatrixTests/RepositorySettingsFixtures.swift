@testable import AreaMatrix

extension RepoConfigSnapshot {
    static func repositorySettingsConfigFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: true,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

func repositorySettingsCapabilitySupport(
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

func repositorySettingsCapabilitiesFixture(
    watcher: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport(),
    trash: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport(),
    cloudPlaceholder: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport(),
    securityBookmark: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport()
) -> PlatformCapabilitiesSnapshot {
    PlatformCapabilitiesSnapshot(
        platform: .macos,
        appVersion: "1",
        watcher: watcher,
        trash: trash,
        shareExtension: repositorySettingsCapabilitySupport(status: .notAvailable, uiEnabled: false),
        cloudPlaceholder: cloudPlaceholder,
        securityBookmark: securityBookmark
    )
}
