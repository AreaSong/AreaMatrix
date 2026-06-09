import SwiftUI

struct AboutSettingsPane: View {
    @StateObject private var model: AboutSettingsModel

    init(
        repoPath: String,
        appVersionReader: any AppVersionReading = BundleAppVersionReader(),
        coreVersionReader: any CoreVersionReading = CoreBridge(),
        metadataReader: any ExistingRepositoryMetadataReading = SQLiteExistingRepositoryMetadataReader(),
        diagnosticsExporter: any AboutDiagnosticsExporting = LocalAboutDiagnosticsExporter(),
        externalLinkOpener: any AboutExternalLinkOpening = NSWorkspaceAboutExternalLinkOpener(),
        logsOpener: any AboutLogsOpening = NSWorkspaceAboutLogsOpener(),
        stringCopier: any AboutStringCopying = NSPasteboardAboutStringCopier(),
        diagnosticsRevealer: any AboutDiagnosticsRevealing = NSWorkspaceAboutDiagnosticsRevealer(),
        errorMapper: any CoreErrorMapping = LocalAboutCoreErrorMapper(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = VoiceOverAccessibilityAnnouncer()
    ) {
        _model = StateObject(wrappedValue: AboutSettingsModel(
            repoPath: repoPath,
            appVersionReader: appVersionReader,
            coreVersionReader: coreVersionReader,
            metadataReader: metadataReader,
            diagnosticsExporter: diagnosticsExporter,
            externalLinkOpener: externalLinkOpener,
            logsOpener: logsOpener,
            stringCopier: stringCopier,
            diagnosticsRevealer: diagnosticsRevealer,
            errorMapper: errorMapper,
            accessibilityAnnouncer: accessibilityAnnouncer
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    versionErrorBanner
                    actionFeedbackBanner
                    versionsSection
                    PlatformDifferencesView()
                    licenseSection
                    linksSection
                    diagnosticsSection
                    logsSection
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await model.load()
        }
        .confirmationDialog(
            "Collect diagnostics?",
            isPresented: diagnosticsConfirmationBinding
        ) {
            Button("Cancel", role: .cancel, action: model.cancelDiagnosticsExport)
            Button("Collect diagnostics") {
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
                Text("关于")
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
            if model.isLoadingVersionInfo {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading version information")
            } else {
                Button {
                    Task {
                        await model.load()
                    }
                } label: {
                    Label("Retry version check", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("S1-31-retry-version-check")
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var versionErrorBanner: some View {
        if let error = model.versionError {
            AboutSettingsBanner(error: error, tint: .orange) {
                Button("Copy error") {
                    model.copyActionDetail(error)
                }
            }
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
                AboutSettingsBanner(error: error, tint: .red) {
                    Button("Copy detail") {
                        model.copyActionDetail(error)
                    }
                }
            }
        }
    }

    private var versionsSection: some View {
        AboutSettingsSection(title: "Versions") {
            AboutSettingsKeyValueRow(label: "App version", value: model.versionInfo.appVersion)
            AboutSettingsKeyValueRow(label: "Core version", value: model.versionInfo.coreVersion)
            AboutSettingsKeyValueRow(label: "Schema version", value: model.versionInfo.schemaVersion)
            Button {
                model.copyVersionSummary()
            } label: {
                Label("Copy versions", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("S1-31-copy-versions")
        }
    }

    private var licenseSection: some View {
        AboutSettingsSection(title: "License") {
            Text("PolyForm Noncommercial")
                .font(.callout)
                .textSelection(.enabled)
                .accessibilityIdentifier("S1-31-license")
        }
    }

    private var linksSection: some View {
        AboutSettingsSection(title: "Links") {
            ForEach(AboutExternalLink.allCases) { link in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button {
                            model.openExternalLink(link)
                        } label: {
                            Label(link.title, systemImage: link.systemImage)
                        }
                        .accessibilityIdentifier("S1-31-open-\(link.rawValue)")

                        Button {
                            model.copyExternalLink(link)
                        } label: {
                            Label("Copy URL", systemImage: "doc.on.doc")
                        }
                        .accessibilityIdentifier("S1-31-copy-\(link.rawValue)")
                    }

                    Text(link.urlString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        AboutSettingsSection(title: "Diagnostics") {
            Button {
                model.requestDiagnosticsExport()
            } label: {
                Label(model.diagnosticsButtonTitle, systemImage: "doc.badge.gearshape")
            }
            .disabled(model.diagnosticsState.isCollecting)
            .accessibilityIdentifier("S1-31-collect-diagnostics")

            Text("Diagnostics are redacted, exclude original file contents, and are not uploaded automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            diagnosticsStatus
        }
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch model.diagnosticsState {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Collecting redacted diagnostics...")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        case let .collected(snapshot):
            VStack(alignment: .leading, spacing: 8) {
                Label("Diagnostics exported", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Text(snapshot.exportPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    Button("Reveal in Finder") {
                        model.revealDiagnostics(snapshot)
                    }
                    Button("Copy diagnostics path") {
                        model.copyDiagnosticsPath(snapshot)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        case let .failed(error):
            AboutSettingsBanner(error: error, tint: .red) {
                Button("Copy error") {
                    model.copyActionDetail(error)
                }
                Button("Retry") {
                    model.requestDiagnosticsExport()
                }
            }
        }
    }

    private var logsSection: some View {
        AboutSettingsSection(title: "Logs") {
            HStack(spacing: 10) {
                Button {
                    model.openLogs()
                } label: {
                    Label("Open logs in Console", systemImage: "terminal")
                }
                .disabled(model.diagnosticsState.isCollecting)
                .accessibilityIdentifier("S1-31-open-logs")

                Button {
                    model.copyLogsPath()
                } label: {
                    Label("Copy logs path", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("S1-31-copy-logs-path")
            }

            Text(model.logsPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
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
}

private struct AboutSettingsKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .accessibilityLabel("\(label): \(value)")
        }
        .font(.callout)
    }
}

private struct AboutSettingsSection<Content: View>: View {
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

private struct AboutSettingsBanner<Actions: View>: View {
    let error: AboutSettingsError
    let tint: Color
    private let actions: Actions

    init(error: AboutSettingsError, tint: Color, @ViewBuilder actions: () -> Actions) {
        self.error = error
        self.tint = tint
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(tint)
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(error.copyableDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
            HStack(spacing: 10) {
                actions
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
