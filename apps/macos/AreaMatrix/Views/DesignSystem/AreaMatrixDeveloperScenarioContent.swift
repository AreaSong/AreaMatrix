import AreaMatrixUIFoundation
import SwiftUI

#if DEBUG
@MainActor
struct AreaMatrixDeveloperScenarioContent: View {
    let scenario: AreaMatrixDeveloperScenario

    var body: some View {
        ZStack {
            AreaMatrixAmbientBackground(scene: ambientScene, parallax: .zero, strength: .subdued)
                .ignoresSafeArea()
            content
        }
        .accessibilityIdentifier("developer.scenario.\(scenario.rawValue)")
    }

    @ViewBuilder
    private var content: some View {
        switch scenario {
        case .launcher:
            EmptyView()
        case .uiCatalog:
            AreaMatrixUICatalog()
        case .commandPalette, .detailLog, .detailNote, .detailPane, .detailMultiSelection:
            DeveloperLibraryScenarioView(scenario: scenario)
        case .diagnosticsConsole, .diagnosticsPackagePreview, .diagnosticsSettings:
            DeveloperDiagnosticsScenarioView(scenario: scenario)
        case .onboarding:
            WelcomeStepView(onContinue: {}, onLearnMore: {})
        case .onboardingConfirm, .onboardingDatabaseRepair, .onboardingDone, .onboardingFailed,
             .onboardingInitializing, .onboardingRecovery, .onboardingValidatePath:
            DeveloperOnboardingScenarioView(scenario: scenario)
        case .loading:
            MainLoadingView(
                state: MainLoadingState(
                    repoPath: AreaMatrixPreviewFixtures.repositoryPath,
                    startupRecovery: .checking,
                    treeLoading: .loading
                ),
                isRetryingStartupRecovery: false,
                onCancelOpening: {},
                onRetryStartupRecovery: {},
                onRetryTree: {},
                onRetryOpening: {}
            )
        case .repositoryEmpty:
            AreaMatrixEmptyStateView(
                systemImage: "tray.and.arrow.down",
                title: L10n.string("main.empty.title"),
                message: L10n.string("main.empty.message"),
                primaryTitle: L10n.string("Import..."),
                primaryAction: {}
            )
        case .repositoryReady:
            AreaMatrixPreviewRepositoryWorkspace(rows: AreaMatrixPreviewFixtures.fileRows(count: 12))
        case .permissionFailure:
            repositoryError(mapping: AreaMatrixPreviewFixtures.permissionFailure)
        case .databaseCorrupt:
            repositoryError(mapping: .database(rawContext: "database disk image is malformed"))
        case .iCloudPlaceholder:
            AreaMatrixPreviewICloudPlaceholderView(rows: AreaMatrixPreviewFixtures.iCloudRows)
        case .importConflict:
            AreaMatrixPreviewImportConflictView()
        case .importEntry, .importFolderPreview, .importProgress, .importResult:
            DeveloperImportScenarioView(scenario: scenario)
        case .mainRepositoryContent:
            DeveloperMainListScenarioView()
        case .syncConflict:
            AreaMatrixPreviewSyncConflictView(conflict: AreaMatrixPreviewFixtures.syncConflict)
        case .syncConflictsICloudList, .syncConflictsICloudMinimal, .syncConflictsEntry,
             .syncConflictsReplaceConfirmation, .syncConflictsReview:
            DeveloperSyncConflictScenarioView(scenario: scenario)
        case .aiUnavailable:
            AreaMatrixPreviewAIUnavailableView()
        case .aiCallLog, .aiClassificationSuggestion, .aiPrivacyRules, .aiSettings,
             .aiSummaryEditor, .aiTagSuggestions, .aiLocalModelStatus, .aiRemoteModelConfig:
            DeveloperAIScenarioView(scenario: scenario)
        case .disabled:
            AreaMatrixPreviewDisabledControlsView()
        case .staleData:
            AreaMatrixPreviewStaleDataView()
        case .longContent:
            AreaMatrixPreviewLongContentView()
        case .largeData:
            AreaMatrixPreviewLargeDataView(rows: AreaMatrixPreviewFixtures.fileRows(count: 120))
        case .searchQueryError, .searchSavedSearch, .searchEmpty, .searchIndexStatus,
             .searchSemanticResults, .searchSmartList:
            DeveloperSearchScenarioView(scenario: scenario)
        case .fileActionsBatchAddTags, .fileActionsBatchChangeCategory, .fileActionsBatchDelete,
             .fileActionsBatchRename, .fileActionsChangeCategory, .fileActionsClassifierImpact,
             .fileActionsDelete, .fileActionsRename, .fileActionsReplace,
             .fileActionsTagSuggestions, .fileActionsUndoHistory:
            DeveloperFileActionScenarioView(scenario: scenario)
        case .settingsAbout, .settingsAdvanced, .settingsClassifier, .settingsGeneral,
             .settingsIntegrations, .settingsLanguage, .settingsPlatformDifferences,
             .settingsRepository:
            DeveloperSettingsScenarioView(scenario: scenario)
        }
    }

    private var ambientScene: AreaMatrixAmbientScene {
        switch scenario {
        case .onboarding, .onboardingConfirm, .onboardingDone, .onboardingValidatePath,
             .repositoryEmpty, .repositoryReady, .uiCatalog, .launcher: .home
        case .loading, .largeData, .onboardingInitializing: .tracking
        case .permissionFailure, .databaseCorrupt, .staleData, .longContent,
             .onboardingDatabaseRepair, .onboardingFailed, .onboardingRecovery: .help
        case .iCloudPlaceholder, .importConflict, .importEntry, .importFolderPreview,
             .importProgress, .importResult: .classify
        case .syncConflict, .syncConflictsICloudList, .syncConflictsICloudMinimal,
             .syncConflictsEntry, .syncConflictsReplaceConfirmation, .syncConflictsReview: .security
        case .aiUnavailable, .aiCallLog, .aiClassificationSuggestion, .aiPrivacyRules,
             .aiSettings, .aiSummaryEditor, .aiTagSuggestions, .aiLocalModelStatus,
             .aiRemoteModelConfig, .disabled, .searchQueryError, .searchSavedSearch, .searchEmpty,
             .searchIndexStatus, .searchSemanticResults, .searchSmartList,
             .commandPalette, .detailLog, .detailNote, .detailPane, .detailMultiSelection,
             .diagnosticsConsole, .diagnosticsPackagePreview, .diagnosticsSettings,
             .fileActionsBatchAddTags, .fileActionsBatchChangeCategory, .fileActionsBatchDelete,
             .fileActionsBatchRename, .fileActionsChangeCategory, .fileActionsClassifierImpact,
             .fileActionsDelete, .fileActionsRename, .fileActionsReplace,
             .fileActionsTagSuggestions, .fileActionsUndoHistory,
             .mainRepositoryContent,
             .settingsAbout, .settingsAdvanced, .settingsClassifier,
             .settingsGeneral, .settingsIntegrations, .settingsLanguage,
             .settingsPlatformDifferences, .settingsRepository: .start
        }
    }

    private func repositoryError(mapping: CoreErrorMappingSnapshot) -> some View {
        MainRepoErrorView(
            repoPath: AreaMatrixPreviewFixtures.longRepositoryPath,
            mapping: mapping,
            onChooseAnotherFolder: {}
        )
    }
}

private struct AreaMatrixPreviewRepositoryWorkspace: View {
    let rows: [ImportFolderPreviewRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("Files"))
                        .font(.title2.bold())
                    Text(AreaMatrixPreviewFixtures.repositoryPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.string("Import...")) {}
                    .buttonStyle(AreaMatrixPrimaryButtonStyle())
            }
            .padding(20)
            Divider()
            HSplitView {
                List {
                    Label(developerText("All Files"), systemImage: "tray.full")
                    Label(developerText("Documents"), systemImage: "doc")
                    Label(L10n.string("Needs Review"), systemImage: "exclamationmark.triangle")
                }
                .frame(minWidth: 180, idealWidth: 210)

                AreaMatrixPreviewFileTable(rows: rows)
                    .padding(12)
            }
        }
        .background(.background)
    }
}

private struct AreaMatrixPreviewICloudPlaceholderView: View {
    let rows: [ImportFolderPreviewRow]

    var body: some View {
        AreaMatrixPreviewFeaturePanel(
            title: L10n.verbatim("iCloud Placeholder", reason: .technicalIdentifier),
            subtitle: L10n.verbatim("Ingestion · Blocked", reason: .technicalIdentifier)
        ) {
            ImportFolderICloudSummarySection(
                iCloudPlaceholderCount: rows.count,
                isDownloading: false,
                downloadErrorMessage: nil,
                onDownloadAndRetry: {},
                onSwitchToLocalRepo: {}
            )
            .padding(16)
            .areaMatrixGlassCard(cornerRadius: 12)
            AreaMatrixPreviewFileTable(rows: rows)
                .frame(minHeight: 260)
        }
    }
}

private struct AreaMatrixPreviewImportConflictView: View {
    @State private var duplicateResolution: SingleFileDuplicateResolutionStrategy = .keepBoth
    @State private var nameResolution: ImportSingleFileNameConflictResolution = .keepBoth

    private let result = ImportSingleFilePreflightResult(
        sourceSizeBytes: 2048,
        sourceModifiedAt: 1_778_738_400,
        hashSha256: "incoming-preview-hash",
        targetRelativePath: "docs/report.pdf",
        conflict: .name(path: "docs/report.pdf"),
        keepBothTargetRelativePath: "docs/report_2.pdf"
    )

    var body: some View {
        AreaMatrixPreviewFeaturePanel(
            title: L10n.verbatim("Import Conflict", reason: .technicalIdentifier),
            subtitle: L10n.verbatim("Ingestion · Blocked", reason: .technicalIdentifier)
        ) {
            ImportSingleFileConflictSection(
                result: result,
                activePage: ImportSingleFileConflictPage(conflict: result.conflict),
                sourceFilename: "report.pdf",
                sourcePath: "/Users/example/Downloads/report.pdf",
                replaceOptionVisibility: .enabled,
                duplicateResolution: $duplicateResolution,
                nameConflictResolution: $nameResolution,
                resolvedNameConflictFilename: "report_2.pdf",
                resolvedNameConflictPath: "docs/report_2.pdf",
                nameConflictBlockingReason: nil,
                existingFile: nil,
                duplicateReplaceActionTitle: L10n.string("Replace"),
                isReplaceConfirmed: false,
                onBeginReplaceConfirmation: {},
                onShowExistingFile: { _ in },
                onRenameNameConflictFile: { nameResolution = .renameIncoming($0) }
            )
            .padding(20)
            .areaMatrixGlassCard(cornerRadius: 12)
        }
    }
}

private struct AreaMatrixPreviewSyncConflictView: View {
    let conflict: SyncConflictSnapshot

    var body: some View {
        AreaMatrixPreviewFeaturePanel(
            title: L10n.verbatim("Sync Conflict", reason: .technicalIdentifier),
            subtitle: L10n.verbatim("Operations · Blocked", reason: .technicalIdentifier)
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SyncConflictReviewSummarySection(conflict: conflict)
                    SyncConflictReviewVersionsSection(files: conflict.affectedFiles)
                }
                .padding(20)
            }
        }
    }
}

private struct AreaMatrixPreviewAIUnavailableView: View {
    var body: some View {
        AreaMatrixPreviewFeaturePanel(
            title: L10n.verbatim("AI Unavailable", reason: .technicalIdentifier),
            subtitle: L10n.verbatim("AI · Unavailable", reason: .technicalIdentifier)
        ) {
            VStack(alignment: .leading, spacing: 18) {
                AISummaryGateNoticeView(
                    notice: .providerUnavailable(nil),
                    repoPath: AreaMatrixPreviewFixtures.repositoryPath,
                    accessibilityID: "developer.aiUnavailable",
                    onOpenAISettings: {},
                    onOpenPrivacyRule: { _ in }
                )
                Text(L10n.string("AI is off. AreaMatrix will not call local or remote models."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(L10n.string("Open AI settings")) {}
                    .buttonStyle(AreaMatrixPrimaryButtonStyle())
            }
            .padding(22)
            .areaMatrixGlassCard(cornerRadius: 12)
        }
    }
}

private struct AreaMatrixPreviewDisabledControlsView: View {
    @State private var toggle = false

    var body: some View {
        AreaMatrixPreviewFeaturePanel(
            title: L10n.verbatim("Disabled Controls", reason: .technicalIdentifier),
            subtitle: L10n.verbatim("UIFoundation · Disabled", reason: .technicalIdentifier)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(L10n.string("Enable AI features"), isOn: $toggle)
                TextField(L10n.string("Search files..."), text: .constant(""))
                Button(L10n.string("Import...")) {}
                    .buttonStyle(AreaMatrixPrimaryButtonStyle())
                Text(L10n.string("Remote AI is not configured"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .disabled(true)
            .padding(22)
            .areaMatrixGlassCard(cornerRadius: 12)
        }
    }
}

private struct AreaMatrixPreviewStaleDataView: View {
    var body: some View {
        AreaMatrixPreviewFeaturePanel(
            title: L10n.verbatim("Stale Data", reason: .technicalIdentifier),
            subtitle: L10n.verbatim("Library · Stale", reason: .technicalIdentifier)
        ) {
            ReasonStatusCard(
                badge: developerText("STALE"),
                badgeTint: .orange,
                accessibilityIdentifier: "developer.staleData",
                badgeAccessibilityIdentifier: "developer.staleData.badge"
            ) {
                Text(L10n.string("Refresh required"))
                    .font(.headline)
            } message: {
                Text(L10n.string("Refresh the conflict entry list and choose another item."))
                    .foregroundStyle(.secondary)
            } actions: {
                Button(L10n.string("Refresh")) {}
            }
            .padding(22)
        }
    }
}

private struct AreaMatrixPreviewLongContentView: View {
    var body: some View {
        AreaMatrixPreviewFeaturePanel(
            title: L10n.verbatim("Long Content", reason: .technicalIdentifier),
            subtitle: L10n.verbatim("UIFoundation · Success", reason: .technicalIdentifier)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(developerText(
                    "A deliberately long localized-style heading verifies wrapping " +
                        "without clipping controls or actions."
                ))
                .font(.title2.bold())
                Text(developerText(
                    "This scenario keeps an unusually long explanation visible across compact and wide windows " +
                        "so layout regressions are caught in Canvas before a full application run."
                ))
                .foregroundStyle(.secondary)
                AreaMatrixPathBox(
                    path: AreaMatrixPreviewFixtures.longRepositoryPath,
                    style: .glass,
                    lineLimit: 4,
                    alignment: .leading
                )
                Button(L10n.string("Retry")) {}
                    .buttonStyle(AreaMatrixPrimaryButtonStyle())
            }
            .padding(24)
            .areaMatrixGlassCard(cornerRadius: 12)
        }
    }
}

private struct AreaMatrixPreviewLargeDataView: View {
    let rows: [ImportFolderPreviewRow]

    var body: some View {
        AreaMatrixPreviewFeaturePanel(
            title: L10n.verbatim("Large Data Set", reason: .technicalIdentifier),
            subtitle: L10n.verbatim("UIFoundation · Success", reason: .technicalIdentifier)
        ) {
            HStack {
                Text(L10n.plural("import.folder.file-count", count: rows.count))
                    .font(.headline)
                Spacer()
                ProgressView(value: 0.78)
                    .frame(width: 180)
            }
            .padding(.horizontal, 18)
            AreaMatrixPreviewFileTable(rows: rows)
        }
    }
}

private struct AreaMatrixPreviewFileTable: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let rows: [ImportFolderPreviewRow]

    var body: some View {
        Table(rows) {
            TableColumn(L10n.string("File")) { row in
                Text(row.originalName).lineLimit(1)
            }
            TableColumn(L10n.string("Relative path")) { row in
                Text(row.relativePath).lineLimit(1)
            }
            TableColumn(L10n.string("Suggested category")) { row in
                Text(row.predictedCategory ?? developerText("inbox"))
            }
            TableColumn(L10n.string("Status")) { row in
                Text(localizer.resolve(row.status.tagMessage))
                    .font(.caption.bold())
            }
        }
    }
}

private struct AreaMatrixPreviewFeaturePanel<Content: View>: View {
    let title: AppDisplayText
    let subtitle: AppDisplayText
    let content: Content

    init(title: AppDisplayText, subtitle: AppDisplayText, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.resolve(title)).font(.title2.bold())
                Text(L10n.resolve(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(24)
        .frame(maxWidth: 860, maxHeight: .infinity, alignment: .topLeading)
    }
}

private func developerText(_ value: String) -> String {
    L10n.resolve(L10n.verbatim(value, reason: .technicalIdentifier))
}
#endif
