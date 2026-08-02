import AreaMatrixCoreContracts

enum FileActionsFeatureManifestProvider: FeatureManifestProvider {
    static let manifest = FeatureManifest(
        id: "FileActions",
        owner: "FileActions",
        responsibility: "Rename, delete, category move, batch actions, tags, confirmations, refresh, and undo routing.",
        riskBoundary: "User-file mutation, confirmation, Core consistency, and undo policy.",
        routes: ["rename", "delete", "changeCategory", "batchDelete", "batchRename", "undoHistory"],
        commands: ["rename", "delete", "changeCategory", "undo", "redo"],
        settingsPanes: [],
        capabilities: ["UserFileMutation", "CoreBridge", "UndoLog"],
        dependencies: ["CoreBridge", "DesignSystem"],
        previewScenarios: ["Confirmation", "Permission failure", "Undo available"],
        riskLevel: .missionCritical,
        validationProfile: .safety,
        extensions: [
            FeatureExtensionManifest(
                id: "command.file-actions",
                ownerFeatureID: "FileActions",
                kind: .command,
                contractVersion: "1.0.0",
                capabilities: ["UserFileMutation", "UndoLog"],
                dependencies: ["CoreBridge"],
                riskLevel: .missionCritical,
                validationProfile: .safety
            )
        ]
    )
}
