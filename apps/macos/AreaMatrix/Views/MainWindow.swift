import AppKit
import SwiftUI

struct MainWindow: View {
    @StateObject private var model: OnboardingModel

    init(model: OnboardingModel = OnboardingModel()) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ZStack(alignment: .top) {
            content

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
        .frame(minWidth: 760, minHeight: 520)
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
                    NSApplication.shared.keyWindow?.close()
                }
            }
            Button("Cancel", role: .cancel, action: model.cancelSetupQuit)
        } message: {
            Text(setupQuitConfirmationMessage)
        }
        .task {
            await model.bootstrapIfNeeded()
        }
        .sheet(item: $model.pendingImportEntry) { request in
            ImportEntrySheetView(request: request, onCancel: model.dismissImportEntry)
        }
    }

    private var isConfirmingInitializationCancel: Bool {
        if case .initializing = model.route { return true }
        return false
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

    @ViewBuilder
    private var content: some View {
        switch model.route {
        case .loadingConfiguration:
            LoadingConfigurationView()
        case .welcome:
            WelcomeStepView(
                onContinue: model.continueFromWelcome,
                onLearnMore: model.openLearnMore
            )
        case .choosePath:
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
        case .validatePath:
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
                    Task {
                        await model.retryRepositoryPathValidation()
                    }
                },
                onICloudRiskAcceptedChanged: model.updateICloudRiskAccepted,
                onContinue: {
                    Task {
                        await model.continueFromValidatePath()
                    }
                }
            )
        case .confirmRepositoryInitialization(let draft):
            ConfirmInitStepView(
                draft: draft,
                onBack: model.showValidatePath,
                onChangePath: model.showChoosePath,
                onCreateEmpty: {
                    Task {
                        await model.createEmptyRepositoryFromConfirmInit()
                    }
                },
                onAdoptExisting: {
                    Task {
                        await model.adoptExistingRepositoryFromConfirmInit()
                    }
                },
                onCancelSetup: {
                    if model.confirmSetupQuit() {
                        NSApplication.shared.keyWindow?.close()
                    }
                }
            )
        case .initializing(let draft):
            InitializingStepView(
                draft: draft,
                scanSession: model.initializationScanSession,
                recoveryReport: model.initializationRecoveryReport,
                progressWarning: model.initializationProgressWarning,
                isCancellationRequested: model.isInitializationCancellationRequested,
                onCancel: model.requestSetupQuit
            )
        case .initializationFailed(let repoPath, let mapping, let retryDraft):
            InitFailedStepView(
                repoPath: repoPath,
                mapping: mapping,
                diagnostics: model.initializationDiagnostics,
                canRetry: retryDraft != nil,
                onChangePath: model.showChoosePath,
                onRetry: {
                    Task {
                        await model.retryFailedInitialization()
                    }
                },
                onCollectDiagnostics: {
                    await model.collectInitializationDiagnostics()
                },
                onQuit: {
                    NSApplication.shared.keyWindow?.close()
                }
            )
        case .initializationDone(let result):
            InitDoneStepView(
                result: result,
                errorMapping: model.initializationOpenErrorMapping,
                onOpenRepository: { Task { await model.openInitializedRepository() } },
                onOpenInFinder: model.openInitializedRepositoryInFinder
            )
        case .mainLoading(let state):
            MainLoadingView(
                state: state,
                onCancelOpening: model.cancelMainOpening,
                onRetryTree: {
                    Task {
                        await model.retryMainLoadingTree()
                    }
                },
                onRetryOpening: {
                    Task {
                        await model.retryMainRepositoryFromError(repoPath: state.repoPath)
                    }
                }
            )
        case .mainRepoError(let repoPath, let mapping):
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
                    Task {
                        await model.retryMainRepositoryFromError(repoPath: repoPath)
                    }
                },
                onReconnectFolder: {
                    Task {
                        await model.reconnectMainRepositoryFolder(from: repoPath)
                    }
                },
                onOpenRepair: {
                    model.openMainRepositoryRepair(repoPath: repoPath)
                },
                onConfirmExternalRemoval: {
                    Task {
                        await model.confirmMainRepositoryExternalRemoval(repoPath: repoPath)
                    }
                },
                onRevealFolder: {
                    model.revealMainRepositoryFolder(repoPath: repoPath)
                },
                onRequestDiagnostics: {
                    model.requestMainRepositoryDiagnosticsPrivacyConfirmation(repoPath: repoPath)
                },
                onConfirmDiagnostics: {
                    Task {
                        await model.collectMainRepositoryDiagnostics(repoPath: repoPath)
                    }
                },
                onCancelDiagnostics: model.cancelMainRepositoryDiagnosticsPrivacyConfirmation,
                onChooseAnotherFolder: model.showChoosePath
            )
        case .dbRepairConfirm(let repoPath, let scanSession, let mapping):
            DBRepairConfirmView(
                repoPath: repoPath,
                scanSession: scanSession,
                mapping: mapping,
                onResume: {
                    Task {
                        await model.resumeInterruptedInitialization(repoPath: repoPath, scanSession: scanSession)
                    }
                },
                onCleanUpAndRetry: {
                    Task {
                        await model.cleanUpInterruptedInitialization(repoPath: repoPath)
                    }
                },
                onChooseAnotherFolder: model.showChoosePath
            )
        case .settingsRepository:
            SettingsRepositoryReturnView()
        case .mainEmpty(let opening):
            MainRepositoryContentView(
                opening: opening,
                state: .empty,
                onImport: { model.chooseImportSources(opening: opening) },
                onDropImport: { urls, destination in
                    model.startImportEntry(
                        opening: opening,
                        source: .dropZone,
                        urls: urls,
                        destination: destination
                    )
                },
                onOpenSettings: { Task { await model.beginSettingsRepositoryPathValidation(opening.config.repoPath) } },
                onRetryCurrentList: { Task { await model.retryConfigurationLoad() } },
                onCollectDiagnostics: { await model.collectMainListDiagnostics(opening: opening) },
                onShowInFinder: { model.showMainListFileInFinder(opening: opening, relativePath: $0) },
                onCopyPath: { model.copyMainListPath(opening: opening, relativePath: $0) }
            )
        case .mainList(let opening):
            MainRepositoryContentView(
                opening: opening,
                state: .list,
                onImport: { model.chooseImportSources(opening: opening) },
                onDropImport: { urls, destination in
                    model.startImportEntry(
                        opening: opening,
                        source: .dropZone,
                        urls: urls,
                        destination: destination
                    )
                },
                onOpenSettings: { Task { await model.beginSettingsRepositoryPathValidation(opening.config.repoPath) } },
                onRetryCurrentList: { Task { await model.retryConfigurationLoad() } },
                onCollectDiagnostics: { await model.collectMainListDiagnostics(opening: opening) },
                onShowInFinder: { model.showMainListFileInFinder(opening: opening, relativePath: $0) },
                onCopyPath: { model.copyMainListPath(opening: opening, relativePath: $0) }
            )
        case .configurationError(let failure):
            ConfigurationErrorView(
                failure: failure,
                onRetry: {
                    Task {
                        await model.retryConfigurationLoad()
                    }
                },
                onStartSetup: model.showWelcome
            )
        }
    }
}
