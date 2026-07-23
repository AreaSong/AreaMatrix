import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var localizer: AppLocalizer
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
            Button(L10n.string("settings.action.cancel"), role: .cancel, action: model.cancelPendingStorageMode)
            Button(L10n.string("settings.action.confirm")) {
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
            L10n.string("settings.ignore.createTitle"),
            isPresented: ignoreRulesCreateBinding
        ) {
            Button(L10n.string("settings.action.cancel"), role: .cancel, action: model.cancelCreateDefaultIgnoreRules)
            Button(L10n.string("settings.ignore.createButton")) {
                model.createDefaultIgnoreRulesAndOpen()
            }
        } message: {
            Text(L10n.string("settings.ignore.createMessage"))
        }
    }

    private var sidebar: some View {
        List(selection: $selectedTab) {
            Label(L10n.string("settings.tab.general"), systemImage: "gearshape")
                .tag("general")
            Label(L10n.string("settings.tab.repository"), systemImage: "folder")
                .tag("repository")
            Label(L10n.string("settings.tab.classifier"), systemImage: "tag")
                .tag("classifier")
            Label(L10n.string("settings.tab.ai"), systemImage: "sparkles")
                .tag("ai")
            Label(L10n.string("settings.tab.integrations"), systemImage: "point.3.connected.trianglepath.dotted")
                .tag("integrations")
            Label(L10n.string("settings.tab.advanced"), systemImage: "wrench.and.screwdriver")
                .tag("advanced")
            Label(L10n.string("settings.tab.about"), systemImage: "info.circle")
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
            title: L10n.string("settings.error.unableToLoad"),
            message: localizer.resolve(error.message),
            recovery: localizer.resolve(error.recovery)
        ) {
            Button(L10n.string("settings.action.retry")) {
                Task {
                    await model.load()
                }
            }
            Button(L10n.string("settings.action.close"), action: onClose)
        }
    }

    private var loadedContent: some View {
        GeneralSettingsLoadedContent(model: model, onClose: onClose)
    }

    private var storageConfirmationTitle: String {
        switch model.pendingStorageConfirmation {
        case .move:
            L10n.string("settings.storage.confirmMove")
        case .indexOnly:
            L10n.string("settings.storage.confirmIndexOnly")
        default:
            L10n.string("settings.storage.confirmDefault")
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
