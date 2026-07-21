import SwiftUI

struct GeneralSettingsView: View {
    @StateObject private var model: GeneralSettingsModel
    @Binding private var selectedTab: String?
    let onClose: () -> Void
    let onChangeRepository: () -> Void
    let onOpenRepositoryRecovery: () -> Void
}

extension GeneralSettingsView {
    init(
        repoPath: String,
        selectedTab: Binding<String?> = .constant("general"),
        onClose: @escaping () -> Void,
        onChangeRepository: @escaping () -> Void = {},
        onOpenRepositoryRecovery: @escaping () -> Void = {},
        loader: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        rootOverviewInspector: any RootOverviewFileInspecting =
            GeneralSettingsPlatformServices.rootOverviewInspector,
        rootOverviewRevealer: any RepositoryFileRevealing =
            GeneralSettingsPlatformServices.rootOverviewRevealer,
        ignoreRulesManager: any RepositoryIgnoreRulesManaging =
            GeneralSettingsPlatformServices.ignoreRulesManager,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper
    ) {
        _model = StateObject(wrappedValue: GeneralSettingsModel(
            repoPath: repoPath,
            loader: loader,
            updater: updater,
            rootOverviewInspector: rootOverviewInspector,
            rootOverviewRevealer: rootOverviewRevealer,
            ignoreRulesManager: ignoreRulesManager,
            errorMapper: errorMapper
        ))
        _selectedTab = selectedTab
        self.onClose = onClose
        self.onChangeRepository = onChangeRepository
        self.onOpenRepositoryRecovery = onOpenRepositoryRecovery
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .areaMatrixWorkspaceRegionShell(cornerRadius: 0)
            Divider()
            content
                .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await model.load()
        }
        .confirmationDialog(
            storageConfirmationTitle,
            isPresented: storageConfirmationBinding
        ) {
            Button(String(localized: "settings.action.cancel"), role: .cancel, action: model.cancelPendingStorageMode)
            Button(String(localized: "settings.action.confirm")) {
                Task {
                    await model.confirmPendingStorageMode()
                }
            }
        } message: {
            Text(model.pendingStorageConfirmation?.confirmationMessage ?? "")
        }
        .sheet(isPresented: rootOverviewBinding) {
            RootOverviewConfirmationSheet(
                status: model.pendingRootOverviewStatus ?? .missing,
                onCancel: model.cancelRootOverview,
                onRevealInFinder: model.revealRootOverviewInFinder,
                onEnable: {
                    Task {
                        await model.confirmRootOverview()
                    }
                }
            )
        }
        .confirmationDialog(
            String(localized: "settings.ignore.createTitle"),
            isPresented: ignoreRulesCreateBinding
        ) {
            Button(String(localized: "settings.action.cancel"), role: .cancel, action: model.cancelCreateDefaultIgnoreRules)
            Button(String(localized: "settings.ignore.createButton")) {
                model.createDefaultIgnoreRulesAndOpen()
            }
        } message: {
            Text(String(localized: "settings.ignore.createMessage"))
        }
    }

    private var sidebar: some View {
        List(selection: $selectedTab) {
            Label(String(localized: "settings.tab.general"), systemImage: "gearshape")
                .tag("general")
            Label(String(localized: "settings.tab.repository"), systemImage: "folder")
                .tag("repository")
            Label(String(localized: "settings.tab.classifier"), systemImage: "tag")
                .tag("classifier")
            Label(String(localized: "settings.tab.ai"), systemImage: "sparkles")
                .tag("ai")
            Label(String(localized: "settings.tab.integrations"), systemImage: "point.3.connected.trianglepath.dotted")
                .tag("integrations")
            Label(String(localized: "settings.tab.advanced"), systemImage: "wrench.and.screwdriver")
                .tag("advanced")
            Label(String(localized: "settings.tab.about"), systemImage: "info.circle")
                .tag("about")
        }
        .listStyle(.sidebar)
        .frame(width: 180)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case "repository":
            RepositorySettingsPane(
                repoPath: model.repoPath,
                onChangeRepository: onChangeRepository,
                onOpenPlatformCapabilities: {
                    selectedTab = "about"
                },
                onOpenRecoveryTools: onOpenRepositoryRecovery
            )
        case "classifier":
            ClassifierSettingsPane(repoPath: model.repoPath)
        case "ai":
            AISettingsPane(repoPath: model.repoPath)
        case "integrations":
            IntegrationsSettingsPane(repoPath: model.repoPath)
        case "advanced":
            AdvancedSettingsPane(
                repoPath: model.repoPath,
                onOpenRecoveryTools: onOpenRepositoryRecovery
            )
        case "about":
            AboutSettingsPane(
                repoPath: model.repoPath,
                onOpenRepositorySettings: {
                    selectedTab = "repository"
                },
                onClose: onClose
            )
        default:
            generalContent
        }
    }

    @ViewBuilder
    private var generalContent: some View {
        switch model.loadState {
        case .loading:
            loadingContent
        case let .failed(error):
            loadingErrorContent(error)
        case .loaded:
            loadedContent
        }
    }

    private var loadingContent: some View {
        GeneralSettingsLoadingContent(onClose: onClose)
    }

    private func loadingErrorContent(_ error: GeneralSettingsSaveError) -> some View {
        SettingsPageErrorContent(
            title: String(localized: "settings.error.unableToLoad"),
            message: error.message,
            recovery: error.recovery
        ) {
            Button(String(localized: "settings.action.retry")) {
                Task {
                    await model.load()
                }
            }
            Button(String(localized: "settings.action.close"), action: onClose)
        }
    }

    private var loadedContent: some View {
        GeneralSettingsLoadedContent(model: model, onClose: onClose)
    }

    private var storageConfirmationTitle: String {
        switch model.pendingStorageConfirmation {
        case .move:
            String(localized: "settings.storage.confirmMove")
        case .indexOnly:
            String(localized: "settings.storage.confirmIndexOnly")
        default:
            String(localized: "settings.storage.confirmDefault")
        }
    }

    private var storageConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.pendingStorageConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    model.cancelPendingStorageMode()
                }
            }
        )
    }

    private var rootOverviewBinding: Binding<Bool> {
        Binding(
            get: { model.pendingRootOverviewStatus != nil },
            set: { isPresented in
                if !isPresented {
                    model.cancelRootOverview()
                }
            }
        )
    }

    private var ignoreRulesCreateBinding: Binding<Bool> {
        Binding(
            get: { model.pendingIgnoreRulesAlert != nil },
            set: { isPresented in
                if !isPresented {
                    model.cancelCreateDefaultIgnoreRules()
                }
            }
        )
    }
}
