import AreaMatrixCoreContracts

enum ImportFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "Import",
        owner: "Import",
        responsibility: "Single-file, folder, batch, progress, result, conflict, duplicate, and placeholder flows.",
        riskBoundary: "Source files, final repository state, DB consistency, iCloud placeholders, and session recovery.",
        routes: ["importEntry", "importProgress", "importResult", "importConflict"],
        commands: ["import", "retryImport", "resolveConflict"],
        settingsPanes: [],
        capabilities: ["UserFileRead", "UserFileWrite", "CoreBridge", "SessionRecovery"],
        dependencies: ["CoreBridge", "PlatformServices", "DesignSystem"],
        previewScenarios: ["Import progress", "Duplicate conflict", "Placeholder unavailable"],
        riskLevel: .missionCritical,
        validationProfile: .safety,
        extensions: [
            FeatureExtensionManifest(
                id: "import.files",
                ownerFeatureID: "Import",
                kind: .importSource,
                contractVersion: "1.0.0",
                capabilities: ["UserFileRead", "UserFileWrite", "SessionRecovery"],
                dependencies: ["CoreBridge", "PlatformServices"],
                riskLevel: .missionCritical,
                validationProfile: .safety
            ),
            FeatureExtensionManifest(
                id: "import.folder",
                ownerFeatureID: "Import",
                kind: .importSource,
                contractVersion: "1.0.0",
                capabilities: ["UserFileRead", "UserFileWrite", "SessionRecovery"],
                dependencies: ["CoreBridge", "PlatformServices"],
                riskLevel: .missionCritical,
                validationProfile: .safety
            )
        ]
    )
}
