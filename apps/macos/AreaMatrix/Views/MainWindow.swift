import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: OnboardingModel
    @StateObject private var externalCreatedFileWatcher: MainExternalCreatedFileWatcher
    @ObservedObject private var observabilityRuntime: ObservabilityRuntimeAssembly
    @ObservedObject private var commandRouter: AppCommandRouter
    private let dependencies: AppDependencyContainer
    private let importProgressControlState: ImportProgressControlState
    private let windowCloser: any WindowClosing

    @MainActor
    init(
        model: OnboardingModel? = nil,
        dependencies: AppDependencyContainer,
        observabilityRuntime: ObservabilityRuntimeAssembly,
        commandRouter: AppCommandRouter,
        windowCloser: (any WindowClosing)? = nil
    ) {
        let resolvedDependencies = dependencies
        let resolvedModel = model ?? OnboardingModel(dependencies: resolvedDependencies)
        let resolvedWindowCloser = windowCloser ?? resolvedDependencies.platform.windowCloser
        self.dependencies = dependencies
        _model = StateObject(wrappedValue: resolvedModel)
        _externalCreatedFileWatcher = StateObject(wrappedValue: MainExternalCreatedFileWatcher(
            cursorStore: resolvedModel.externalChangesSyncer,
            inFlightTracker: resolvedDependencies.platform.inFlightFileChangeTracker
        ))
        importProgressControlState = resolvedModel.importProgressControlState
        _observabilityRuntime = ObservedObject(wrappedValue: observabilityRuntime)
        _commandRouter = ObservedObject(wrappedValue: commandRouter)
        self.windowCloser = resolvedWindowCloser
    }
}

extension MainWindow {
    var body: some View {
        _ = localizer.resourceLocaleIdentifier
        return ZStack(alignment: .top) {
            MainWindowRouteContent(
                model: model,
                dependencies: dependencies,
                commandRouter: commandRouter,
                windowCloser: windowCloser
            )

            if let toastMessage = model.toastMessage {
                Text(localizer.resolve(toastMessage))
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let notice = observabilityRuntime.recoveryNotice {
                ObservabilityRecoveryBanner(
                    incidentID: notice.incidentID,
                    onOpen: openRecoveredIncident,
                    onDismiss: observabilityRuntime.dismissRecoveryNotice
                )
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(
            minWidth: minWindowWidth,
            maxWidth: maxWindowWidth,
            minHeight: minWindowHeight,
            maxHeight: maxWindowHeight
        )
        .environment(\.areaMatrixInteractionFeedback, dependencies.platform.interactionFeedback)
        .background {
            if case .welcome = model.route {
                Color.clear
            } else if isOnboardingRoute {
                AreaMatrixAmbientBackground(
                    scene: routeAmbientScene,
                    parallax: .zero,
                    strength: .standard
                )
                .ignoresSafeArea()
            } else {
                AreaMatrixAmbientBackground(
                    scene: routeAmbientScene,
                    parallax: .zero,
                    strength: .subdued
                )
                .ignoresSafeArea()
            }
        }
        .background {
            if usesCustomWindowChrome {
                AreaMatrixWindowChromeObserver()
            }
        }
        .background(WindowCloseConfirmationObserver(
            shouldConfirm: { model.shouldConfirmSetupExit },
            onAttemptClose: model.requestSetupQuit
        ))
        .onExitCommand(perform: model.requestSetupQuit)
        .confirmationDialog(
            setupQuitConfirmationTitle,
            isPresented: Binding(
                get: { model.isSetupQuitConfirmationPresented },
                set: { if !$0 { model.cancelSetupQuit() } }
            )
        ) {
            Button(setupQuitConfirmationActionTitle, role: .destructive) {
                if model.confirmSetupQuit() {
                    windowCloser.closeKeyWindow()
                }
            }
            Button(L10n.string("Cancel"), role: .cancel, action: model.cancelSetupQuit)
        } message: {
            Text(setupQuitConfirmationMessage)
        }
        .task {
            await model.bootstrapIfNeeded()
            model.consumePendingDockOpenRequests()
        }
        .onReceive(commandRouter.commands) { command in
            switch command {
            case .dockOpenRequested:
                model.consumePendingDockOpenRequests()
            case .importRequested:
                model.handleImportMenuCommand()
            case .settingsRequested:
                model.handleSettingsMenuCommand()
            case .externalSyncRequested:
                model.consumePendingExternalSyncWindows(repoPath: activeMainRepositoryPath)
            default:
                break
            }
        }
        .sheet(isPresented: $model.isAppLanguageSettingsPresented) {
            AppLanguageSettingsSheet(onClose: model.closeAppLanguageSettings)
        }
        .task(id: activeMainRepositoryPath) {
            guard let activeMainRepositoryPath else {
                externalCreatedFileWatcher.stop()
                return
            }
            model.consumePendingExternalSyncWindows(repoPath: activeMainRepositoryPath)
            await externalCreatedFileWatcher.start(repoPath: activeMainRepositoryPath)
        }
        .onChange(of: externalCreatedFileWatcher.recoveryRequest) { _, request in
            if let request { model.handleExternalWatcherRecovery(request) }
        }
        .sheet(item: $model.pendingImportEntry) { request in
            ImportEntrySheetView(
                request: request,
                onCancel: model.dismissImportEntry,
                onSwitchToLocalRepo: model.switchImportEntryToLocalRepository,
                onImportStarted: model.beginImportEntryProgress,
                onImportStartedWithRetryContext: importRetryContextHandler(for: request),
                onImportFailed: model.failImportEntry,
                onBatchImportProgress: model.updateImportEntryProgress,
                onBatchImportFailed: model.failImportEntry,
                onBatchImportResults: model.showImportEntryResults,
                importProgressControlState: importProgressControlState,
                onImported: { repoPath, entry in
                    Task {
                        await model.finishImportEntry(repoPath: repoPath, entry: entry)
                    }
                },
                onShowExistingFile: model.showImportEntryExistingFile,
                fileResourceAccess: dependencies.feature.import.fileResourceAccess,
                categoryPredictor: dependencies.feature.import.categoryPredictor,
                batchFileLoader: dependencies.feature.import.batchFileLoader,
                fileImporter: dependencies.feature.import.fileImporter,
                batchFileImporter: dependencies.feature.import.batchFileImporter,
                batchConflictBatcher: dependencies.feature.import.conflictBatcher,
                undoActionStore: dependencies.feature.import.undoActionStore,
                folderScanner: dependencies.feature.import.folderScanner,
                sourcePreflightInspector: dependencies.feature.import.sourcePreflightInspector,
                placeholderDownloader: dependencies.feature.import.placeholderDownloader,
                errorMapper: dependencies.feature.shared.errorMapper,
                batchSessionStore: model.importBatchSessionStore,
                actionLogger: dependencies.feature.import.actionLogger
            )
        }
    }

    private var isConfirmingInitializationCancel: Bool {
        if case .initializing = model.route { return true }
        return false
    }

    private var usesCustomWindowChrome: Bool {
        switch model.route {
        case .loadingConfiguration, .choosePath, .validatePath,
             .confirmRepositoryInitialization, .initializing, .initializationFailed,
             .initializationDone, .configurationError:
            true
        default:
            false
        }
    }

    private var isOnboardingRoute: Bool {
        switch model.route {
        case .loadingConfiguration, .welcome, .choosePath, .validatePath,
             .confirmRepositoryInitialization, .initializing, .initializationFailed,
             .initializationDone, .configurationError:
            true
        default:
            false
        }
    }

    private var routeAmbientScene: AreaMatrixAmbientScene {
        switch model.route {
        case .choosePath: .classify
        case .validatePath, .confirmRepositoryInitialization: .security
        case .initializing, .mainLoading, .importProgress: .tracking
        case .initializationFailed, .mainRepoError, .dbRepairConfirm: .help
        case .initializationDone, .importResult: .start
        case .settingsGeneral, .settingsRepository: .home
        case .mainEmpty, .mainList: .home
        default: .home
        }
    }

    private var minWindowWidth: CGFloat {
        isOnboardingRoute ? 860 : 760
    }

    private var maxWindowWidth: CGFloat? {
        isOnboardingRoute ? 860 : nil
    }

    private var minWindowHeight: CGFloat {
        isOnboardingRoute ? 680 : 520
    }

    private var maxWindowHeight: CGFloat? {
        isOnboardingRoute ? 680 : nil
    }

    private var setupQuitConfirmationTitle: String {
        isConfirmingInitializationCancel
            ? L10n.string("onboarding.quit.initializationTitle")
            : L10n.string("onboarding.confirm.quitSetup")
    }

    private var setupQuitConfirmationActionTitle: String {
        isConfirmingInitializationCancel
            ? L10n.string("onboarding.quit.stopAtSafePoint")
            : L10n.string("onboarding.confirm.quit")
    }

    private var setupQuitConfirmationMessage: String {
        if isConfirmingInitializationCancel {
            return L10n.string("onboarding.quit.safePointMessage")
        }

        return L10n.string("onboarding.quit.setupMessage")
    }

    private var activeMainRepositoryPath: String? {
        switch model.route {
        case let .mainEmpty(opening), let .mainList(opening), let .settingsGeneral(opening):
            opening.config.repoPath
        default:
            nil
        }
    }

    private func importRetryContextHandler(for request: ImportEntryRequest) -> (
        String,
        String,
        ImportSingleFileStorageMode,
        String,
        String,
        ImportDuplicateStrategySnapshot
    ) -> Void {
        { currentPath, sourcePath, storageMode, overrideCategory, overrideFilename, duplicateStrategy in
            model.beginImportEntryProgress(
                currentPath: currentPath,
                retryContext: ImportProgressRetryContext(
                    repoPath: request.repoPath,
                    sourcePath: sourcePath,
                    storageMode: storageMode,
                    overrideCategory: overrideCategory,
                    overrideFilename: overrideFilename,
                    duplicateStrategy: ImportProgressDuplicateStrategy(coreStrategy: duplicateStrategy)
                )
            )
        }
    }
}

private extension MainWindow {
    func openRecoveredIncident() {
        switch model.route {
        case let .mainEmpty(opening), let .mainList(opening), let .settingsGeneral(opening):
            model.showGeneralSettings(opening: opening, selectedTab: "diagnostics")
            observabilityRuntime.dismissRecoveryNotice()
        default:
            model.toastMessage = L10n.message("observability.recovery.openAfterRepository")
        }
    }
}
