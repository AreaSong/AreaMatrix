import Foundation

/// Source-of-truth catalog for the built-in feature boundaries.
///
/// Feature implementations remain App-owned while their stable ownership,
/// risk, dependency, and extension contracts live in this independently
/// testable package. The App target only adapts these values to its local
/// `FeatureManifestProvider` names.
public enum FeatureManifestCatalog {
    public static let ai = FeatureManifest(
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

    public static let commandPalette = FeatureManifest(
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

    public static let detail = FeatureManifest(
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

    public static let diagnostics = FeatureManifest(
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

    public static let fileActions = FeatureManifest(
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

    public static let `import` = FeatureManifest(
        id: "Import",
        owner: "Import",
        responsibility: "Single-file, folder, batch, progress, result, conflict, duplicate, and placeholder flows.",
        riskBoundary: "Source files, final repository state, DB consistency, iCloud placeholders, and session recovery.",
        routes: ["importEntry", "importProgress", "importResult", "importConflict"],
        commands: ["import", "retryImport", "resolveConflict"],
        settingsPanes: [],
        capabilities: ["UserFileRead", "UserFileWrite", "CoreBridge", "SessionRecovery"],
        dependencies: ["CoreBridge", "PlatformServices", "DesignSystem"],
        previewScenarios: ["Import progress", "Duplicate conflict", "Placeholder unavailable"],
        riskLevel: .missionCritical,
        validationProfile: .safety,
        extensions: [
            FeatureExtensionManifest(
                id: "import.files",
                ownerFeatureID: "Import",
                kind: .importSource,
                contractVersion: "1.0.0",
                capabilities: ["UserFileRead", "UserFileWrite", "SessionRecovery"],
                dependencies: ["CoreBridge", "PlatformServices"],
                riskLevel: .missionCritical,
                validationProfile: .safety
            ),
            FeatureExtensionManifest(
                id: "import.folder",
                ownerFeatureID: "Import",
                kind: .importSource,
                contractVersion: "1.0.0",
                capabilities: ["UserFileRead", "UserFileWrite", "SessionRecovery"],
                dependencies: ["CoreBridge", "PlatformServices"],
                riskLevel: .missionCritical,
                validationProfile: .safety
            )
        ]
    )

    public static let mainList = FeatureManifest(
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

    public static let onboarding = FeatureManifest(
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

    public static let repositoryLifecycle = FeatureManifest(
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

    public static let search = FeatureManifest(
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

    public static let settings = FeatureManifest(
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

    public static let syncConflicts = FeatureManifest(
        id: "SyncConflicts",
        owner: "SyncConflicts",
        responsibility: "iCloud and external sync conflict listing, review, preview, resolve, and replace confirmation.",
        riskBoundary: "External changes, iCloud copies, conflict resolution, and user-file selection.",
        routes: ["syncConflicts", "iCloudConflict", "replaceConfirmation"],
        commands: ["reviewSyncConflict", "resolveSyncConflict"],
        settingsPanes: [],
        capabilities: ["ICloud", "ExternalSync", "UserFileWrite"],
        dependencies: ["CoreBridge", "PlatformServices", "FileActions", "DesignSystem"],
        previewScenarios: ["Conflict list", "Placeholder", "Replace confirmation"],
        riskLevel: .missionCritical,
        validationProfile: .safety
    )

    public static let all: [FeatureManifest] = [
        ai,
        commandPalette,
        detail,
        diagnostics,
        fileActions,
        `import`,
        mainList,
        onboarding,
        repositoryLifecycle,
        search,
        settings,
        syncConflicts
    ]

    public static let byID: [String: FeatureManifest] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}
