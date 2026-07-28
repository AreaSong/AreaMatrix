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
                    Text(L10n.string("AreaMatrix"))
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
                SettingsHeaderProgressIndicator(label: L10n.string("Loading version information"))
            } else {
                Button {
                    onRetryVersionCheck()
                } label: {
                    Label(L10n.string("Retry version check"), systemImage: "arrow.clockwise")
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
        AboutSettingsSection(title: L10n.string("Versions")) {
            AboutSettingsKeyValueRow(label: L10n.string("App version"), value: versionInfo.appVersion)
            AboutSettingsKeyValueRow(label: L10n.string("Core version"), value: versionInfo.coreVersion)
            AboutSettingsKeyValueRow(label: L10n.string("Schema version"), value: versionInfo.schemaVersion)
            Button {
                onCopyVersions()
            } label: {
                Label(L10n.string("Copy versions"), systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("about-settings-copy-versions")
        }
    }
}

struct AboutSettingsLicenseSection: View {
    var body: some View {
        AboutSettingsSection(title: L10n.string("License")) {
            Text(L10n.string("PolyForm Noncommercial"))
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
        AboutSettingsSection(title: L10n.string("Links")) {
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
                            Label(L10n.string("Copy URL"), systemImage: "doc.on.doc")
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
    let onOpenDiagnostics: () -> Void

    var body: some View {
        AboutSettingsSection(title: L10n.string("settings.advanced.observability.title")) {
            Button {
                onOpenDiagnostics()
            } label: {
                Label(L10n.string("settings.advanced.openDiagnostics"), systemImage: "waveform.path.ecg")
            }
            .accessibilityIdentifier("about-settings-open-diagnostics")

            Text(L10n.string("settings.advanced.observability.detail"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
    @EnvironmentObject private var localizer: AppLocalizer
    let error: AboutSettingsError
    let tint: Color
    private let actions: Actions

    init(error: AboutSettingsError, tint: Color, @ViewBuilder actions: () -> Actions) {
        self.error = error
        self.tint = tint
        self.actions = actions()
    }

    var body: some View {
        SettingsStatusBanner(
            title: localizer.resolve(error.message),
            systemImage: "exclamationmark.triangle",
            tint: tint
        ) {
            Text(localizer.resolve(error.recovery))
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
