import AreaMatrixCoreContracts

enum CommandPaletteFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "CommandPalette",
        owner: "CommandPalette",
        responsibility: "Command discovery, focus restoration, and contextual command routing.",
        riskBoundary: "Presentation and routing only; commands delegate execution to their owning feature.",
        routes: ["commandPalette"],
        commands: ["openCommandPalette", "find", "openSettings", "openHelp"],
        settingsPanes: [],
        capabilities: ["KeyboardRouting"],
        dependencies: ["MainList", "FileActions", "Search", "DesignSystem"],
        previewScenarios: ["Empty query", "Filtered commands", "Focus restore"],
        riskLevel: .low,
        validationProfile: .feature,
        extensions: [
            FeatureExtensionManifest(
                id: "command.palette",
                ownerFeatureID: "CommandPalette",
                kind: .command,
                contractVersion: "1.0.0",
                capabilities: ["KeyboardRouting"],
                dependencies: ["MainList", "FileActions", "Search"],
                riskLevel: .low,
                validationProfile: .feature
            )
        ]
    )
}
