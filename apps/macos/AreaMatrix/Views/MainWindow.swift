import SwiftUI

struct MainWindow: View {
    @StateObject private var model: OnboardingModel
    @StateObject private var externalCreatedFileWatcher: MainExternalCreatedFileWatcher
    private let importProgressControlState: ImportProgressControlState
    private let windowCloser: any WindowClosing

    init(
        model: OnboardingModel = OnboardingModel(),
        windowCloser: any WindowClosing = AppPlatformServices.windowCloser
    ) {
        _model = StateObject(wrappedValue: model)
        _externalCreatedFileWatcher = StateObject(wrappedValue: MainExternalCreatedFileWatcher(
            cursorStore: model.externalChangesSyncer
        ))
        importProgressControlState = model.importProgressControlState
        self.windowCloser = windowCloser
    }
}

extension MainWindow {
    var body: some View {
        ZStack(alignment: .top) {
            MainWindowRouteContent(model: model, windowCloser: windowCloser)

            if let toastMessage = model.toastMessage {
                Text(toastMessage)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
        .background {
            if case .welcome = model.route {
                Color.clear
            } else if isOnboardingRoute {
                AreaMatrixAmbientBackground(scene: onboardingScene, parallax: .zero)
                    .ignoresSafeArea()
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .background {
            if isOnboardingRoute {
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
            Button("Cancel", role: .cancel, action: model.cancelSetupQuit)
        } message: {
            Text(setupQuitConfirmationMessage)
        }
        .task {
            await model.bootstrapIfNeeded()
            model.consumePendingDockOpenRequests()
        }
        .onReceive(NotificationCenter.default.publisher(for: AreaMatrixDockOpenRelay.notification)) { _ in
            model.consumePendingDockOpenRequests()
        }
        .onReceive(NotificationCenter.default.publisher(for: AreaMatrixImportCommandRelay.notification)) { _ in
            model.handleImportMenuCommand()
        }
        .onReceive(NotificationCenter.default.publisher(for: AreaMatrixSettingsCommandRelay.notification)) { _ in
            model.handleSettingsMenuCommand()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AreaMatrixExternalCreatedFileRelay.notification),
            perform: handleExternalCreatedFileRelayNotification
        )
        .task(id: activeMainRepositoryPath) {
            if let activeMainRepositoryPath {
                await externalCreatedFileWatcher.start(repoPath: activeMainRepositoryPath)
            } else {
                externalCreatedFileWatcher.stop()
            }
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
                batchSessionStore: model.importBatchSessionStore
            )
        }
    }

    private var isConfirmingInitializationCancel: Bool {
        if case .initializing = model.route { return true }
        return false
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

    private var onboardingScene: AreaMatrixAmbientScene {
        switch model.route {
        case .choosePath: .classify
        case .validatePath: .security
        case .confirmRepositoryInitialization: .security
        case .initializing: .tracking
        case .initializationFailed: .help
        case .initializationDone: .start
        default: .home
        }
    }

    private var minWindowWidth: CGFloat {
        if case .welcome = model.route { return 860 }
        return 760
    }

    private var maxWindowWidth: CGFloat? {
        if case .welcome = model.route { return 860 }
        return nil
    }

    private var minWindowHeight: CGFloat {
        if case .welcome = model.route { return 640 }
        return 520
    }

    private var maxWindowHeight: CGFloat? {
        if case .welcome = model.route { return 640 }
        return nil
    }

    private var setupQuitConfirmationTitle: String {
        isConfirmingInitializationCancel ? "退出初始化？" : "Quit setup?"
    }

    private var setupQuitConfirmationActionTitle: String {
        isConfirmingInitializationCancel ? "Stop at Safe Point" : "Quit"
    }

    private var setupQuitConfirmationMessage: String {
        if isConfirmingInitializationCancel {
            return "AreaMatrix 会在当前 Core 操作到达安全点后停止；不会删除用户原文件。"
        }

        return "AreaMatrix will not create .areamatrix/ or save this repository selection."
    }

    private var activeMainRepositoryPath: String? {
        switch model.route {
        case let .mainEmpty(opening), let .mainList(opening), let .settingsGeneral(opening):
            opening.config.repoPath
        default:
            nil
        }
    }

    private func handleExternalCreatedFileRelayNotification(_ notification: Notification) {
        if let signals = notification.object as? [MainExternalCreatedFileSignal] {
            _ = model.handleExternalCreatedFiles(signals)
            _ = AreaMatrixExternalCreatedFileRelay.takePendingSignals(matchingRepoPath: activeMainRepositoryPath)
            return
        }
        model.consumePendingExternalCreatedFileSignals()
    }

    private func importRetryContextHandler(for request: ImportEntryRequest) -> (
        String,
        String,
        ImportSingleFileStorageMode,
        String,
        String,
        DuplicateStrategy
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
