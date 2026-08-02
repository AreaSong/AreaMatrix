import AreaMatrixCoreContracts

enum DiagnosticsFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "Diagnostics",
        owner: "Diagnostics",
        responsibility: "Runtime evidence, incident capture, user activity, developer console, and diagnostic package preview and inspection.",
        riskBoundary: "Privacy-safe local evidence and explicit no-overwrite package export; business writes stay with their owning feature.",
        routes: ["diagnostics", "incidentDetail", "traceConsole"],
        commands: ["openDiagnostics", "captureIncident", "exportDiagnostics"],
        settingsPanes: ["Diagnostics"],
        capabilities: ["OSLog", "Signpost", "LocalPackageExport"],
        dependencies: ["PlatformServices", "DesignSystem"],
        previewScenarios: ["Healthy runtime", "Recovery notice", "Package export failure"],
        riskLevel: .high,
        validationProfile: .safety
    )
}
