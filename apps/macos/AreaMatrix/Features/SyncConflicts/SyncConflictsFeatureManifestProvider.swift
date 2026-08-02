import AreaMatrixCoreContracts

enum SyncConflictsFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "SyncConflicts",
        owner: "SyncConflicts",
        responsibility: "iCloud and external sync conflict listing, review, preview, resolve, and replace confirmation.",
        riskBoundary: "External changes, iCloud copies, conflict resolution, and user-file selection.",
        routes: ["syncConflicts", "iCloudConflict", "replaceConfirmation"],
        commands: ["reviewSyncConflict", "resolveSyncConflict"],
        settingsPanes: [],
        capabilities: ["ICloud", "ExternalSync", "UserFileWrite"],
        dependencies: ["CoreBridge", "PlatformServices", "FileActions", "DesignSystem"],
        previewScenarios: ["Conflict list", "Placeholder", "Replace confirmation"],
        riskLevel: .missionCritical,
        validationProfile: .safety
    )
}
