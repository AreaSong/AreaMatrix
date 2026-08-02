import AreaMatrixCoreContracts

enum RepositoryLifecycleFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "RepositoryLifecycle",
        owner: "RepositoryLifecycle",
        responsibility: "Repository-level errors, lifecycle presentation, and shared open/recovery entry contracts.",
        riskBoundary: "Repository availability and Core error mapping; no direct user-file mutation.",
        routes: ["repositoryError", "repositorySettings"],
        commands: ["openRepository", "retryRepository"],
        settingsPanes: ["Repository"],
        capabilities: ["CoreBridge", "RepositoryContext"],
        dependencies: ["CoreBridge", "PlatformServices", "DesignSystem"],
        previewScenarios: ["Repository unavailable", "Retry", "Configuration error"],
        riskLevel: .high,
        validationProfile: .integration
    )
}
