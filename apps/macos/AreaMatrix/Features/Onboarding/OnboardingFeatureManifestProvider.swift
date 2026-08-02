import AreaMatrixCoreContracts

enum OnboardingFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "Onboarding",
        owner: "Onboarding",
        responsibility: "Welcome, path validation, initialization, startup recovery, DB repair, and main loading.",
        riskBoundary: "Repository opening, initialization writes, recovery, DB repair, and user-file safety.",
        routes: ["welcome", "choosePath", "validatePath", "initialize", "dbRepair"],
        commands: ["continueSetup", "chooseRepository", "repairDatabase"],
        settingsPanes: [],
        capabilities: ["CoreBridge", "UserFileRead", "UserFileWrite", "DatabaseRepair"],
        dependencies: ["CoreBridge", "PlatformServices", "RepositoryLifecycle", "DesignSystem"],
        previewScenarios: ["Welcome", "Permission failure", "Database repair"],
        riskLevel: .missionCritical,
        validationProfile: .safety
    )
}
