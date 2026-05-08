import SwiftUI

struct AdvancedSettingsPane: View {
    @StateObject private var model: AdvancedSettingsModel
    @State private var isDangerZoneExpanded = false
    private let onOpenRecoveryTools: () -> Void

    init(
        repoPath: String,
        onOpenRecoveryTools: @escaping () -> Void = {},
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        rootOverviewInspector: any RootOverviewFileInspecting = LocalRootOverviewFileInspector(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        _model = StateObject(wrappedValue: AdvancedSettingsModel(
            repoPath: repoPath,
            loader: loader,
            updater: updater,
            rootOverviewInspector: rootOverviewInspector,
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
        case .failed(let error):
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
                dangerZoneSection
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
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
                    .accessibilityIdentifier("S1-30-C1-04-retry-save")
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
            .accessibilityIdentifier("S1-30-C1-04-overview-output")

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
}

struct AdvancedSettingsRecoveryToolsSection: View {
    let onOpenRecoveryTools: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recovery tools")
                .font(.headline)
            Button {
                onOpenRecoveryTools()
            } label: {
                Label("Open recovery tools...", systemImage: "arrow.clockwise.circle")
            }
            .accessibilityIdentifier("S1-30-C1-16-open-recovery-tools")
            Text(
                "Startup cleanup and staging recovery stay in the dedicated recovery flow " +
                    "with confirmation before metadata actions."
            )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AdvancedSettingsSection<Content: View>: View {
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

private struct AdvancedRootOverviewConfirmationSheet: View {
    let status: RootOverviewFileStatus
    let onCancel: () -> Void
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enable root AREAMATRIX.md?")
                .font(.title2.weight(.semibold))
            Text(
                "AreaMatrix may create or update AREAMATRIX.md at the repository root " +
                    "on the next overview regeneration. " +
                    "Existing content outside the managed marker block is preserved. README.md is never modified."
            )
            .fixedSize(horizontal: false, vertical: true)
            Text(status.confirmationDetail)
                .foregroundStyle(status.canEnableRootOverview ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Enable root file", action: onEnable)
                    .buttonStyle(.borderedProminent)
                    .disabled(!status.canEnableRootOverview)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
