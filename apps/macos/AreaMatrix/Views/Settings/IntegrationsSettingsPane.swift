import SwiftUI

struct IntegrationsSettingsPane: View {
    @StateObject private var model: IntegrationsSettingsModel
    @State private var isConflictListPresented = false

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        statusDetector: any ICloudStatusDetecting = LocalICloudStatusDetector(),
        finderOpener: any RepositoryFinderOpening = NSWorkspaceRepositoryFinderOpener(),
        helpOpener: any ICloudHelpOpening = NSWorkspaceICloudHelpOpener()
    ) {
        _model = StateObject(wrappedValue: IntegrationsSettingsModel(
            repoPath: repoPath,
            loader: loader,
            updater: updater,
            errorMapper: errorMapper,
            statusDetector: statusDetector,
            finderOpener: finderOpener,
            helpOpener: helpOpener
        ))
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
        .sheet(isPresented: $isConflictListPresented) {
            ICloudConflictListView(
                model: ICloudConflictListModel(repoPath: model.repoPath),
                onClose: { isConflictListPresented = false },
                onResolve: model.recordConflictResolveEntry,
                onCollectDiagnostics: model.recordConflictDiagnosticsEntry
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("集成")
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
            if model.loadState == .loading || model.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(model.isSaving ? "Saving integration settings" : "Checking iCloud status")
            } else if model.canRetryStatus {
                Button {
                    Task {
                        await model.load()
                    }
                } label: {
                    Label("Retry status", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("S1-29-retry-status")
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
            Text("Checking integrations...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadErrorContent(_ error: IntegrationsSettingsError) -> some View {
        ContentUnavailableView {
            Label("Unable to load integrations", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.message)
            Text(error.recovery)
        } actions: {
            Button("Retry status") {
                Task {
                    await model.load()
                }
            }
            .accessibilityIdentifier("S1-29-load-error-retry-status")
        }
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                feedbackBanner
                saveErrorBanner
                if let summary = model.summary {
                    iCloudDriveSection(summary)
                    externalToolsSection
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
        }
    }

    private func iCloudDriveSection(_ summary: IntegrationsSettingsSummary) -> some View {
        IntegrationsSettingsSection(title: "iCloud Drive") {
            VStack(alignment: .leading, spacing: 12) {
                IntegrationsSettingsKeyValueRow(label: "Repository location", value: summary.repositoryLocation.label)
                IntegrationsSettingsKeyValueRow(label: "iCloud status", value: summary.iCloudStatus.label)
                IntegrationsSettingsKeyValueRow(
                    label: "Placeholder handling",
                    value: "Downloaded when AreaMatrix needs to read the file"
                )
                IntegrationsSettingsKeyValueRow(
                    label: "Conflict handling",
                    value: "Conflicted copies are shown for review"
                )

                Text(
                    "AreaMatrix stores your files in a normal folder. If that folder is in iCloud Drive, " +
                        "iCloud controls sync timing. AreaMatrix will not delete conflict copies automatically."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if summary.shouldShowICloudRiskWarning {
                    iCloudRiskWarning
                }

                Toggle("Show iCloud warnings", isOn: iCloudWarningsSelection)
                    .disabled(writesDisabled)
                    .accessibilityIdentifier("S1-29-C1-04-icloud-warnings")

                HStack(spacing: 10) {
                    Button {
                        model.openICloudHelp()
                    } label: {
                        Label("Open iCloud help", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("S1-29-open-icloud-help")

                    Button {
                        isConflictListPresented = true
                    } label: {
                        Label(
                            IntegrationsSettingsConflictListPresentation.reviewConflictsTitle,
                            systemImage: "exclamationmark.icloud"
                        )
                    }
                    .accessibilityIdentifier(
                        IntegrationsSettingsConflictListPresentation.reviewConflictsAccessibilityID
                    )

                    Button {
                        model.revealRepositoryInFinder()
                    } label: {
                        Label("Reveal repository in Finder", systemImage: "folder")
                    }
                    .accessibilityIdentifier("S1-29-reveal-repository")

                    if summary.canRetryStatus {
                        Button {
                            Task {
                                await model.load()
                            }
                        } label: {
                            Label("Retry status", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.loadState == .loading)
                        .accessibilityIdentifier("S1-29-card-retry-status")
                    }
                }
            }
        }
    }

    private var iCloudRiskWarning: some View {
        Label {
            Text("iCloud may delay sync, keep placeholder files offline, or create conflicted copies.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(.orange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("S1-29-icloud-risk-warning")
    }

    private var externalToolsSection: some View {
        IntegrationsSettingsSection(title: "Finder and other apps") {
            Text("You can open files directly in Finder. External changes are picked up by file watching when available.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let feedback = model.actionFeedback {
            switch feedback {
            case .success(let message):
                Label(message, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
            case .failed(let error):
                IntegrationsSettingsErrorBanner(error: error, tint: .red)
            }
        }
    }

    @ViewBuilder
    private var saveErrorBanner: some View {
        if let error = model.saveError {
            VStack(alignment: .leading, spacing: 8) {
                IntegrationsSettingsErrorBanner(error: error, tint: .red)
                Text("The UI has been restored to the last saved integration setting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.hasRetryableSave {
                    Button("Retry save") {
                        Task {
                            await model.retrySave()
                        }
                    }
                    .accessibilityIdentifier("S1-29-retry-save")
                }
            }
        }
    }

    private var writesDisabled: Bool {
        model.isSaving || !model.isLoaded
    }

    private var iCloudWarningsSelection: Binding<Bool> {
        Binding(
            get: { model.summary?.iCloudWarningsEnabled ?? true },
            set: { isEnabled in
                Task {
                    await model.setICloudWarningsEnabled(isEnabled)
                }
            }
        )
    }
}

private struct IntegrationsSettingsSection<Content: View>: View {
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

private struct IntegrationsSettingsKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(label): \(value)")
        }
        .font(.callout)
    }
}

private struct IntegrationsSettingsErrorBanner: View {
    let error: IntegrationsSettingsError
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(tint)
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
