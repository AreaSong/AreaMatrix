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
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        repositoryOpener: any CoreEmptyRepositoryOpening = CoreBridge(),
        fileLister: (any CoreFileListing)? = nil,
        scanSessionReader: any CoreScanSessionReading = CoreBridge(),
        existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading =
            SQLiteExistingRepositoryMetadataReader(),
        finderOpener: any RepositoryFinderOpening = NSWorkspaceRepositoryFinderOpener(),
        pathCopier: any RepositoryPathCopying = NSPasteboardRepositoryPathCopier(),
        diagnosticsCollector: any CoreDiagnosticsCollecting = CoreBridge(),
        coreVersionLoader: any CoreVersionLoading = CoreBridge(),
        capabilityLoader: any CorePlatformCapabilitiesLoading = CoreBridge(),
        appVersion: String = RepoPlatformCapabilitiesModel.defaultAppVersion(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = VoiceOverAccessibilityAnnouncer(),
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

            repositoryPathSection(summary)
            repositoryHealthSection
            platformCapabilitySection
            repositoryConfigSection
            repositorySafeActionsSection
        }
    }

    private func repositoryPathSection(_ summary: RepositorySettingsSummary) -> some View {
        RepositorySettingsSection(title: "路径") {
            RepositorySettingsKeyValueRow(label: "Repository name", value: summary.repositoryName)
            RepositorySettingsKeyValueRow(label: "Location", value: summary.location)
            RepositorySettingsKeyValueRow(label: "Type", value: summary.locationType)
            RepositorySettingsKeyValueRow(label: "Core version", value: summary.coreVersion)
            RepositorySettingsKeyValueRow(label: "Metadata", value: summary.metadataStatus)
            repositoryPathActions
        }
    }

    private var repositoryHealthSection: some View {
        RepositorySettingsSection(title: "健康") {
            RepositorySettingsHealthSection(summary: model.healthSummary)
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

    private var repositorySafeActionsSection: some View {
        RepositorySettingsSection(title: "Actions") {
            Button("Reconnect Repository", action: onChangeRepository)
                .accessibilityIdentifier("repository-settings-reconnect-repository")

            Button("Choose Another Folder", action: onChangeRepository)
                .accessibilityIdentifier("repository-settings-choose-another-folder")

            Button(diagnosticsButtonTitle) {
                model.requestDiagnosticsExport()
            }
            .disabled(model.diagnosticsState.isCollecting || !capabilityModel.allowsDiagnosticsExport)
            .help(capabilityModel.diagnosticsDisabledReason ?? "Diagnostics export is available.")
            .accessibilityIdentifier("repository-settings-export-diagnostics")

            Text("Diagnostics do not include your original file contents and are not uploaded automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var repositoryPathActions: some View {
        HStack(spacing: 10) {
            Button("Reveal in Finder") {
                model.revealRepositoryInFinder()
            }
            .accessibilityIdentifier("repository-settings-reveal-repository")

            Button("Copy path") {
                model.copyRepositoryPath()
            }
            .accessibilityIdentifier("repository-settings-copy-repository-path")

            Button("Change repository...", action: onChangeRepository)
                .accessibilityIdentifier("repository-settings-change-repository")
        }
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

private struct RepositorySettingsHealthSection: View {
    let summary: RepositorySettingsHealthSummary?

    private static let indexedCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RepositorySettingsKeyValueRow(label: "Database", value: summary?.databaseStatus.label ?? "—")
            RepositorySettingsKeyValueRow(label: "Schema version", value: schemaVersionValue)
            RepositorySettingsKeyValueRow(label: "Files indexed", value: filesIndexedValue)
            RepositorySettingsKeyValueRow(label: "Last opened", value: lastOpenedValue)
            RepositorySettingsKeyValueRow(label: "Last scan", value: lastScanValue)
            RepositorySettingsKeyValueRow(label: "Watcher", value: summary?.watcherStatus.label ?? "Paused")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var schemaVersionValue: String {
        guard let schemaVersion = summary?.schemaVersion else {
            return "Unknown"
        }
        return "v\(schemaVersion)"
    }

    private var filesIndexedValue: String {
        guard let filesIndexed = summary?.filesIndexed else {
            return "—"
        }

        return Self.indexedCountFormatter.string(from: NSNumber(value: filesIndexed)) ?? "\(filesIndexed)"
    }

    private var lastScanValue: String {
        guard let timestamp = summary?.lastScanAt else {
            return "Not available"
        }

        return Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(date: .abbreviated, time: .shortened)
    }

    private var lastOpenedValue: String {
        guard let timestamp = summary?.lastOpenedAt else {
            return "Unknown"
        }

        return Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(date: .abbreviated, time: .shortened)
    }
}
