import AreaMatrixCoreContracts

enum SettingsFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "Settings",
        owner: "Settings",
        responsibility: "General, repository, classifier, integrations, advanced, about, and platform differences settings.",
        riskBoundary: "Configuration writes, dangerous settings, diagnostics export, iCloud state, and platform actions.",
        routes: ["settingsGeneral", "settingsRepository", "settingsClassifier", "settingsAdvanced", "settingsAbout"],
        commands: ["openSettings", "openDiagnostics", "changeLanguage"],
        settingsPanes: ["General", "Repository", "Classifier", "Integrations", "Advanced", "About"],
        capabilities: ["ConfigurationWrite", "PlatformSettings", "Diagnostics"],
        dependencies: ["CoreBridge", "PlatformServices", "Diagnostics", "DesignSystem"],
        previewScenarios: ["General settings", "Configuration failure", "Language switch"],
        riskLevel: .high,
        validationProfile: .integration,
        extensions: [
            FeatureExtensionManifest(
                id: "command.settings",
                ownerFeatureID: "Settings",
                kind: .command,
                contractVersion: "1.0.0",
                capabilities: ["SettingsRouting"],
                dependencies: ["CoreBridge", "PlatformServices"],
                riskLevel: .high,
                validationProfile: .integration
            )
        ]
    )
}
