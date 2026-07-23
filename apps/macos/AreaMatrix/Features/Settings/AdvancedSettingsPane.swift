import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: AdvancedSettingsModel
    @State private var isDangerZoneExpanded = false
    private let onOpenRecoveryTools: () -> Void
}

extension AdvancedSettingsPane {
    init(
        repoPath: String,
        onOpenRecoveryTools: @escaping () -> Void = {},
        loader: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        rootOverviewInspector: any RootOverviewFileInspecting =
            AdvancedSettingsPlatformServices.rootOverviewInspector,
        diagnosticsCollector: any CoreDiagnosticsCollecting = AppCoreServices.diagnosticsCollector,
        appVersionReader: any AppVersionReading = AdvancedSettingsPlatformServices.appVersionReader,
        coreVersionReader: any CoreVersionReading = AppCoreServices.coreVersionReader,
        metadataReader: any ExistingRepositoryMetadataReading = AdvancedSettingsPlatformServices.metadataReader,
        logsOpener: any AdvancedSettingsLogFolderOpening = AdvancedSettingsPlatformServices.logsOpener,
        summaryCopier: any AdvancedSettingsDiagnosticSummaryCopying =
            AdvancedSettingsPlatformServices.diagnosticSummaryCopier,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper
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
            logsOpener: logsOpener,
            summaryCopier: summaryCopier,
            errorMapper: errorMapper
        ))
        self.onOpenRecoveryTools = onOpenRecoveryTools
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
            Button("Cancel", role: .cancel, action: model.cancelDiagnosticsExport)
            Button("Export diagnostics") {
                Task {
                    await model.collectDiagnostics()
                }
            }
        } message: {
            Text(
                "Repository diagnostics copy AreaMatrix metadata and may include paths, file names, tags, " +
                    "notes, and other sensitive metadata. Original file contents are not copied, and " +
                    "diagnostics are not uploaded automatically. Review the snapshot before sharing."
            )
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
            Button("Cancel", role: .cancel, action: model.cancelAllowReplaceDuringImport)
            Button("Enable Replace") {
                Task {
                    await model.confirmAllowReplaceDuringImport()
                }
            }
        } message: {
            Text(
                "Replace can move an existing repository file to system Trash before importing the new file. " +
                    "It is hidden by default and still requires confirmation for every replace."
            )
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
                    Label("Retry status", systemImage: "arrow.clockwise")
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
            Button("Retry status") {
                Task {
                    await model.load()
                }
            }
            .accessibilityIdentifier("advanced-settings-load-error-retry-status")
            Button {
                onOpenRecoveryTools()
            } label: {
                Label("Open recovery tools...", systemImage: "arrow.clockwise.circle")
            }
            .accessibilityIdentifier("advanced-settings-startup-recovery-core-open-recovery-tools")
        }
    }

    private var loadedContent: some View {
        SettingsPageScrollContent {
            saveErrorBanner
            versionErrorBanner
            diagnosticsStatusBanner
            actionFeedbackBanner
            diagnosticsSection
            logsSection
            dangerZoneSection
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

    private var logsSection: some View {
        AdvancedSettingsLogsSection(
            isCollecting: model.diagnosticsState.isCollecting,
            onOpenLogsFolder: model.openLogsFolder,
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
                Text("The UI has been restored to the last saved advanced settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.hasRetryableSave {
                    Button("Retry save") {
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
        DisclosureGroup("Danger zone", isExpanded: $isDangerZoneExpanded) {
            VStack(alignment: .leading, spacing: 18) {
                Text(
                    "These actions can affect AreaMatrix metadata. " +
                        "They do not delete your original files unless explicitly stated."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                overviewOutputSection
                allowReplaceSection
                AdvancedSettingsRecoveryToolsSection(onOpenRecoveryTools: onOpenRecoveryTools)
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
