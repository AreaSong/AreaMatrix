import SwiftUI

struct RepositorySettingsPane: View {
    @StateObject private var model: RepositorySettingsModel
    @StateObject private var capabilityModel: RepositorySettingsPlatformCapabilitiesModel
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
        appVersion: String = RepositorySettingsPlatformCapabilitiesModel.defaultAppVersion(),
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
        _capabilityModel = StateObject(wrappedValue: RepositorySettingsPlatformCapabilitiesModel(
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
                .accessibilityIdentifier("S4-X-08-connect-repository")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repository Settings")
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
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking repository configuration")
            } else {
                Button("Retry status") {
                    Task {
                        await reload()
                    }
                }
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
        case let .loaded(summary):
            loadedContent(summary)
        case let .failed(error):
            loadErrorContent(error)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading repository settings...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadErrorContent(_ error: RepositorySettingsLoadError) -> some View {
        ContentUnavailableView {
            Label("Could not load repository status", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.message)
            Text(error.recovery)
        } actions: {
            Button("Try again") {
                Task {
                    await model.load()
                }
            }
            Button("Change repository...", action: onChangeRepository)
        }
    }

    private func loadedContent(_ summary: RepositorySettingsSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 28)
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
        RepositorySettingsPlatformCapabilitySection(
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
                .accessibilityIdentifier("S4-X-08-reconnect-repository")

            Button("Choose Another Folder", action: onChangeRepository)
                .accessibilityIdentifier("S4-X-08-choose-another-folder")

            Button(diagnosticsButtonTitle) {
                model.requestDiagnosticsExport()
            }
            .disabled(model.diagnosticsState.isCollecting || !capabilityModel.allowsDiagnosticsExport)
            .help(capabilityModel.diagnosticsDisabledReason ?? "Diagnostics export is available.")
            .accessibilityIdentifier("S4-X-08-export-diagnostics")

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
            .accessibilityIdentifier("S4-X-08-reveal-repository")

            Button("Copy path") {
                model.copyRepositoryPath()
            }
            .accessibilityIdentifier("S4-X-08-copy-repository-path")

            Button("Change repository...", action: onChangeRepository)
                .accessibilityIdentifier("S4-X-08-change-repository")
        }
    }

    @ViewBuilder
    private var repositoryActionBanner: some View {
        if let error = model.repositoryActionError {
            VStack(alignment: .leading, spacing: 8) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error.recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        } else if let message = model.repositoryActionMessage {
            Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
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
                Text("Preparing diagnostics...")
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
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        case let .failed(error):
            VStack(alignment: .leading, spacing: 8) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error.recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
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
            VStack(alignment: .leading, spacing: 8) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error.recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var healthErrorBanner: some View {
        if let error = model.healthError {
            let tint: Color = error.databaseStatus == .locked ? .orange : .red
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
}

private struct RepositorySettingsSection<Content: View>: View {
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

private struct RepositorySettingsKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .accessibilityLabel("\(label): \(value)")
        }
        .font(.callout)
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
