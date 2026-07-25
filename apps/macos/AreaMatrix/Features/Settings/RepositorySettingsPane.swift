import SwiftUI

struct RepositorySettingsPane: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: RepositorySettingsModel
    @StateObject private var capabilityModel: RepoPlatformCapabilitiesModel
    @StateObject private var configModel: RepositorySettingsConfigModel
    @StateObject private var overviewRegenerationModel: RepositoryOverviewRegenerationModel
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
        overviewRegenerator: any CoreOverviewRegenerating = AppCoreServices.overviewRegenerator,
        overviewRegenerationCoordinator: OverviewRegenerationCoordinator? = nil,
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
            loader: loader,
            updater: updater,
            errorMapper: errorMapper,
            accessibilityAnnouncer: accessibilityAnnouncer
        ))
        _overviewRegenerationModel = StateObject(wrappedValue: RepositoryOverviewRegenerationModel(
            repoPath: repoPath,
            bridge: overviewRegenerator,
            coordinator: overviewRegenerationCoordinator,
            errorMapper: errorMapper
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
            Button(L10n.string("Cancel"), role: .cancel, action: model.cancelDiagnosticsExport)
            Button(L10n.string("Export diagnostics")) {
                Task {
                    await model.collectDiagnostics()
                }
            }
        } message: {
            Text(L10n.string("Diagnostics do not include your original file contents and are not uploaded automatically."))
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
        .onDisappear(perform: model.cancelDiagnosticsExport)
    }

    private var emptyRepositoryBody: some View {
        ContentUnavailableView {
            Label(L10n.string("No repository connected."), systemImage: "folder.badge.questionmark")
        } description: {
            Text(L10n.string("Connect a repository to view cross-platform repository settings."))
        } actions: {
            Button(L10n.string("Connect Repository"), action: onChangeRepository)
                .accessibilityIdentifier("repository-settings-connect-repository")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        SettingsPageHeader(title: L10n.string("settings.page.repository"), subtitle: model.repoPath) {
            if model.isLoading {
                SettingsHeaderProgressIndicator(label: L10n.string("Checking repository configuration"))
            } else {
                Button(L10n.string("Retry status")) {
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
        SettingsPageLoadingContent(title: L10n.string("settings.loading.repository"))
    }

    private func loadErrorContent(_ error: RepositorySettingsLoadError) -> some View {
        SettingsPageErrorContent(
            title: L10n.string("settings.error.loadRepository"),
            message: localizer.resolve(error.message),
            recovery: localizer.resolve(error.recovery)
        ) {
            Button(L10n.string("Try again")) {
                Task {
                    await model.load()
                }
            }
            Button(L10n.string("Change repository..."), action: onChangeRepository)
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
            RepositoryOverviewRegenerationSection(model: overviewRegenerationModel)
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
                await reload()
            }
        )
    }

    @ViewBuilder
    private var repositoryActionBanner: some View {
        if let error = model.repositoryActionError {
            SettingsStatusBanner(
                title: localizer.resolve(error.message),
                systemImage: "exclamationmark.triangle",
                tint: .red
            ) {
                Text(localizer.resolve(error.recovery))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if let message = model.repositoryActionMessage {
            SettingsStatusBanner(title: localizer.resolve(message), systemImage: "checkmark.circle", tint: .green)
        }
    }

    @ViewBuilder
    private var diagnosticsStatusBanner: some View {
        switch model.diagnosticsState {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            SettingsProgressBanner(title: L10n.string("Preparing diagnostics..."))
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
            }
        case let .failed(error):
            SettingsStatusBanner(
                title: localizer.resolve(error.message),
                systemImage: "exclamationmark.triangle",
                tint: .red
            ) {
                Text(localizer.resolve(error.recovery))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var diagnosticsButtonTitle: String {
        model.diagnosticsState.isCollecting
            ? L10n.string("Exporting diagnostics...")
            : L10n.string("Export diagnostics...")
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
        if let concreteLocale = resolvedContentLocale {
            await overviewRegenerationModel.load(contentLocale: concreteLocale)
        }
    }

    @ViewBuilder
    private var syncErrorBanner: some View {
        if let error = model.syncError {
            SettingsStatusBanner(
                title: localizer.resolve(error.message),
                systemImage: "exclamationmark.triangle",
                tint: .red
            ) {
                Text(localizer.resolve(error.recovery))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(L10n.string("Retry path sync")) {
                    Task {
                        await model.retryRepositoryPathSync()
                    }
                }
                .accessibilityIdentifier("repository-settings-retry-path-sync")
            }
        }
    }

    private var resolvedContentLocale: String? {
        guard let config = model.loadedConfig else { return nil }
        return try? RepositoryContentLanguage(snapshotValue: config.locale)
            .resolvedIdentifier(interfaceLocaleIdentifier: AppLanguageRuntime.shared.resolvedIdentifier())
    }

    @ViewBuilder
    private var healthErrorBanner: some View {
        if let error = model.healthError {
            let tint: Color = error.databaseStatus == .locked ? .orange : .red
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
}
