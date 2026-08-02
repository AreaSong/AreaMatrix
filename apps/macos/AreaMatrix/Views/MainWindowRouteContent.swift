import SwiftUI

struct MainWindowRouteContent: View {
    @ObservedObject var model: OnboardingModel
    let dependencies: AppDependencyContainer
    @ObservedObject var commandRouter: AppCommandRouter
    private let windowCloser: any WindowClosing

    @MainActor
    init(
        model: OnboardingModel,
        dependencies: AppDependencyContainer,
        commandRouter: AppCommandRouter? = nil,
        windowCloser: (any WindowClosing)? = nil
    ) {
        self.model = model
        self.dependencies = dependencies
        self.commandRouter = commandRouter ?? .shared
        self.windowCloser = windowCloser ?? dependencies.platform.windowCloser
    }

    var body: some View {
        routeBody
            .id(routeIdentity)
            .transition(.areaMatrixScene)
            .animation(.areaMatrixSceneFlow, value: routeIdentity)
    }

    @ViewBuilder
    private var routeBody: some View {
        switch model.route {
        case .loadingConfiguration:
            LoadingConfigurationView()
        case .welcome:
            WelcomeStepView(
                onContinue: model.continueFromWelcome,
                onLearnMore: model.openLearnMore
            )
        case .choosePath:
            choosePathView
        case .validatePath:
            validatePathView
        case let .confirmRepositoryInitialization(draft):
            confirmRepositoryInitializationView(draft)
        case let .initializing(draft):
            initializingView(draft)
        case let .initializationFailed(repoPath, mapping, retryDraft):
            initializationFailedView(repoPath: repoPath, mapping: mapping, canRetry: retryDraft != nil)
        case let .initializationDone(result):
            initializationDoneView(result)
        case let .mainLoading(state):
            mainLoadingView(state)
        case let .mainRepoError(repoPath, mapping):
            mainRepoErrorView(repoPath: repoPath, mapping: mapping)
        case let .dbRepairConfirm(repairRoute):
            dbRepairConfirmView(repairRoute)
        case .settingsRepository:
            SettingsRepositoryReturnView()
        case let .settingsGeneral(opening):
            settingsGeneralView(opening)
        case let .importProgress(state):
            importProgressContent(state)
        case let .importResult(state):
            importResultView(state)
        case let .mainEmpty(opening):
            mainRepositoryContent(opening: opening, state: .empty)
        case let .mainList(opening):
            mainRepositoryContent(opening: opening, state: .list)
        case let .configurationError(failure):
            configurationErrorView(failure)
        }
    }

    private var routeIdentity: String {
        switch model.route {
        case .loadingConfiguration: "loadingConfiguration"
        case .welcome: "welcome"
        case .choosePath: "choosePath"
        case .validatePath: "validatePath"
        case .confirmRepositoryInitialization: "confirmRepositoryInitialization"
        case .initializing: "initializing"
        case .initializationFailed: "initializationFailed"
        case .initializationDone: "initializationDone"
        case .mainLoading: "mainLoading"
        case .mainRepoError: "mainRepoError"
        case .dbRepairConfirm: "dbRepairConfirm"
        case .settingsRepository: "settingsRepository"
        case .settingsGeneral: "settingsGeneral"
        case .importProgress: "importProgress"
        case .importResult: "importResult"
        case .mainEmpty: "mainEmpty"
        case .mainList: "mainList"
        case .configurationError: "configurationError"
        }
    }
}

private extension MainWindowRouteContent {
    var choosePathView: some View {
        ChoosePathStepView(
            pathText: Binding(
                get: { model.repositoryPathText },
                set: { model.updateRepositoryPath($0) }
            ),
            errorMessage: model.repositoryPathError,
            isValidating: model.isValidatingRepositoryPath,
            canContinue: model.canContinueFromChoosePath,
            onBack: model.returnFromChoosePath,
            onChoose: model.chooseRepositoryPath,
            onUseDefault: { Task { await model.useDefaultRepositoryPath() } },
            onContinue: { Task { await model.continueFromChoosePath() } }
        )
    }

    var validatePathView: some View {
        ValidatePathStepView(
            pathText: model.repositoryPathText,
            validation: model.repositoryPathValidation,
            existingRepositoryMetadata: model.existingRepositoryMetadata,
            latestScanSession: model.latestScanSession,
            errorMessage: model.repositoryPathError,
            errorMapping: model.repositoryPathErrorMapping,
            isValidating: model.isValidatingRepositoryPath,
            isICloudRiskAccepted: model.isICloudRiskAccepted,
            canContinue: model.canContinueFromValidatePath,
            primaryActionTitle: model.validatePathPrimaryActionTitle,
            showsCancel: model.validatePathReturnRouteIsSettings,
            onBack: model.returnFromValidatePath,
            onCancel: model.returnFromValidatePath,
            onChangePath: model.showChoosePath,
            onRetry: {
                Task { await model.retryRepositoryPathValidation() }
            },
            onICloudRiskAcceptedChanged: model.updateICloudRiskAccepted,
            onContinue: {
                Task { await model.continueFromValidatePath() }
            }
        )
    }

    func confirmRepositoryInitializationView(_ draft: RepositoryInitializationDraft) -> some View {
        ConfirmInitStepView(
            draft: draft,
            onBack: model.showValidatePath,
            onChangePath: model.showChoosePath,
            onCreateEmpty: {
                Task { await model.createEmptyRepositoryFromConfirmInit() }
            },
            onAdoptExisting: {
                Task { await model.adoptExistingRepositoryFromConfirmInit() }
            },
            onCancelSetup: {
                if model.confirmSetupQuit() {
                    windowCloser.closeKeyWindow()
                }
            }
        )
    }

    func initializingView(_ draft: RepositoryInitializationDraft) -> some View {
        InitializingStepView(
            draft: draft,
            scanSession: model.initializationScanSession,
            recoveryReport: model.initializationRecoveryReport,
            progressWarning: model.initializationProgressWarning,
            isCancellationRequested: model.isInitializationCancellationRequested,
            onCancel: model.requestSetupQuit
        )
    }

    func initializationFailedView(repoPath: String, mapping: CoreErrorMappingSnapshot?, canRetry: Bool) -> some View {
        InitFailedStepView(
            repoPath: repoPath,
            mapping: mapping,
            diagnostics: model.initializationDiagnostics,
            canRetry: canRetry,
            onChangePath: model.showChoosePath,
            onRetry: {
                Task { await model.retryFailedInitialization() }
            },
            onCollectDiagnostics: {
                await model.collectInitializationDiagnostics()
            },
            onQuit: {
                windowCloser.closeKeyWindow()
            }
        )
    }

    func initializationDoneView(_ result: RepositoryInitializationResult) -> some View {
        InitDoneStepView(
            result: result,
            errorMapping: model.initializationOpenErrorMapping,
            onOpenRepository: { Task { await model.openInitializedRepository() } },
            onOpenInFinder: model.openInitializedRepositoryInFinder
        )
    }

    func mainLoadingView(_ state: MainLoadingState) -> some View {
        MainLoadingView(
            state: state,
            isRetryingStartupRecovery: model.isRetryingMainRepository,
            onCancelOpening: model.cancelMainOpening,
            onRetryStartupRecovery: {
                Task { await model.retryMainRepositoryFromError(repoPath: state.repoPath) }
            },
            onRetryTree: {
                Task { await model.retryMainLoadingTree() }
            },
            onRetryOpening: {
                Task { await model.retryMainRepositoryFromError(repoPath: state.repoPath) }
            }
        )
    }

    func mainRepoErrorView(repoPath: String, mapping: CoreErrorMappingSnapshot?) -> some View {
        MainRepoErrorView(
            repoPath: repoPath,
            mapping: mapping,
            validation: model.mainRepoRecoveryValidation,
            isRetrying: model.isRetryingMainRepository,
            retryErrorMapping: model.mainRepoRecoveryErrorMapping,
            externalRemoval: model.mainRepoExternalRemoval,
            diagnostics: model.mainRepoDiagnostics,
            lastOpenedAt: model.mainRepoLastOpenedAt,
            onRetry: {
                Task { await model.retryMainRepositoryFromError(repoPath: repoPath) }
            },
            onReconnectFolder: {
                Task { await model.reconnectMainRepositoryFolder(from: repoPath) }
            },
            onOpenRepair: {
                model.openMainRepositoryRepair(repoPath: repoPath)
            },
            onConfirmExternalRemoval: {
                Task { await model.confirmMainRepositoryExternalRemoval(repoPath: repoPath) }
            },
            onRevealFolder: {
                model.revealMainRepositoryFolder(repoPath: repoPath)
            },
            onRequestDiagnostics: {
                model.requestMainRepositoryDiagnosticsPrivacyConfirmation(repoPath: repoPath)
            },
            onConfirmDiagnostics: {
                Task { await model.collectMainRepositoryDiagnostics(repoPath: repoPath) }
            },
            onCancelDiagnostics: model.cancelMainRepositoryDiagnosticsPrivacyConfirmation,
            onChooseAnotherFolder: model.showChoosePath
        )
    }

    func dbRepairConfirmView(_ repairRoute: DatabaseRepairRouteState) -> some View {
        DBRepairConfirmView(
            repoPath: repairRoute.repoPath,
            scanSession: repairRoute.scanSession,
            mapping: repairRoute.mapping,
            lastOpenedAt: model.mainRepoLastOpenedAt,
            metadataRepairer: dependencies.feature.onboarding.metadataRepairer,
            repositoryReindexer: dependencies.feature.onboarding.repositoryReindexer,
            startupRecoverer: dependencies.feature.onboarding.startupRecoverer,
            repositoryWriteCoordinator: dependencies.feature.onboarding.repositoryWriteCoordinator,
            diagnosticsCollector: dependencies.feature.onboarding.diagnosticsCollector,
            errorMapper: dependencies.feature.onboarding.errorMapper,
            onCancel: {
                model.returnFromDatabaseRepair(repairRoute)
            },
            onRepairSucceeded: { await model.finishWatcherRecoveryRescan(repoPath: repairRoute.repoPath) },
            onOpenRepositoryInFinder: {
                model.revealMainRepositoryFolder(repoPath: repairRoute.repoPath)
            }
        )
    }

    func settingsGeneralView(_ opening: RepositoryOpeningResult) -> some View {
        GeneralSettingsView(
            repoPath: opening.config.repoPath,
            selectedTab: Binding(
                get: { model.settingsGeneralSelectedTab },
                set: { model.settingsGeneralSelectedTab = $0 }
            ),
            onClose: {
                Task { await model.refreshAfterGeneralSettings(opening: opening) }
            },
            onChangeRepository: {
                model.beginSettingsRepositoryChange(from: opening)
            },
            onOpenRepositoryRecovery: {
                model.openMainRepositoryRepair(repoPath: opening.config.repoPath)
            },
            onReturnToWelcome: {
                model.updateRepositoryPath("")
                model.showWelcome()
            },
            featureDependencies: dependencies.feature.settings,
            aiDependencies: dependencies.feature.ai,
            sharedDependencies: dependencies.feature.shared,
            syncConflictsDependencies: dependencies.feature.syncConflicts,
            loader: dependencies.feature.settings.configurationLoader,
            updater: dependencies.feature.settings.configurationUpdater,
            errorMapper: dependencies.feature.shared.errorMapper
        )
    }

    func importResultView(_ state: ImportResultRouteState) -> some View {
        ImportResultView(
            state: state,
            onDone: model.finishImportResult,
            onRetryFailed: {
                Task { await model.retryImportResultFailedItems() }
            },
            onLoadChangeLog: {
                Task { await model.loadImportResultChangeLog() }
            },
            onShowExistingFile: model.showImportResultExistingFile,
            onReviewTagSuggestions: model.reviewImportResultTagSuggestions,
            onRequestExport: model.requestImportResultExportPrivacyConfirmation,
            onConfirmExport: model.exportImportResultDetails,
            onCancelExport: model.cancelImportResultExport
        )
    }

    func configurationErrorView(_ failure: ConfigLoadFailure) -> some View {
        ConfigurationErrorView(
            failure: failure,
            onRetry: {
                Task { await model.retryConfigurationLoad() }
            },
            onStartSetup: model.showWelcome
        )
    }

    func importProgressContent(_ state: ImportProgressRouteState) -> some View {
        ZStack(alignment: .trailing) {
            mainRepositoryContent(
                opening: state.sourceOpening,
                state: .list,
                isImportProgressReadOnly: true,
                importProgressPresentation: ImportProgressListPresentation(items: state.items)
            )
            ImportProgressView(
                state: state,
                onStopAfterCurrentFile: model.stopImportProgressAfterCurrentFile,
                onViewDetails: model.viewImportProgressDetails,
                onRetryCurrentItem: {
                    Task { await model.retryCurrentImportProgressItem() }
                },
                onStopAndViewResults: model.stopImportProgressAndViewResults,
                onRequestDiagnostics: model.requestImportProgressDiagnosticsPrivacyConfirmation,
                onConfirmDiagnostics: {
                    Task { await model.collectImportProgressDiagnostics() }
                },
                onCancelDiagnostics: model.cancelImportProgressDiagnosticsPrivacyConfirmation,
                onOpenRepositoryInFinder: model.openImportProgressRepositoryInFinder
            )
            .frame(width: 380)
            .background(.regularMaterial)
            .overlay(alignment: .leading) {
                Divider()
            }
        }
        .task(id: state.recoveryCheckTaskID) {
            await model.checkImportProgressRecoveryIfNeeded()
        }
    }

    func mainRepositoryContent(
        opening: RepositoryOpeningResult,
        state: MainRepositoryContentState,
        isImportProgressReadOnly: Bool = false,
        importProgressPresentation: ImportProgressListPresentation = .empty
    ) -> MainRepositoryContentView {
        let displayOpening = isImportProgressReadOnly ? opening.importProgressReadOnlyOpening : opening
        return MainRepositoryContentView(
            opening: displayOpening,
            state: state,
            assembly: .live(opening: displayOpening, dependencies: dependencies),
            commandRouter: commandRouter,
            onImport: isImportProgressReadOnly ? {} : { model.chooseImportSources(opening: opening) },
            onDropImport: { urls, destination in
                guard !isImportProgressReadOnly else { return }
                model.startImportEntry(opening: opening, source: .dropZone, urls: urls, destination: destination)
            },
            onOpenSettings: { model.showGeneralSettings(opening: opening) },
            onOpenAISettings: { model.showGeneralSettings(opening: opening, selectedTab: "ai") },
            onOpenRepository: model.showChoosePath,
            onOpenHelp: model.openLearnMore,
            onOpenImportConflictBatch: { model.startImportConflictBatchReview(opening: opening, route: $0) },
            mainListErrorRecoveryActions: MainListErrorRecoveryActions(
                retryFallback: { Task { await model.retryConfigurationLoad() } },
                collectFallbackDiagnostics: { await model.collectMainListDiagnostics(opening: opening) },
                openRepair: { model.openMainRepositoryRepair(repoPath: opening.config.repoPath) },
                openRepairWithMapping: {
                    model.openMainRepositoryRepair(repoPath: opening.config.repoPath, mapping: $0)
                },
                downloadExternalSyncPlaceholder: { relativePath in
                    try await downloadExternalSyncPlaceholder(
                        repoPath: opening.config.repoPath,
                        relativePath: relativePath
                    )
                }
            ),
            onShowInFinder: { model.showMainListFileInFinder(opening: opening, relativePath: $0) },
            onCopyPath: { model.copyMainListPath(opening: opening, relativePath: $0) },
            onCopyPaths: { model.copyMainListPaths(opening: opening, relativePaths: $0) },
            onOpenNoteFile: { model.openMainListFile(opening: opening, relativePath: $0) },
            onOpenChangeCategoryPermissionRecovery: {
                model.revealMainRepositoryFolder(repoPath: opening.config.repoPath)
            },
            externalSyncWindows: model.externalSyncWindows(for: opening),
            onExternalSyncWindowCompleted: model.finishExternalSyncWindow,
            pendingTagSuggestionFocus: model.pendingTagSuggestionFocus,
            onPendingTagSuggestionFocusConsumed: model.consumePendingTagSuggestionFocus,
            importProgressPresentation: importProgressPresentation
        )
    }

    private func downloadExternalSyncPlaceholder(
        repoPath: String,
        relativePath: String
    ) async throws {
        let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL
        let itemURL = repoURL.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
        let repoPrefix = repoURL.path.hasSuffix("/") ? repoURL.path : "\(repoURL.path)/"
        guard itemURL.path.hasPrefix(repoPrefix) else {
            throw AppSemanticError.invalidPath(rawContext: relativePath)
        }
        try await LocalICloudPlaceholderDownloader().downloadPlaceholder(at: itemURL)
    }
}

private extension RepositoryOpeningResult {
    var importProgressReadOnlyOpening: RepositoryOpeningResult {
        var opening = self
        opening.isReadOnly = true
        return opening
    }
}
