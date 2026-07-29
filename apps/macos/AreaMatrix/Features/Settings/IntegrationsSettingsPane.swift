import SwiftUI

struct IntegrationsSettingsPane: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: IntegrationsSettingsModel
    @State private var isConflictListPresented = false

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        statusDetector: any ICloudStatusDetecting = IntegrationsSettingsPlatformServices.statusDetector,
        finderOpener: any RepositoryFinderOpening = IntegrationsSettingsPlatformServices.finderOpener,
        helpOpener: any ICloudHelpOpening = IntegrationsSettingsPlatformServices.helpOpener
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
                pageContext: .iCloudConflictVisualConflictVisual,
                onClose: { isConflictListPresented = false },
                onResolve: model.recordConflictResolveEntry,
                onCollectDiagnostics: model.recordConflictDiagnosticsEntry
            )
        }
    }

    private var header: some View {
        SettingsPageHeader(title: L10n.string("settings.page.integrations"), subtitle: model.repoPath) {
            if model.loadState == .loading || model.isSaving {
                SettingsHeaderProgressIndicator(
                    label: model.isSaving
                        ? L10n.string("Saving integration settings")
                        : L10n.string("Checking iCloud status")
                )
            } else if model.canRetryStatus {
                Button {
                    Task {
                        await model.load()
                    }
                } label: {
                    Label(L10n.string("Retry status"), systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("integrations-settings-retry-status")
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
        SettingsPageLoadingContent(title: L10n.string("settings.loading.integrations"))
    }

    private func loadErrorContent(_ error: IntegrationsSettingsError) -> some View {
        SettingsPageErrorContent(
            title: L10n.string("settings.error.loadIntegrations"),
            message: localizer.resolve(error.message),
            recovery: localizer.resolve(error.recovery)
        ) {
            Button(L10n.string("Retry status")) {
                Task {
                    await model.load()
                }
            }
            .accessibilityIdentifier("integrations-settings-load-error-retry-status")
        }
    }

    private var loadedContent: some View {
        SettingsPageScrollContent {
            feedbackBanner
            saveErrorBanner
            if let summary = model.summary {
                iCloudDriveSection(summary)
                externalToolsSection
            }
        }
    }

    private func iCloudDriveSection(_ summary: IntegrationsSettingsSummary) -> some View {
        IntegrationsSettingsSection(title: L10n.string("iCloud Drive")) {
            VStack(alignment: .leading, spacing: 12) {
                IntegrationsSettingsKeyValueRow(
                    label: L10n.string("Repository location"),
                    value: summary.repositoryLocation.label
                )
                IntegrationsSettingsKeyValueRow(label: L10n.string("iCloud status"), value: summary.iCloudStatus.label)
                IntegrationsSettingsKeyValueRow(
                    label: L10n.string("Placeholder handling"),
                    value: L10n.string("Downloaded when AreaMatrix needs to read the file")
                )
                IntegrationsSettingsKeyValueRow(
                    label: L10n.string("Conflict handling"),
                    value: L10n.string("Conflicted copies are shown for review")
                )

                iCloudDriveDescription

                if summary.shouldShowICloudRiskWarning {
                    iCloudRiskWarning
                }

                iCloudWarningsToggle
                iCloudDriveActions(summary)
            }
        }
    }

    private var iCloudDriveDescription: some View {
        Text(L10n.string("settings.integrations.iCloudFolderDetail"))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var iCloudWarningsToggle: some View {
        Toggle(L10n.string("Show iCloud warnings"), isOn: iCloudWarningsSelection)
            .disabled(writesDisabled)
            .accessibilityIdentifier("integrations-settings-repository-config-icloud-warnings")
    }

    private func iCloudDriveActions(_ summary: IntegrationsSettingsSummary) -> some View {
        HStack(spacing: 10) {
            iCloudHelpButton
            reviewConflictsButton
            revealRepositoryButton
            if summary.canRetryStatus {
                retryStatusButton
            }
        }
    }

    private var iCloudHelpButton: some View {
        Button {
            model.openICloudHelp()
        } label: {
            Label(L10n.string("Open iCloud help"), systemImage: "questionmark.circle")
        }
        .accessibilityIdentifier("integrations-settings-open-icloud-help")
    }

    private var reviewConflictsButton: some View {
        Button {
            isConflictListPresented = true
        } label: {
            Label(IntegrationConflictListPresentation.reviewConflictsTitle, systemImage: "exclamationmark.icloud")
        }
        .accessibilityIdentifier(IntegrationConflictListPresentation.reviewConflictsAccessibilityID)
    }

    private var revealRepositoryButton: some View {
        Button {
            model.revealRepositoryInFinder()
        } label: {
            Label(L10n.string("Reveal repository in Finder"), systemImage: "folder")
        }
        .accessibilityIdentifier("integrations-settings-reveal-repository")
    }

    private var retryStatusButton: some View {
        Button {
            Task { await model.load() }
        } label: {
            Label(L10n.string("Retry status"), systemImage: "arrow.clockwise")
        }
        .disabled(model.loadState == .loading)
        .accessibilityIdentifier("integrations-settings-card-retry-status")
    }

    private var iCloudRiskWarning: some View {
        SettingsStatusBanner(
            title: L10n.string(
                "iCloud may delay sync, keep placeholder files offline, or create conflicted copies."
            ),
            systemImage: "exclamationmark.triangle",
            tint: .orange
        )
        .accessibilityIdentifier("integrations-settings-icloud-risk-warning")
    }

    private var externalToolsSection: some View {
        IntegrationsSettingsSection(title: L10n.string("Finder and other apps")) {
            Text(
                L10n
                    .string(
                        // swiftlint:disable:next line_length
                        "You can open files directly in Finder. External changes are picked up by file watching when available."
                    )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let feedback = model.actionFeedback {
            switch feedback {
            case let .success(message):
                SettingsStatusBanner(title: localizer.resolve(message), systemImage: "checkmark.circle", tint: .green)
            case let .failed(error):
                IntegrationsSettingsErrorBanner(error: error, tint: .red)
            }
        }
    }

    @ViewBuilder
    private var saveErrorBanner: some View {
        if let error = model.saveError {
            VStack(alignment: .leading, spacing: 8) {
                IntegrationsSettingsErrorBanner(error: error, tint: .red)
                Text(L10n.string("The UI has been restored to the last saved integration setting."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.hasRetryableSave {
                    Button(L10n.string("Retry save")) {
                        Task {
                            await model.retrySave()
                        }
                    }
                    .accessibilityIdentifier("integrations-settings-retry-save")
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

private struct IntegrationsSettingsKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        SettingsKeyValueRow(label: label, value: value, labelWidth: 150, valueLayout: .wrapping)
    }
}

private struct IntegrationsSettingsErrorBanner: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let error: IntegrationsSettingsError
    let tint: Color

    var body: some View {
        SettingsStatusBanner(
            title: localizer.resolve(error.message),
            systemImage: "exclamationmark.triangle",
            tint: tint
        ) {
            Text(localizer.resolve(error.recovery))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
