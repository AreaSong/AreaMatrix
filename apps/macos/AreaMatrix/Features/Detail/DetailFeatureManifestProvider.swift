import AreaMatrixCoreContracts

enum DetailFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "Detail",
        owner: "Detail",
        responsibility: "Selected-file detail, notes, tags, metadata, logs, and multi-selection summaries.",
        riskBoundary: "Read/write actions remain behind FileActions or CoreBridge contracts.",
        routes: ["detail", "detailNote", "detailLog", "detailTags"],
        commands: ["openNote", "openChangeLog", "applyTagSuggestion"],
        settingsPanes: [],
        capabilities: ["CoreBridge", "SelectionState"],
        dependencies: ["CoreBridge", "AI", "DesignSystem"],
        previewScenarios: ["Selected file", "No selection", "Load failure"],
        riskLevel: .medium,
        validationProfile: .feature
    )
}
