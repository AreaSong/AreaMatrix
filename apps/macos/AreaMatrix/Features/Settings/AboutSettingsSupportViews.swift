import SwiftUI

struct AboutSettingsHeader: View {
    let repoPath: String
    let isLoadingVersionInfo: Bool
    let onRetryVersionCheck: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Image("AreaMatrixLogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AreaMatrix")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(repoPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            if isLoadingVersionInfo {
                SettingsHeaderProgressIndicator(label: "Loading version information")
            } else {
                Button {
                    onRetryVersionCheck()
                } label: {
                    Label("Retry version check", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("about-settings-retry-version-check")
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct AboutSettingsVersionsSection: View {
    let versionInfo: AboutSettingsVersionInfo
    let onCopyVersions: () -> Void

    var body: some View {
        AboutSettingsSection(title: "Versions") {
            AboutSettingsKeyValueRow(label: "App version", value: versionInfo.appVersion)
            AboutSettingsKeyValueRow(label: "Core version", value: versionInfo.coreVersion)
            AboutSettingsKeyValueRow(label: "Schema version", value: versionInfo.schemaVersion)
            Button {
                onCopyVersions()
            } label: {
                Label("Copy versions", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("about-settings-copy-versions")
        }
    }
}

struct AboutSettingsLicenseSection: View {
    var body: some View {
        AboutSettingsSection(title: "License") {
            Text("PolyForm Noncommercial")
                .font(.callout)
                .textSelection(.enabled)
                .accessibilityIdentifier("about-settings-license")
        }
    }
}

struct AboutSettingsLinksSection: View {
    let onOpenLink: (AboutExternalLink) -> Void
    let onCopyLink: (AboutExternalLink) -> Void

    var body: some View {
        AboutSettingsSection(title: "Links") {
            ForEach(AboutExternalLink.allCases) { link in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button {
                            onOpenLink(link)
                        } label: {
                            Label(link.title, systemImage: link.systemImage)
                        }
                        .accessibilityIdentifier("about-settings-open-\(link.rawValue)")

                        Button {
                            onCopyLink(link)
                        } label: {
                            Label("Copy URL", systemImage: "doc.on.doc")
                        }
                        .accessibilityIdentifier("about-settings-copy-\(link.rawValue)")
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
}

struct AboutSettingsDiagnosticsSection: View {
    let diagnosticsButtonTitle: String
    let diagnosticsState: AboutSettingsDiagnosticsState
    let onRequestDiagnostics: () -> Void
    let onRevealDiagnostics: (AboutDiagnosticsExportSnapshot) -> Void
    let onCopyDiagnosticsPath: (AboutDiagnosticsExportSnapshot) -> Void
    let onCopyError: (AboutSettingsError) -> Void

    var body: some View {
        AboutSettingsSection(title: "Diagnostics") {
            Button {
                onRequestDiagnostics()
            } label: {
                Label(diagnosticsButtonTitle, systemImage: "doc.badge.gearshape")
            }
            .disabled(diagnosticsState.isCollecting)
            .accessibilityIdentifier("about-settings-collect-diagnostics")

            Text("Diagnostics are redacted, exclude original file contents, and are not uploaded automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            diagnosticsStatus
        }
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch diagnosticsState {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            SettingsProgressBanner(title: "Collecting redacted diagnostics...")
        case let .collected(snapshot):
            SettingsStatusBanner(title: "Diagnostics exported", systemImage: "checkmark.circle", tint: .green) {
                Text(snapshot.exportPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    Button("Reveal in Finder") {
                        onRevealDiagnostics(snapshot)
                    }
                    Button("Copy diagnostics path") {
                        onCopyDiagnosticsPath(snapshot)
                    }
                }
            }
        case let .failed(error):
            AboutSettingsBanner(error: error, tint: .red) {
                Button("Copy error") {
                    onCopyError(error)
                }
                Button("Retry") {
                    onRequestDiagnostics()
                }
            }
        }
    }
}

struct AboutSettingsLogsSection: View {
    let isDisabled: Bool
    let logsPath: String
    let onOpenLogs: () -> Void
    let onCopyLogsPath: () -> Void

    var body: some View {
        AboutSettingsSection(title: "Logs") {
            HStack(spacing: 10) {
                Button {
                    onOpenLogs()
                } label: {
                    Label("Open logs in Console", systemImage: "terminal")
                }
                .disabled(isDisabled)
                .accessibilityIdentifier("about-settings-open-logs")

                Button {
                    onCopyLogsPath()
                } label: {
                    Label("Copy logs path", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("about-settings-copy-logs-path")
            }

            Text(logsPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

struct AboutSettingsKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        SettingsKeyValueRow(label: label, value: value, labelWidth: 130)
    }
}

struct AboutSettingsBanner<Actions: View>: View {
    let error: AboutSettingsError
    let tint: Color
    private let actions: Actions

    init(error: AboutSettingsError, tint: Color, @ViewBuilder actions: () -> Actions) {
        self.error = error
        self.tint = tint
        self.actions = actions()
    }

    var body: some View {
        SettingsStatusBanner(title: error.message, systemImage: "exclamationmark.triangle", tint: tint) {
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
    }
}
