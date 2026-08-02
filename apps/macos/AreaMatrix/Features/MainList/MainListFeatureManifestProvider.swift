import AreaMatrixCoreContracts

enum MainListFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "MainList",
        owner: "MainList",
        responsibility: "Visible files, filtering, selection, loading, empty/error presentation, and feature entry contracts.",
        riskBoundary: "Cross-feature composition only; execution remains with Detail, FileActions, Search, or Import.",
        routes: ["mainEmpty", "mainList", "mainLoading", "mainError"],
        commands: ["openFile", "selectAll", "refresh"],
        settingsPanes: [],
        capabilities: ["CoreBridge", "SelectionState", "ExternalSync"],
        dependencies: ["CoreBridge", "DesignSystem"],
        previewScenarios: ["Loading", "Empty repository", "Large list", "Error recovery"],
        riskLevel: .medium,
        validationProfile: .integration
    )
}
