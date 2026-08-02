import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: AdvancedSettingsModel
    @State private var isDangerZoneExpanded = false
    private let onOpenRecoveryTools: () -> Void
    private let onOpenDiagnostics: () -> Void
    private let onReturnToWelcome: () -> Void
}

extension AdvancedSettingsPane {
    init(
        repoPath: String,
        featureDependencies: SettingsFeatureDependencies,
        sharedDependencies: SharedFeatureDependencies,
        onOpenRecoveryTools: @escaping () -> Void = {},
        onOpenDiagnostics: @escaping () -> Void = {},
        onReturnToWelcome: @escaping () -> Void = {},
        rootOverviewInspector: any RootOverviewFileInspecting = AdvancedSettingsPlatformServices.rootOverviewInspector,
        appVersionReader: any AppVersionReading = AdvancedSettingsPlatformServices.appVersionReader,
        metadataReader: any ExistingRepositoryMetadataReading = AdvancedSettingsPlatformServices.metadataReader,
        summaryCopier: any AdvancedSettingsDiagnosticSummaryCopying =
            AdvancedSettingsPlatformServices.diagnosticSummaryCopier
    ) {
        self.init(
            repoPath: repoPath,
            onOpenRecoveryTools: onOpenRecoveryTools,
            onOpenDiagnostics: onOpenDiagnostics,
            onReturnToWelcome: onReturnToWelcome,
            loader: featureDependencies.configurationLoader,
            updater: featureDependencies.configurationUpdater,
            rootOverviewInspector: rootOverviewInspector,
            diagnosticsCollector: sharedDependencies.diagnosticsCollector,
            appVersionReader: appVersionReader,
            coreVersionReader: featureDependencies.coreVersionReader,
            metadataReader: metadataReader,
            summaryCopier: summaryCopier,
            errorMapper: sharedDependencies.errorMapper
        )
    }

    init(
        repoPath: String,
        onOpenRecoveryTools: @escaping () -> Void = {},
        onOpenDiagnostics: @escaping () -> Void = {},
        onReturnToWelcome: @escaping () -> Void = {},
        loader: any CoreConfigurationLoading,
        updater: any CoreConfigurationUpdating,
        rootOverviewInspector: any RootOverviewFileInspecting =
            AdvancedSettingsPlatformServices.rootOverviewInspector,
        diagnosticsCollector: any CoreDiagnosticsCollecting,
        appVersionReader: any AppVersionReading = AdvancedSettingsPlatformServices.appVersionReader,
        coreVersionReader: any CoreVersionReading,
        metadataReader: any ExistingRepositoryMetadataReading = AdvancedSettingsPlatformServices.metadataReader,
        summaryCopier: any AdvancedSettingsDiagnosticSummaryCopying =
            AdvancedSettingsPlatformServices.diagnosticSummaryCopier,
        errorMapper: any CoreErrorMapping
    ) {
        _model = StateObject(wrappedValue: AdvancedSettingsModel(
            repoPath: repoPath,
            loader: loader,
            updater: updater,
            rootOverviewInspector: rootOverviewInspector,
            diagnosticsCollector: diagnosticsCollector,
            appVersionReader: appVersionReader,
            coreVersionReader: coreVersionReader,
            metadataReader: metadataReader,
            summaryCopier: summaryCopier,
            errorMapper: errorMapper
        ))
        self.onOpenRecoveryTools = onOpenRecoveryTools
        self.onOpenDiagnostics = onOpenDiagnostics
        self.onReturnToWelcome = onReturnToWelcome
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await model.load()
        }
        .onDisappear(perform: model.cancelDiagnosticsExport)
        .confirmationDialog(
            "Export diagnostics?",
            isPresented: diagnosticsConfirmationBinding
        ) {
            Button(L10n.string("Cancel"), role: .cancel, action: model.cancelDiagnosticsExport)
            Button(L10n.string("Export diagnostics")) {
                AppLogger.shared.logUIAction("diagnostics.export.confirmed")
                Task {
                    await model.collectDiagnostics()
                }
            }
        } message: {
            Text(L10n.string("diagnostics.repositoryPrivacyDetail"))
        }
        .sheet(isPresented: rootOverviewBinding) {
            AdvancedRootOverviewConfirmationSheet(
                status: model.pendingRootOverviewStatus ?? .missing,
                onCancel: model.cancelRootOverview,
                onEnable: {
                    Task {
                        await model.confirmRootOverview()
                    }
                }
            )
        }
        .confirmationDialog(
            "Enable Replace during import?",
            isPresented: replaceConfirmationBinding
        ) {
            Button(L10n.string("Cancel"), role: .cancel, action: model.cancelAllowReplaceDuringImport)
            Button(L10n.string("Enable Replace")) {
                AppLogger.shared.logUIAction(
                    "repository.import.replace.enabled",
                    severity: .warn
                )
                Task {
                    await model.confirmAllowReplaceDuringImport()
                }
            }
        } message: {
            Text(L10n.string("settings.advanced.replaceConfirmationDetail"))
        }
    }

    private var header: some View {
        SettingsPageHeader(title: L10n.string("settings.page.advanced"), subtitle: model.repoPath) {
            if model.isSaving || model.loadState == .loading {
                SettingsHeaderProgressIndicator(
                    label: model.isSaving
                        ? L10n.string("Saving advanced settings")
                        : L10n.string("Loading advanced settings")
                )
            } else {
                Button {
                    Task {
                        await model.load()
                    }
                } label: {
                    Label(L10n.string("Retry status"), systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("advanced-settings-retry-status")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            loadingContent
        case .loaded:
            loadedContent
        case let .failed(error):
            loadErrorContent(error)
        }
    }

    private var loadingContent: some View {
        SettingsPageLoadingContent(title: L10n.string("settings.loading.advanced"))
    }

    private func loadErrorContent(_ error: AdvancedSettingsError) -> some View {
        SettingsPageErrorContent(
            title: L10n.string("settings.error.loadAdvanced"),
            message: localizer.resolve(error.message),
            recovery: localizer.resolve(error.recovery)
        ) {
            Button(L10n.string("Retry status")) {
                Task {
                    await model.load()
                }
            }
            .accessibilityIdentifier("advanced-settings-load-error-retry-status")
            Button {
                onOpenRecoveryTools()
            } label: {
                Label(L10n.string("Open recovery tools..."), systemImage: "arrow.clockwise.circle")
            }
            .accessibilityIdentifier("advanced-settings-startup-recovery-core-open-recovery-tools")
        }
    }

    private var loadedContent: some View {
        SettingsPageScrollContent {
            VStack(spacing: 20) {
                saveErrorBanner
                versionErrorBanner
                diagnosticsStatusBanner
                actionFeedbackBanner

                diagnosticsSection
                    .modifier(SettingsSectionCardModifier())

                observabilitySection
                    .modifier(SettingsSectionCardModifier())

                dangerZoneSection
                    .modifier(SettingsSectionCardModifier())
            }
            .padding()
        }
    }

    @ViewBuilder
    private var versionErrorBanner: some View {
        if let error = model.versionError {
            AdvancedSettingsInlineBanner(error: error, tint: .orange)
        }
    }

    @ViewBuilder
    private var diagnosticsStatusBanner: some View {
        switch model.diagnosticsState {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            SettingsProgressBanner(title: L10n.string("Preparing repository diagnostics..."))
        case let .collected(snapshot):
            SettingsStatusBanner(
                title: L10n.string("Diagnostics exported"),
                systemImage: "checkmark.circle",
                tint: .green
            ) {
                Text(snapshot.snapshotPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                ForEach(snapshot.warnings.prefix(3), id: \.self) { warning in
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        case let .failed(error):
            AdvancedSettingsInlineBanner(error: error, tint: .red)
        }
    }

    @ViewBuilder
    private var actionFeedbackBanner: some View {
        if let feedback = model.actionFeedback {
            switch feedback {
            case let .success(message):
                SettingsStatusBanner(title: localizer.resolve(message), systemImage: "checkmark.circle", tint: .green)
            case let .failed(error):
                AdvancedSettingsInlineBanner(error: error, tint: .red)
            }
        }
    }

    private var diagnosticsSection: some View {
        AdvancedSettingsDiagnosticsSection(
            versionInfo: model.versionInfo,
            buttonTitle: diagnosticsButtonTitle,
            isCollecting: model.diagnosticsState.isCollecting,
            onExportDiagnostics: model.requestDiagnosticsExport
        )
    }

    private var observabilitySection: some View {
        AdvancedSettingsObservabilitySection(
            isCollecting: model.diagnosticsState.isCollecting,
            onOpenDiagnostics: onOpenDiagnostics,
            onCopyDiagnosticSummary: model.copyDiagnosticSummary
        )
    }

    @ViewBuilder
    private var saveErrorBanner: some View {
        if let error = model.saveError {
            SettingsStatusBanner(
                title: localizer.resolve(error.message),
                systemImage: "exclamationmark.triangle",
                tint: .red
            ) {
                Text(localizer.resolve(error.recovery))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(L10n.string("The UI has been restored to the last saved advanced settings."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.hasRetryableSave {
                    Button(L10n.string("Retry save")) {
                        Task {
                            await model.retrySave()
                        }
                    }
                    .accessibilityIdentifier(model.retrySaveAccessibilityIdentifier)
                }
            }
        }
    }

    private var dangerZoneSection: some View {
        DisclosureGroup(L10n.string("Danger zone"), isExpanded: $isDangerZoneExpanded) {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.string("settings.advanced.dangerZoneDetail"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                overviewOutputSection
                allowReplaceSection
                AdvancedSettingsRecoveryToolsSection(onOpenRecoveryTools: onOpenRecoveryTools)

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("返回欢迎页"))
                        .font(.headline)
                        .foregroundColor(.red)
                    Button {
                        onReturnToWelcome()
                    } label: {
                        Label(
                            L10n.string("Disconnect and return to Welcome screen"),
                            systemImage: "arrow.uturn.backward"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityIdentifier("advanced-settings-danger-zone-return-to-welcome")
                    Text(L10n.string("关闭当前窗口上下文，彻底退回初始启动欢迎页。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 10)
        }
        .accessibilityIdentifier("advanced-settings-danger-zone")
    }

    private var overviewOutputSection: some View {
        AdvancedSettingsOverviewOutputSection(
            selection: overviewOutputSelection,
            writesDisabled: model.writesDisabled
        )
    }

    private var allowReplaceSection: some View {
        AdvancedSettingsAllowReplaceSection(
            isOn: allowReplaceSelection,
            writesDisabled: model.writesDisabled
        )
    }

    private var overviewOutputSelection: Binding<AdvancedSettingsOverviewOutput> {
        Binding(
            get: { model.draft?.overviewOutput ?? .generatedOnly },
            set: { output in
                Task {
                    await model.requestOverviewOutput(output)
                }
            }
        )
    }

    private var allowReplaceSelection: Binding<Bool> {
        Binding(
            get: { model.draft?.allowReplaceDuringImport ?? false },
            set: { isEnabled in
                Task {
                    await model.requestAllowReplaceDuringImport(isEnabled)
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

    private var replaceConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.isReplaceConfirmationPending },
            set: { isPresented in
                if !isPresented {
                    model.cancelAllowReplaceDuringImport()
                }
            }
        )
    }

    private var diagnosticsConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.diagnosticsState.isConfirmingPrivacy },
            set: { isPresented in
                if !isPresented {
                    model.cancelDiagnosticsExport()
                }
            }
        )
    }

    private var diagnosticsButtonTitle: String {
        model.diagnosticsState.isCollecting
            ? L10n.string("Exporting diagnostics...")
            : L10n.string("Export diagnostics...")
    }
}

struct SettingsSectionCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .areaMatrixGlassCard(cornerRadius: 12)
    }
}
