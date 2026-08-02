import AreaMatrixCoreContracts

enum SearchFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "Search",
        owner: "Search",
        responsibility: "Normal, semantic, saved, smart-list, filter, diagnostic, and search presentation routing.",
        riskBoundary: "Query diagnostics and privacy-aware semantic search; Core calls remain in Bridge.",
        routes: ["search", "semanticSearch", "savedSearch", "smartList"],
        commands: ["find", "semanticSearch", "manageSmartList"],
        settingsPanes: [],
        capabilities: ["CoreBridge", "QueryDiagnostics"],
        dependencies: ["CoreBridge", "DesignSystem"],
        previewScenarios: ["No results", "Semantic unavailable", "Saved search"],
        riskLevel: .medium,
        validationProfile: .feature
    )
}
