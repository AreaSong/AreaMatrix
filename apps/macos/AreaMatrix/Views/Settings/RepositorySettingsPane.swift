import SwiftUI

struct RepositorySettingsPane: View {
    @StateObject private var model: RepositorySettingsModel
    let onChangeRepository: () -> Void
    let onOpenRecoveryTools: () -> Void

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
        generatedOverviewRevealer: any RepositoryFileRevealing = NSWorkspaceRepositoryFileRevealer(),
        diagnosticsCollector: any CoreDiagnosticsCollecting = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = VoiceOverAccessibilityAnnouncer(),
        onChangeRepository: @escaping () -> Void = {},
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
            generatedOverviewRevealer: generatedOverviewRevealer,
            diagnosticsCollector: diagnosticsCollector,
            errorMapper: errorMapper,
            accessibilityAnnouncer: accessibilityAnnouncer
        ))
        self.onChangeRepository = onChangeRepository
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
            Text("Diagnostics do not include your original file contents and are not uploaded automatically.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("资料库")
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
                        await model.load()
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
        case .loaded(let summary):
            loadedContent(summary)
        case .failed(let error):
            loadErrorContent(error)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Checking repository...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadErrorContent(_ error: RepositorySettingsLoadError) -> some View {
        ContentUnavailableView {
            Label("Unable to load repository status", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.message)
            Text(error.recovery)
        } actions: {
            Button("Retry status") {
                Task {
                    await model.load()
                }
            }
            Button("Change repository...", action: onChangeRepository)
            Button("Open recovery tools...", action: onOpenRecoveryTools)
        }
    }

    private func loadedContent(_ summary: RepositorySettingsSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                syncErrorBanner
                healthErrorBanner
                overviewActionErrorBanner
                repositoryActionBanner
                diagnosticsStatusBanner

                repositoryPathSection(summary)
                repositoryHealthSection
                repositoryOverviewSection(summary)
                repositorySafeActionsSection
                metadataDeletionWarning
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
            RepositorySettingsKeyValueRow(label: "Metadata", value: summary.metadataStatus)
            repositoryPathActions
        }
    }

    private var repositoryHealthSection: some View {
        RepositorySettingsSection(title: "健康") {
            RepositorySettingsHealthSection(summary: model.healthSummary)
        }
    }

    private func repositoryOverviewSection(_ summary: RepositorySettingsSummary) -> some View {
        RepositorySettingsSection(title: "概览输出") {
            RepositorySettingsKeyValueRow(label: "Generated overview", value: summary.overviewMode)
            RepositorySettingsKeyValueRow(label: "Generated path", value: summary.generatedPath)
            RepositorySettingsKeyValueRow(label: "Root file", value: summary.rootFile)
            RepositorySettingsKeyValueRow(label: "README.md", value: summary.readmePolicy)
            Button("Reveal generated overview") {
                model.revealGeneratedOverviewInFinder()
            }
            .accessibilityIdentifier("S1-27-C1-20-reveal-generated-overview")
        }
    }

    private var repositorySafeActionsSection: some View {
        RepositorySettingsSection(title: "安全动作") {
            Button(diagnosticsButtonTitle) {
                model.requestDiagnosticsExport()
            }
            .disabled(model.diagnosticsState.isCollecting)
            .accessibilityIdentifier("S1-27-export-diagnostics")

            if model.healthError?.databaseStatus == .needsRecovery {
                Button("Open recovery tools...", action: onOpenRecoveryTools)
                    .accessibilityIdentifier("S1-27-open-recovery-tools")
            }

            Text("Diagnostics do not include your original file contents and are not uploaded automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var metadataDeletionWarning: some View {
        Text(
            "Deleting the .areamatrix folder removes AreaMatrix metadata, not your original files. " +
                "Do this only if you know what you are doing."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var repositoryPathActions: some View {
        HStack(spacing: 10) {
            Button("Reveal in Finder") {
                model.revealRepositoryInFinder()
            }
            .accessibilityIdentifier("S1-27-reveal-repository")

            Button("Copy path") {
                model.copyRepositoryPath()
            }
            .accessibilityIdentifier("S1-27-copy-repository-path")

            Button("Change repository...", action: onChangeRepository)
                .accessibilityIdentifier("S1-27-change-repository")
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
        case .collected(let snapshot):
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
        case .failed(let error):
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

    @ViewBuilder
    private var overviewActionErrorBanner: some View {
        if let error = model.overviewActionError {
            VStack(alignment: .leading, spacing: 8) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error.recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        }
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
}
