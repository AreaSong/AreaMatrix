import SwiftUI

#if DEBUG
enum AreaMatrixDeveloperScenario: String, CaseIterable, Hashable, Identifiable {
    case launcher
    case uiCatalog = "ui-catalog"
    case commandPalette = "command-palette"
    case detailLog = "detail-log"
    case detailNote = "detail-note"
    case detailPane = "detail-pane"
    case detailMultiSelection = "detail-multi-selection"
    case diagnosticsConsole = "diagnostics-console"
    case diagnosticsPackagePreview = "diagnostics-package-preview"
    case diagnosticsSettings = "diagnostics-settings"
    case onboarding
    case onboardingConfirm = "onboarding-confirm"
    case onboardingDatabaseRepair = "onboarding-database-repair"
    case onboardingDone = "onboarding-done"
    case onboardingFailed = "onboarding-failed"
    case onboardingInitializing = "onboarding-initializing"
    case onboardingRecovery = "onboarding-recovery"
    case onboardingValidatePath = "onboarding-validate-path"
    case loading
    case repositoryEmpty = "repository-empty"
    case repositoryReady = "repository-ready"
    case permissionFailure = "permission-failure"
    case databaseCorrupt = "database-corrupt"
    case iCloudPlaceholder = "icloud-placeholder"
    case importConflict = "import-conflict"
    case importEntry = "import-entry"
    case importFolderPreview = "import-folder-preview"
    case importProgress = "import-progress"
    case importResult = "import-result"
    case mainRepositoryContent = "main-repository-content"
    case syncConflict = "sync-conflict"
    case syncConflictsICloudList = "sync-conflicts-icloud-list"
    case syncConflictsICloudMinimal = "sync-conflicts-icloud-minimal"
    case syncConflictsEntry = "sync-conflicts-entry"
    case syncConflictsReplaceConfirmation = "sync-conflicts-replace-confirmation"
    case syncConflictsReview = "sync-conflicts-review"
    case aiUnavailable = "ai-unavailable"
    case aiCallLog = "ai-call-log"
    case aiClassificationSuggestion = "ai-classification-suggestion"
    case aiPrivacyRules = "ai-privacy-rules"
    case aiSettings = "ai-settings"
    case aiSummaryEditor = "ai-summary-editor"
    case aiTagSuggestions = "ai-tag-suggestions"
    case aiLocalModelStatus = "ai-local-model-status"
    case aiRemoteModelConfig = "ai-remote-model-config"
    case disabled
    case staleData = "stale-data"
    case longContent = "long-content"
    case largeData = "large-data"
    case searchQueryError = "search-query-error"
    case searchSavedSearch = "search-saved-search"
    case searchEmpty = "search-empty"
    case searchIndexStatus = "search-index-status"
    case searchSemanticResults = "search-semantic-results"
    case searchSmartList = "search-smart-list"
    case fileActionsBatchAddTags = "file-actions-batch-add-tags"
    case fileActionsBatchChangeCategory = "file-actions-batch-change-category"
    case fileActionsBatchDelete = "file-actions-batch-delete"
    case fileActionsBatchRename = "file-actions-batch-rename"
    case fileActionsChangeCategory = "file-actions-change-category"
    case fileActionsClassifierImpact = "file-actions-classifier-impact"
    case fileActionsDelete = "file-actions-delete"
    case fileActionsRename = "file-actions-rename"
    case fileActionsReplace = "file-actions-replace"
    case fileActionsTagSuggestions = "file-actions-tag-suggestions"
    case fileActionsUndoHistory = "file-actions-undo-history"
    case settingsAbout = "settings-about"
    case settingsAdvanced = "settings-advanced"
    case settingsClassifier = "settings-classifier"
    case settingsGeneral = "settings-general"
    case settingsIntegrations = "settings-integrations"
    case settingsLanguage = "settings-language"
    case settingsPlatformDifferences = "settings-platform-differences"
    case settingsRepository = "settings-repository"

    var id: String {
        rawValue
    }

    static var current: AreaMatrixDeveloperScenarioConfiguration? {
        resolve(environment: ProcessInfo.processInfo.environment)
    }

    static func resolve(environment: [String: String]) -> AreaMatrixDeveloperScenarioConfiguration? {
        AreaMatrixDeveloperScenarioConfiguration.resolve(environment: environment)
    }

    var title: String {
        switch self {
        case .launcher: "Scenario Launcher"
        case .uiCatalog: "UI Catalog"
        case .commandPalette: "Command Palette"
        case .detailLog: "Detail Change Log"
        case .detailNote: "Detail Note"
        case .detailPane: "File Detail Pane"
        case .detailMultiSelection: "Multi-selection Detail"
        case .diagnosticsConsole: "Diagnostics Console"
        case .diagnosticsPackagePreview: "Diagnostics Package Preview"
        case .diagnosticsSettings: "Diagnostics Settings"
        case .onboarding: "Welcome"
        case .onboardingConfirm: "Confirm Repository Initialization"
        case .onboardingDatabaseRepair: "Database Repair"
        case .onboardingDone: "Initialization Complete"
        case .onboardingFailed: "Initialization Failed"
        case .onboardingInitializing: "Repository Initialization"
        case .onboardingRecovery: "Startup Recovery Failure"
        case .onboardingValidatePath: "Validate Repository Path"
        case .loading: "Repository Loading"
        case .repositoryEmpty: "Empty Repository"
        case .repositoryReady: "Repository Workspace"
        case .permissionFailure: "Permission Failure"
        case .databaseCorrupt: "Database Corruption"
        case .iCloudPlaceholder: "iCloud Placeholder"
        case .importConflict: "Import Conflict"
        case .importEntry: "Import Entry"
        case .importFolderPreview: "Import Folder Preview"
        case .importProgress: "Import Progress"
        case .importResult: "Import Result"
        case .mainRepositoryContent: "Repository Content"
        case .syncConflict: "Sync Conflict"
        case .syncConflictsICloudList: "iCloud Conflict List"
        case .syncConflictsICloudMinimal: "iCloud Conflict Resolution"
        case .syncConflictsEntry: "Sync Conflict Entry"
        case .syncConflictsReplaceConfirmation: "Sync Conflict Replace Confirmation"
        case .syncConflictsReview: "Sync Conflict Review"
        case .aiUnavailable: "AI Unavailable"
        case .aiCallLog: "AI Call Log"
        case .aiClassificationSuggestion: "AI Classification Suggestion"
        case .aiPrivacyRules: "AI Privacy Rules"
        case .aiSettings: "AI Settings"
        case .aiSummaryEditor: "AI Summary Editor"
        case .aiTagSuggestions: "AI Tag Suggestions"
        case .aiLocalModelStatus: "Local Model Status"
        case .aiRemoteModelConfig: "Remote Model Configuration"
        case .disabled: "Disabled Controls"
        case .staleData: "Stale Data"
        case .longContent: "Long Content"
        case .largeData: "Large Data Set"
        case .searchQueryError: "Search Query Error"
        case .searchSavedSearch: "Save Search"
        case .searchEmpty: "Empty Search Results"
        case .searchIndexStatus: "Search Index Status"
        case .searchSemanticResults: "Semantic Search Results"
        case .searchSmartList: "Smart List Management"
        case .fileActionsBatchAddTags: "Batch Add Tags"
        case .fileActionsBatchChangeCategory: "Batch Change Category"
        case .fileActionsBatchDelete: "Batch Delete"
        case .fileActionsBatchRename: "Batch Rename"
        case .fileActionsChangeCategory: "Change Category"
        case .fileActionsClassifierImpact: "Classifier Impact Preview"
        case .fileActionsDelete: "Delete File"
        case .fileActionsRename: "Rename File"
        case .fileActionsReplace: "Replace File"
        case .fileActionsTagSuggestions: "Tag Suggestions"
        case .fileActionsUndoHistory: "Undo History"
        case .settingsAbout: "About Settings"
        case .settingsAdvanced: "Advanced Settings"
        case .settingsClassifier: "Classifier Settings"
        case .settingsGeneral: "General Settings"
        case .settingsIntegrations: "Integrations Settings"
        case .settingsLanguage: "Language Settings"
        case .settingsPlatformDifferences: "Platform Differences"
        case .settingsRepository: "Repository Settings"
        }
    }

    var feature: String {
        switch self {
        case .launcher, .uiCatalog, .disabled, .longContent, .largeData: "UIFoundation"
        case .commandPalette: "CommandPalette"
        case .detailLog, .detailNote, .detailPane, .detailMultiSelection: "Detail"
        case .diagnosticsConsole, .diagnosticsPackagePreview, .diagnosticsSettings: "Diagnostics"
        case .onboardingConfirm, .onboardingDatabaseRepair, .onboardingDone, .onboardingFailed,
             .onboardingInitializing, .onboardingRecovery, .onboardingValidatePath: "Onboarding"
        case .onboarding, .loading, .permissionFailure, .databaseCorrupt: "RepositoryLifecycle"
        case .repositoryEmpty, .repositoryReady, .staleData: "Library"
        case .iCloudPlaceholder, .importConflict: "Ingestion"
        case .importEntry, .importFolderPreview, .importProgress, .importResult: "Import"
        case .mainRepositoryContent: "MainList"
        case .syncConflict: "Operations"
        case .syncConflictsICloudList, .syncConflictsICloudMinimal, .syncConflictsEntry,
             .syncConflictsReplaceConfirmation, .syncConflictsReview: "SyncConflicts"
        case .aiUnavailable, .aiCallLog, .aiClassificationSuggestion, .aiPrivacyRules,
             .aiSettings, .aiSummaryEditor, .aiTagSuggestions, .aiLocalModelStatus,
             .aiRemoteModelConfig: "AI"
        case .searchQueryError, .searchSavedSearch, .searchEmpty, .searchIndexStatus,
             .searchSemanticResults, .searchSmartList: "Search"
        case .fileActionsBatchAddTags, .fileActionsBatchChangeCategory, .fileActionsBatchDelete,
             .fileActionsBatchRename, .fileActionsChangeCategory, .fileActionsClassifierImpact,
             .fileActionsDelete, .fileActionsRename, .fileActionsReplace,
             .fileActionsTagSuggestions, .fileActionsUndoHistory: "FileActions"
        case .settingsAbout, .settingsAdvanced, .settingsClassifier, .settingsGeneral,
             .settingsIntegrations, .settingsLanguage, .settingsPlatformDifferences,
             .settingsRepository: "Settings"
        }
    }

    var stateKind: AreaMatrixPreviewStateKind {
        switch self {
        case .loading, .onboardingInitializing, .importProgress: .loading
        case .repositoryEmpty, .searchEmpty: .empty
        case .permissionFailure, .databaseCorrupt, .onboardingFailed, .onboardingRecovery,
             .searchQueryError: .failed
        case .disabled: .disabled
        case .iCloudPlaceholder, .importConflict, .syncConflict, .onboardingDatabaseRepair,
             .syncConflictsICloudList, .syncConflictsICloudMinimal, .syncConflictsEntry,
             .syncConflictsReplaceConfirmation, .syncConflictsReview: .blocked
        case .staleData: .stale
        case .aiUnavailable, .searchIndexStatus: .unavailable
        case .launcher, .uiCatalog, .onboarding, .onboardingConfirm, .onboardingDone,
             .onboardingValidatePath, .repositoryReady, .longContent, .largeData,
             .commandPalette, .detailLog, .detailNote, .detailPane, .detailMultiSelection,
             .diagnosticsConsole, .diagnosticsPackagePreview, .diagnosticsSettings,
             .aiCallLog, .aiClassificationSuggestion, .aiPrivacyRules, .aiSettings,
             .aiSummaryEditor, .aiTagSuggestions, .aiLocalModelStatus, .aiRemoteModelConfig,
             .searchSavedSearch, .searchSemanticResults, .searchSmartList,
             .fileActionsBatchAddTags, .fileActionsBatchChangeCategory, .fileActionsBatchDelete,
             .fileActionsBatchRename, .fileActionsChangeCategory, .fileActionsClassifierImpact,
             .fileActionsDelete, .fileActionsRename, .fileActionsReplace,
             .fileActionsTagSuggestions, .fileActionsUndoHistory,
             .importEntry, .importFolderPreview, .importResult,
             .mainRepositoryContent,
             .settingsAbout, .settingsAdvanced, .settingsClassifier, .settingsGeneral,
             .settingsIntegrations, .settingsLanguage, .settingsPlatformDifferences,
             .settingsRepository: .success
        }
    }
}

enum AreaMatrixDeveloperSurfaceFeature: String, CaseIterable {
    case artificialIntelligence = "AI"
    case commandPalette = "CommandPalette"
    case detail = "Detail"
    case diagnostics = "Diagnostics"
    case fileActions = "FileActions"
    case `import` = "Import"
    case mainList = "MainList"
    case onboarding = "Onboarding"
    case repositoryLifecycle = "RepositoryLifecycle"
    case search = "Search"
    case settings = "Settings"
    case syncConflicts = "SyncConflicts"
}

struct AreaMatrixDeveloperSurface: Identifiable {
    let id: String
    let feature: AreaMatrixDeveloperSurfaceFeature
    let scenarios: [AreaMatrixDeveloperScenario]

    init(
        _ id: String,
        feature: AreaMatrixDeveloperSurfaceFeature,
        scenarios: [AreaMatrixDeveloperScenario] = []
    ) {
        self.id = id
        self.feature = feature
        self.scenarios = scenarios
    }

    var hasFullPageScenario: Bool {
        !scenarios.isEmpty
    }
}

enum AreaMatrixDeveloperSurfaceInventory {
    /// This is the product-page denominator. Component and stress scenarios remain useful,
    /// but they do not count as full-page Canvas coverage.
    static let all: [AreaMatrixDeveloperSurface] = [
        .init("AI.AICallLogView", feature: .artificialIntelligence, scenarios: [.aiCallLog]),
        .init(
            "AI.AIClassificationSuggestionPanel",
            feature: .artificialIntelligence,
            scenarios: [.aiClassificationSuggestion]
        ),
        .init("AI.AIPrivacyRulesRouteView", feature: .artificialIntelligence, scenarios: [.aiPrivacyRules]),
        .init("AI.AISettingsPane", feature: .artificialIntelligence, scenarios: [.aiSettings]),
        .init("AI.AISummaryEditorView", feature: .artificialIntelligence, scenarios: [.aiSummaryEditor]),
        .init("AI.AITagSuggestionsPanel", feature: .artificialIntelligence, scenarios: [.aiTagSuggestions]),
        .init("AI.LocalModelStatusView", feature: .artificialIntelligence, scenarios: [.aiLocalModelStatus]),
        .init("AI.RemoteModelConfigSheet", feature: .artificialIntelligence, scenarios: [.aiRemoteModelConfig]),
        .init("CommandPalette.CommandPaletteView", feature: .commandPalette, scenarios: [.commandPalette]),
        .init("Detail.DetailLogTabView", feature: .detail, scenarios: [.detailLog]),
        .init("Detail.DetailNoteTabView", feature: .detail, scenarios: [.detailNote]),
        .init("Detail.MainRepositoryDetailPane", feature: .detail, scenarios: [.detailPane]),
        .init(
            "Detail.MultiSelectionDetailSummary",
            feature: .detail,
            scenarios: [.detailMultiSelection]
        ),
        .init(
            "Diagnostics.DiagnosticsConsoleView",
            feature: .diagnostics,
            scenarios: [.diagnosticsConsole]
        ),
        .init(
            "Diagnostics.DiagnosticsPackagePreviewSheet",
            feature: .diagnostics,
            scenarios: [.diagnosticsPackagePreview]
        ),
        .init(
            "Diagnostics.DiagnosticsSettingsPane",
            feature: .diagnostics,
            scenarios: [.diagnosticsSettings]
        ),
        .init("FileActions.BatchAddTagsSheet", feature: .fileActions, scenarios: [.fileActionsBatchAddTags]),
        .init(
            "FileActions.BatchChangeCategorySheet",
            feature: .fileActions,
            scenarios: [.fileActionsBatchChangeCategory]
        ),
        .init("FileActions.BatchDeleteConfirmSheet", feature: .fileActions, scenarios: [.fileActionsBatchDelete]),
        .init("FileActions.BatchRenameSheet", feature: .fileActions, scenarios: [.fileActionsBatchRename]),
        .init("FileActions.ChangeCategorySheet", feature: .fileActions, scenarios: [.fileActionsChangeCategory]),
        .init(
            "FileActions.ClassifierImpactPreviewSheet",
            feature: .fileActions,
            scenarios: [.fileActionsClassifierImpact]
        ),
        .init("FileActions.DeleteFileConfirmSheet", feature: .fileActions, scenarios: [.fileActionsDelete]),
        .init("FileActions.RenameFileSheet", feature: .fileActions, scenarios: [.fileActionsRename]),
        .init("FileActions.ReplaceConfirmSheet", feature: .fileActions, scenarios: [.fileActionsReplace]),
        .init("FileActions.TagSuggestionsPanel", feature: .fileActions, scenarios: [.fileActionsTagSuggestions]),
        .init("FileActions.UndoHistoryPanel", feature: .fileActions, scenarios: [.fileActionsUndoHistory]),
        .init("Import.ImportEntrySheetView", feature: .import, scenarios: [.importEntry]),
        .init("Import.ImportFolderPreviewView", feature: .import, scenarios: [.importFolderPreview]),
        .init("Import.ImportProgressView", feature: .import, scenarios: [.importProgress]),
        .init("Import.ImportResultView", feature: .import, scenarios: [.importResult]),
        .init(
            "MainList.MainRepositoryContentView",
            feature: .mainList,
            scenarios: [.mainRepositoryContent]
        ),
        .init("Onboarding.ConfirmInitStepView", feature: .onboarding, scenarios: [.onboardingConfirm]),
        .init("Onboarding.DBRepairConfirmView", feature: .onboarding, scenarios: [.onboardingDatabaseRepair]),
        .init("Onboarding.InitDoneStepView", feature: .onboarding, scenarios: [.onboardingDone]),
        .init("Onboarding.InitFailedStepView", feature: .onboarding, scenarios: [.onboardingFailed]),
        .init("Onboarding.InitializingStepView", feature: .onboarding, scenarios: [.onboardingInitializing]),
        .init("Onboarding.MainLoadingView", feature: .onboarding, scenarios: [.loading]),
        .init(
            "Onboarding.StartupRecoveryErrorRecoveryView",
            feature: .onboarding,
            scenarios: [.onboardingRecovery]
        ),
        .init("Onboarding.ValidatePathStepView", feature: .onboarding, scenarios: [.onboardingValidatePath]),
        .init("Onboarding.WelcomeStepView", feature: .onboarding, scenarios: [.onboarding]),
        .init(
            "RepositoryLifecycle.MainRepoErrorView",
            feature: .repositoryLifecycle,
            scenarios: [.permissionFailure, .databaseCorrupt]
        ),
        .init("Search.QueryErrorRouteView", feature: .search, scenarios: [.searchQueryError]),
        .init("Search.SavedSearchSheetRouteView", feature: .search, scenarios: [.searchSavedSearch]),
        .init("Search.SearchEmptyRouteView", feature: .search, scenarios: [.searchEmpty]),
        .init("Search.SearchIndexingStatusRouteView", feature: .search, scenarios: [.searchIndexStatus]),
        .init("Search.SemanticSearchResultsView", feature: .search, scenarios: [.searchSemanticResults]),
        .init("Search.SmartListManagementSheet", feature: .search, scenarios: [.searchSmartList]),
        .init("Settings.AboutSettingsPane", feature: .settings, scenarios: [.settingsAbout]),
        .init("Settings.AdvancedSettingsPane", feature: .settings, scenarios: [.settingsAdvanced]),
        .init("Settings.ClassifierSettingsPane", feature: .settings, scenarios: [.settingsClassifier]),
        .init("Settings.GeneralSettingsView", feature: .settings, scenarios: [.settingsGeneral]),
        .init("Settings.IntegrationsSettingsPane", feature: .settings, scenarios: [.settingsIntegrations]),
        .init(
            "Settings.LanguageSettingsPane",
            feature: .settings,
            scenarios: [.settingsLanguage]
        ),
        .init(
            "Settings.PlatformDifferencesView",
            feature: .settings,
            scenarios: [.settingsPlatformDifferences]
        ),
        .init("Settings.RepositorySettingsPane", feature: .settings, scenarios: [.settingsRepository]),
        .init(
            "SyncConflicts.ICloudConflictListView",
            feature: .syncConflicts,
            scenarios: [.syncConflictsICloudList]
        ),
        .init(
            "SyncConflicts.ICloudConflictMinimalSheet",
            feature: .syncConflicts,
            scenarios: [.syncConflictsICloudMinimal]
        ),
        .init(
            "SyncConflicts.SyncConflictEntryPanel",
            feature: .syncConflicts,
            scenarios: [.syncConflictsEntry]
        ),
        .init(
            "SyncConflicts.SyncConflictReplaceConfirmationPanel",
            feature: .syncConflicts,
            scenarios: [.syncConflictsReplaceConfirmation]
        ),
        .init(
            "SyncConflicts.SyncConflictReviewView",
            feature: .syncConflicts,
            scenarios: [.syncConflictsReview]
        )
    ]

    static var covered: [AreaMatrixDeveloperSurface] {
        all.filter(\.hasFullPageScenario)
    }

    static var uncovered: [AreaMatrixDeveloperSurface] {
        all.filter { !$0.hasFullPageScenario }
    }
}

@MainActor
struct AreaMatrixDeveloperScenarioView: View {
    @EnvironmentObject private var localizer: AppLocalizer

    let configuration: AreaMatrixDeveloperScenarioConfiguration

    var body: some View {
        Group {
            if configuration.scenario == .launcher {
                AreaMatrixDeveloperScenarioLauncher(initialConfiguration: configuration)
            } else {
                AreaMatrixDeveloperScenarioContent(scenario: configuration.scenario)
                    .preferredColorScheme(configuration.theme.colorScheme)
            }
        }
        .frame(
            width: configuration.viewport.size.width,
            height: configuration.viewport.size.height
        )
        .onAppear(perform: applyLanguage)
        .onChange(of: configuration.language) { _, _ in applyLanguage() }
    }

    private func applyLanguage() {
        localizer.apply(
            configuration.language.appLanguage,
            preferredLanguages: [configuration.language.rawValue]
        )
    }
}
#endif
