import SwiftUI

struct AdvancedSettingsPane: View {
    @StateObject private var model: AdvancedSettingsModel
    @State private var isDangerZoneExpanded = false
    private let onOpenRecoveryTools: () -> Void
}

extension AdvancedSettingsPane {
    init(
        repoPath: String,
        onOpenRecoveryTools: @escaping () -> Void = {},
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        rootOverviewInspector: any RootOverviewFileInspecting = LocalRootOverviewFileInspector(),
        diagnosticsCollector: any CoreDiagnosticsCollecting = CoreBridge(),
        appVersionReader: any AppVersionReading = BundleAppVersionReader(),
        coreVersionReader: any CoreVersionReading = CoreBridge(),
        metadataReader: any ExistingRepositoryMetadataReading = SQLiteExistingRepositoryMetadataReader(),
        logsOpener: any AdvancedSettingsLogFolderOpening = AdvancedSettingsLogFolderOpener(),
        summaryCopier: any AdvancedSettingsDiagnosticSummaryCopying =
            AdvancedSettingsDiagnosticCopier(),
        errorMapper: any CoreErrorMapping = CoreBridge()
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
                "Diagnostics do not include your original file contents, are not uploaded automatically, " +
                    "and paths and usernames are redacted before display."
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("高级")
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
            if model.isSaving || model.loadState == .loading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(model.isSaving ? "Saving advanced settings" : "Loading advanced settings")
            } else {
                Button {
                    Task {
                        await model.load()
                    }
                } label: {
                    Label("Retry status", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("S1-30-retry-status")
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Divider()
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
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading advanced settings...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadErrorContent(_ error: AdvancedSettingsError) -> some View {
        ContentUnavailableView {
            Label("Unable to load advanced settings", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.message)
            Text(error.recovery)
        } actions: {
            Button("Retry status") {
                Task {
                    await model.load()
                }
            }
            .accessibilityIdentifier("S1-30-load-error-retry-status")
            Button {
                onOpenRecoveryTools()
            } label: {
                Label("Open recovery tools...", systemImage: "arrow.clockwise.circle")
            }
            .accessibilityIdentifier("S1-30-C1-16-open-recovery-tools")
        }
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                saveErrorBanner
                versionErrorBanner
                diagnosticsStatusBanner
                actionFeedbackBanner
                diagnosticsSection
                logsSection
                dangerZoneSection
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
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
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing redacted diagnostics...")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        case let .collected(snapshot):
            VStack(alignment: .leading, spacing: 8) {
                Label("Diagnostics exported", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        case let .failed(error):
            AdvancedSettingsInlineBanner(error: error, tint: .red)
        }
    }

    @ViewBuilder
    private var actionFeedbackBanner: some View {
        if let feedback = model.actionFeedback {
            switch feedback {
            case let .success(message):
                Label(message, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
            case let .failed(error):
                AdvancedSettingsInlineBanner(error: error, tint: .red)
            }
        }
    }

    private var diagnosticsSection: some View {
        AdvancedSettingsSection(title: "Diagnostics") {
            AdvancedSettingsKeyValueRow(label: "App version", value: model.versionInfo.appVersion)
            AdvancedSettingsKeyValueRow(label: "Core version", value: model.versionInfo.coreVersion)
            AdvancedSettingsKeyValueRow(
                label: "Repo schema version",
                value: model.versionInfo.repoSchemaVersionLabel
            )

            Button {
                model.requestDiagnosticsExport()
            } label: {
                Label(diagnosticsButtonTitle, systemImage: "doc.badge.gearshape")
            }
            .disabled(model.diagnosticsState.isCollecting)
            .accessibilityIdentifier("S1-30-export-diagnostics")

            Text(
                "Diagnostics do not include your original file contents, are not uploaded automatically, " +
                    "and paths and usernames are redacted before display."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var logsSection: some View {
        AdvancedSettingsSection(title: "Logs") {
            HStack(spacing: 10) {
                Button {
                    model.openLogsFolder()
                } label: {
                    Label("Open logs folder", systemImage: "folder")
                }
                .disabled(model.diagnosticsState.isCollecting)
                .accessibilityIdentifier("S1-30-open-logs-folder")

                Button {
                    model.copyDiagnosticSummary()
                } label: {
                    Label("Copy diagnostic summary", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("S1-30-copy-diagnostic-summary")
            }

            Text("Diagnostics do not include your original file contents.")
                .font(.callout)
                .foregroundStyle(.secondary)
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
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
        .accessibilityIdentifier("S1-30-danger-zone")
    }

    private var overviewOutputSection: some View {
        AdvancedSettingsSection(title: "Generated overview output") {
            Picker("Generated overview output", selection: overviewOutputSelection) {
                ForEach(AdvancedSettingsOverviewOutput.allCases) { output in
                    Text(output.label).tag(output)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.writesDisabled)
            .frame(maxWidth: 320)
            .accessibilityIdentifier(AdvancedSettingsAccessibilityID.overviewOutput)

            Text("Generated only writes under .areamatrix/generated/.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Root AREAMATRIX.md adds a managed marker block to the repository root file.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("README.md is never managed.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var allowReplaceSection: some View {
        AdvancedSettingsSection(title: "Dangerous import option") {
            Toggle("Allow replace during import", isOn: allowReplaceSelection)
                .disabled(model.writesDisabled)
                .accessibilityIdentifier("S1-30-C1-04-allow-replace")

            Text(
                "When enabled, ImportSheet may show Replace for duplicate or name conflicts. " +
                    "Replace still requires Trash and a second confirmation."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
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
        model.diagnosticsState.isCollecting ? "Exporting diagnostics..." : "Export diagnostics..."
    }
}
