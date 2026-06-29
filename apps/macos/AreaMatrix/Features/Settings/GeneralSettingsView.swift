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
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        rootOverviewInspector: any RootOverviewFileInspecting = LocalRootOverviewFileInspector(),
        rootOverviewRevealer: any RepositoryFileRevealing = NSWorkspaceRepositoryFileRevealer(),
        ignoreRulesManager: any RepositoryIgnoreRulesManaging = NSWorkspaceRepositoryIgnoreRulesManager(),
        errorMapper: any CoreErrorMapping = CoreBridge()
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
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await model.load()
        }
        .confirmationDialog(
            storageConfirmationTitle,
            isPresented: storageConfirmationBinding
        ) {
            Button("Cancel", role: .cancel, action: model.cancelPendingStorageMode)
            Button("Confirm") {
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
            "Create default ignore.yaml?",
            isPresented: ignoreRulesCreateBinding
        ) {
            Button("Cancel", role: .cancel, action: model.cancelCreateDefaultIgnoreRules)
            Button("Create default ignore.yaml") {
                model.createDefaultIgnoreRulesAndOpen()
            }
        } message: {
            Text(
                """
                AreaMatrix will only write .areamatrix/ignore.yaml. Existing user files are not moved, renamed, \
                deleted, or overwritten.
                """
            )
        }
    }

    private var sidebar: some View {
        List(selection: $selectedTab) {
            Label("通用", systemImage: "gearshape")
                .tag("general")
            Label("资料库", systemImage: "folder")
                .tag("repository")
            Label("分类规则", systemImage: "tag")
                .tag("classifier")
            Label("AI", systemImage: "sparkles")
                .tag("ai")
            Label("集成", systemImage: "point.3.connected.trianglepath.dotted")
                .tag("integrations")
            Label("高级", systemImage: "wrench.and.screwdriver")
                .tag("advanced")
            Label("关于", systemImage: "info.circle")
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
            title: "Unable to load settings",
            message: error.message,
            recovery: error.recovery
        ) {
            Button("Retry") {
                Task {
                    await model.load()
                }
            }
            Button("Close", action: onClose)
        }
    }

    private var loadedContent: some View {
        GeneralSettingsLoadedContent(model: model, onClose: onClose)
    }

    private var storageConfirmationTitle: String {
        switch model.pendingStorageConfirmation {
        case .move:
            "Use Move as the default?"
        case .indexOnly:
            "Use Index-only as the default?"
        default:
            "Confirm default storage mode"
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
