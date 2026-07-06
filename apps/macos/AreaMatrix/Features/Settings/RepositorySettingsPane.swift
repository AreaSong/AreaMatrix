import SwiftUI

struct RepositorySettingsPane: View {
    @StateObject private var model: RepositorySettingsModel
    @StateObject private var capabilityModel: RepoPlatformCapabilitiesModel
    @StateObject private var configModel: RepositorySettingsConfigModel
    let onChangeRepository: () -> Void
    let onOpenPlatformCapabilities: () -> Void
    let onOpenRecoveryTools: () -> Void
}

extension RepositorySettingsPane {
    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        repositoryOpener: any CoreEmptyRepositoryOpening = AppCoreServices.emptyRepositoryOpener,
        fileLister: (any CoreFileListing)? = nil,
        scanSessionReader: any CoreScanSessionReading = AppCoreServices.scanSessionReader,
        existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading =
            RepositorySettingsPlatformServices.metadataReader,
        finderOpener: any RepositoryFinderOpening = RepositorySettingsPlatformServices.finderOpener,
        pathCopier: any RepositoryPathCopying = RepositorySettingsPlatformServices.pathCopier,
        diagnosticsCollector: any CoreDiagnosticsCollecting = AppCoreServices.diagnosticsCollector,
        coreVersionLoader: any CoreVersionLoading = AppCoreServices.coreVersionLoader,
        capabilityLoader: any CorePlatformCapabilitiesLoading = AppCoreServices.platformCapabilityLoader,
        appVersion: String? = nil,
        appVersionReader: any AppVersionReading = RepositorySettingsPlatformServices.appVersionReader,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        accessibilityAnnouncer: any AccessibilityAnnouncing = RepositorySettingsPlatformServices.accessibilityAnnouncer,
        onChangeRepository: @escaping () -> Void = {},
        onOpenPlatformCapabilities: @escaping () -> Void = {},
        onOpenRecoveryTools: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: RepositorySettingsModel(
            repoPath: repoPath,
            loader: loader,
            updater: updater,
            repositoryOpener: repositoryOpener,
            fileLister: fileLister,
            scanSessionReader: scanSessionReader,
            existingRepositoryMetadataReader: existingRepositoryMetadataReader,
            finderOpener: finderOpener,
            pathCopier: pathCopier,
            diagnosticsCollector: diagnosticsCollector,
            coreVersionLoader: coreVersionLoader,
            errorMapper: errorMapper,
            accessibilityAnnouncer: accessibilityAnnouncer
        ))
        _capabilityModel = StateObject(wrappedValue: RepoPlatformCapabilitiesModel(
            appVersion: appVersion,
            appVersionReader: appVersionReader,
            capabilityLoader: capabilityLoader,
            errorMapper: errorMapper
        ))
        _configModel = StateObject(wrappedValue: RepositorySettingsConfigModel(
            repoPath: repoPath,
            updater: updater,
            errorMapper: errorMapper,
            accessibilityAnnouncer: accessibilityAnnouncer
        ))
        self.onChangeRepository = onChangeRepository
        self.onOpenPlatformCapabilities = onOpenPlatformCapabilities
        self.onOpenRecoveryTools = onOpenRecoveryTools
    }

    var body: some View {
        Group {
            if model.hasConnectedRepository {
                connectedRepositoryBody
            } else {
                emptyRepositoryBody
            }
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
            Text("Diagnostics do not include your original file contents and are not uploaded automatically.")
        }
    }

    private var connectedRepositoryBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await reload()
        }
    }

    private var emptyRepositoryBody: some View {
        ContentUnavailableView {
            Label("No repository connected.", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Connect a repository to view cross-platform repository settings.")
        } actions: {
            Button("Connect Repository", action: onChangeRepository)
                .accessibilityIdentifier("repository-settings-connect-repository")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        SettingsPageHeader(title: "Repository Settings", subtitle: model.repoPath) {
            if model.isLoading {
                SettingsHeaderProgressIndicator(label: "Checking repository configuration")
            } else {
                Button("Retry status") {
                    Task {
                        await reload()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            loadingContent
        case let .loaded(summary):
            loadedContent(summary)
        case let .failed(error):
            loadErrorContent(error)
        }
    }

    private var loadingContent: some View {
        SettingsPageLoadingContent(title: "Loading repository settings...")
    }

    private func loadErrorContent(_ error: RepositorySettingsLoadError) -> some View {
        SettingsPageErrorContent(
            title: "Could not load repository status",
            message: error.message,
            recovery: error.recovery
        ) {
            Button("Try again") {
                Task {
                    await model.load()
                }
            }
            Button("Change repository...", action: onChangeRepository)
        }
    }

    private func loadedContent(_ summary: RepositorySettingsSummary) -> some View {
        SettingsPageScrollContent {
            syncErrorBanner
            healthErrorBanner
            repositoryActionBanner
            diagnosticsStatusBanner

            RepositorySettingsPathSection(
                summary: summary,
                onRevealInFinder: model.revealRepositoryInFinder,
                onCopyPath: model.copyRepositoryPath,
                onChangeRepository: onChangeRepository
            )
            RepositorySettingsHealthSection(summary: model.healthSummary)
            platformCapabilitySection
            repositoryConfigSection
            RepositorySettingsSafeActionsSection(
                diagnosticsButtonTitle: diagnosticsButtonTitle,
                isDiagnosticsDisabled: model.diagnosticsState.isCollecting || !capabilityModel.allowsDiagnosticsExport,
                diagnosticsDisabledReason: capabilityModel.diagnosticsDisabledReason,
                onReconnectRepository: onChangeRepository,
                onChooseAnotherFolder: onChangeRepository,
                onExportDiagnostics: model.requestDiagnosticsExport
            )
        }
    }

    private var platformCapabilitySection: some View {
        RepoPlatformCapabilitySection(
            state: capabilityModel.state,
            onOpenPlatformCapabilities: onOpenPlatformCapabilities
        )
    }

    private var repositoryConfigSection: some View {
        RepositorySettingsConfigSection(
            config: model.loadedConfig,
            model: configModel,
            capabilityState: capabilityModel.state,
            onSaved: {
                await model.load()
            }
        )
    }

    @ViewBuilder
    private var repositoryActionBanner: some View {
        if let error = model.repositoryActionError {
            SettingsStatusBanner(title: error.message, systemImage: "exclamationmark.triangle", tint: .red) {
                Text(error.recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if let message = model.repositoryActionMessage {
            SettingsStatusBanner(title: message, systemImage: "checkmark.circle", tint: .green)
        }
    }

    @ViewBuilder
    private var diagnosticsStatusBanner: some View {
        switch model.diagnosticsState {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            SettingsProgressBanner(title: "Preparing diagnostics...")
        case let .collected(snapshot):
            SettingsStatusBanner(title: "Diagnostics exported", systemImage: "checkmark.circle", tint: .green) {
                Text(snapshot.snapshotPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case let .failed(error):
            SettingsStatusBanner(title: error.message, systemImage: "exclamationmark.triangle", tint: .red) {
                Text(error.recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var diagnosticsButtonTitle: String {
        model.diagnosticsState.isCollecting ? "Exporting diagnostics..." : "Export diagnostics..."
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

    private func reload() async {
        await model.load()
        await capabilityModel.load()
    }

    @ViewBuilder
    private var syncErrorBanner: some View {
        if let error = model.syncError {
            SettingsStatusBanner(title: error.message, systemImage: "exclamationmark.triangle", tint: .red) {
                Text(error.recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var healthErrorBanner: some View {
        if let error = model.healthError {
            let tint: Color = error.databaseStatus == .locked ? .orange : .red
            SettingsStatusBanner(title: error.message, systemImage: "exclamationmark.triangle", tint: tint) {
                Text(error.recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
