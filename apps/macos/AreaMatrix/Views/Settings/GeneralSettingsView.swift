import SwiftUI

struct GeneralSettingsView: View {
    @StateObject private var model: GeneralSettingsModel
    @Binding private var selectedTab: String?
    let onClose: () -> Void
    let onChangeRepository: () -> Void
    let onOpenRepositoryRecovery: () -> Void

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
            Text("AreaMatrix will only write .areamatrix/ignore.yaml. Existing user files are not moved, renamed, deleted, or overwritten.")
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
            Label("集成", systemImage: "point.3.connected.trianglepath.dotted")
                .tag("integrations")
            Label("高级", systemImage: "wrench.and.screwdriver")
                .tag("advanced")
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
                onOpenRecoveryTools: onOpenRepositoryRecovery
            )
        case "classifier":
            ClassifierSettingsPane(repoPath: model.repoPath)
        case "integrations":
            IntegrationsSettingsPane(repoPath: model.repoPath)
        case "advanced":
            AdvancedSettingsPane(repoPath: model.repoPath)
        default:
            generalContent
        }
    }

    @ViewBuilder
    private var generalContent: some View {
        switch model.loadState {
        case .loading:
            loadingContent
        case .failed(let error):
            loadingErrorContent(error)
        case .loaded:
            loadedContent
        }
    }

    private var loadingContent: some View {
        GeneralSettingsLoadingContent(onClose: onClose)
    }

    private func loadingErrorContent(_ error: GeneralSettingsSaveError) -> some View {
        ContentUnavailableView {
            Label("Unable to load settings", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.message)
            Text(error.recovery)
        } actions: {
            Button("Retry") {
                Task {
                    await model.load()
                }
            }
            Button("Close", action: onClose)
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    saveErrorBanner
                    storageSection
                    overviewSection
                    ignoreRulesSection
                    languageSection
                    appearanceSection
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
            }
            footer
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("通用")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(model.repoPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if model.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Saving settings")
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var saveErrorBanner: some View {
        if let error = model.saveError {
            VStack(alignment: .leading, spacing: 8) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error.recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("The UI has been restored to the last saved settings. .areamatrix/generated/ remains the safe default overview output.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.hasRetryableSave {
                    Button("Retry save") {
                        Task {
                            await model.retrySave()
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        }
    }

    private var storageSection: some View {
        SettingsSection(title: "默认存储模式") {
            Picker("Default storage mode", selection: storageSelection) {
                ForEach(GeneralSettingsStorageMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .disabled(writesDisabled)
            Text("导入时仍可在 ImportSheet 临时更改。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        SettingsSection(title: "资料库概览") {
            Picker("Repository overview output", selection: overviewSelection) {
                Text("仅保存在 .areamatrix/generated/").tag(GeneralSettingsOverviewOutput.generatedOnly)
                Text("同时在根目录生成 AREAMATRIX.md").tag(GeneralSettingsOverviewOutput.rootAreaMatrixFile)
            }
            .pickerStyle(.radioGroup)
            .disabled(writesDisabled)
            Text("AreaMatrix 永远不会覆盖已有 README.md。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var ignoreRulesSection: some View {
        SettingsSection(title: "忽略规则") {
            Button("Open ignore.yaml", action: model.openIgnoreRules)
                .disabled(writesDisabled)
            Text("Missing ignore.yaml can be recreated only inside .areamatrix/.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var languageSection: some View {
        SettingsSection(title: "语言") {
            Picker("Language", selection: localeSelection) {
                ForEach(GeneralSettingsLocale.allCases) { locale in
                    Text(locale.label).tag(locale)
                }
            }
            .pickerStyle(.segmented)
            .disabled(writesDisabled)
            .frame(maxWidth: 260)
        }
    }

    private var appearanceSection: some View {
        SettingsSection(title: "外观") {
            Picker("Appearance", selection: .constant(GeneralSettingsAppearance.system)) {
                ForEach(GeneralSettingsAppearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .disabled(true)
            .frame(maxWidth: 180)
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset this tab") {
                Task {
                    await model.resetThisTab()
                }
            }
            .disabled(writesDisabled)
            Spacer()
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var writesDisabled: Bool {
        model.isSaving || !model.isLoaded || model.pendingStorageConfirmation != nil ||
            model.pendingRootOverviewStatus != nil || model.pendingIgnoreRulesAlert != nil
    }

    private var storageSelection: Binding<GeneralSettingsStorageMode> {
        Binding(
            get: { model.draft?.defaultStorageMode ?? .copy },
            set: { mode in
                Task {
                    await model.requestStorageMode(mode)
                }
            }
        )
    }

    private var overviewSelection: Binding<GeneralSettingsOverviewOutput> {
        Binding(
            get: { model.draft?.overviewOutput ?? .generatedOnly },
            set: { output in
                Task {
                    await model.requestOverviewOutput(output)
                }
            }
        )
    }

    private var localeSelection: Binding<GeneralSettingsLocale> {
        Binding(
            get: { model.draft?.locale ?? .system },
            set: { locale in
                Task {
                    await model.updateLocale(locale)
                }
            }
        )
    }

    private var storageConfirmationTitle: String {
        switch model.pendingStorageConfirmation {
        case .move:
            return "Use Move as the default?"
        case .indexOnly:
            return "Use Index-only as the default?"
        default:
            return "Confirm default storage mode"
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

struct GeneralSettingsLoadingContent: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading settings...")
                .font(.headline)
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("S1-26-loading-close-settings")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RootOverviewConfirmationSheet: View {
    let status: RootOverviewFileStatus
    let onCancel: () -> Void
    let onRevealInFinder: () -> Void
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enable root AREAMATRIX.md?")
                .font(.title2.weight(.semibold))
            Text("AreaMatrix will continue writing generated overviews to .areamatrix/generated/. If AREAMATRIX.md already exists, AreaMatrix will only update its own managed block after you confirm. README.md is never used as an automatic output target.")
                .fixedSize(horizontal: false, vertical: true)
            Text(status.confirmationDetail)
                .foregroundStyle(status.canEnableRootOverview ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if status.requiresFinderRecovery {
                    Button("Reveal in Finder", action: onRevealInFinder)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Enable root overview", action: onEnable)
                    .buttonStyle(.borderedProminent)
                    .disabled(!status.canEnableRootOverview)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
