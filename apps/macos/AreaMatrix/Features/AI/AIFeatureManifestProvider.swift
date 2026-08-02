import AreaMatrixCoreContracts

enum AIFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "AI",
        owner: "AI",
        responsibility: "Privacy rules, provider configuration, summaries, classification, tags, and local/remote AI status.",
        riskBoundary: "User-data privacy, credentials, Keychain, network access, and probe process execution.",
        routes: ["settingsAI", "aiPrivacyRules", "aiSummary", "aiClassification", "aiTags"],
        commands: ["openAISettings", "suggestTags", "classifySelection"],
        settingsPanes: ["AI", "AI Privacy", "Remote Provider"],
        capabilities: ["CoreBridge", "Keychain", "RestrictedNetwork"],
        dependencies: ["CoreBridge", "PlatformServices", "DesignSystem"],
        previewScenarios: ["AI unavailable", "Privacy rules", "Provider configured"],
        riskLevel: .high,
        validationProfile: .safety,
        extensions: [
            FeatureExtensionManifest(
                id: "ai.remote-provider",
                ownerFeatureID: "AI",
                kind: .aiProvider,
                contractVersion: "1.0.0",
                capabilities: ["Keychain", "RestrictedNetwork"],
                dependencies: ["CoreBridge", "PlatformServices"],
                riskLevel: .high,
                validationProfile: .safety
            )
        ]
    )
}
