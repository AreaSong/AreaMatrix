import SwiftUI

struct RepositorySettingsPathSection: View {
    let summary: RepositorySettingsSummary
    let onRevealInFinder: () -> Void
    let onCopyPath: () -> Void
    let onChangeRepository: () -> Void

    var body: some View {
        RepositorySettingsSection(title: L10n.string("settings.repository.section.path")) {
            RepositorySettingsKeyValueRow(label: L10n.string("Repository name"), value: summary.repositoryName)
            RepositorySettingsKeyValueRow(label: L10n.string("Location"), value: summary.location)
            RepositorySettingsKeyValueRow(label: L10n.string("Type"), value: summary.locationType)
            RepositorySettingsKeyValueRow(label: L10n.string("Core version"), value: summary.coreVersion)
            RepositorySettingsKeyValueRow(label: L10n.string("Metadata"), value: summary.metadataStatus)
            repositoryPathActions
        }
    }

    private var repositoryPathActions: some View {
        HStack(spacing: 10) {
            Button(L10n.string("Reveal in Finder"), action: onRevealInFinder)
                .accessibilityIdentifier("repository-settings-reveal-repository")

            Button(L10n.string("Copy path"), action: onCopyPath)
                .accessibilityIdentifier("repository-settings-copy-repository-path")

            Button(L10n.string("Change repository..."), action: onChangeRepository)
                .accessibilityIdentifier("repository-settings-change-repository")
        }
    }
}

struct RepositorySettingsHealthSection: View {
    let summary: RepositorySettingsHealthSummary?

    private static let indexedCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    var body: some View {
        RepositorySettingsSection(title: L10n.string("settings.repository.section.health")) {
            VStack(alignment: .leading, spacing: 10) {
                RepositorySettingsKeyValueRow(
                    label: L10n.string("Database"),
                    value: summary?.databaseStatus.label ?? "—"
                )
                RepositorySettingsKeyValueRow(label: L10n.string("Schema version"), value: schemaVersionValue)
                RepositorySettingsKeyValueRow(label: L10n.string("Files indexed"), value: filesIndexedValue)
                RepositorySettingsKeyValueRow(label: L10n.string("Last opened"), value: lastOpenedValue)
                RepositorySettingsKeyValueRow(label: L10n.string("Last scan"), value: lastScanValue)
                RepositorySettingsKeyValueRow(
                    label: L10n.string("Watcher"),
                    value: summary?.watcherStatus.label ?? L10n.string("Paused")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var schemaVersionValue: String {
        guard let schemaVersion = summary?.schemaVersion else {
            return L10n.string("Unknown")
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
            return L10n.string("Not available")
        }

        return Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(date: .abbreviated, time: .shortened)
    }

    private var lastOpenedValue: String {
        guard let timestamp = summary?.lastOpenedAt else {
            return L10n.string("Unknown")
        }

        return Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(date: .abbreviated, time: .shortened)
    }
}

struct RepositorySettingsSafeActionsSection: View {
    let diagnosticsButtonTitle: String
    let isDiagnosticsDisabled: Bool
    let diagnosticsDisabledReason: String?
    let onReconnectRepository: () -> Void
    let onChooseAnotherFolder: () -> Void
    let onExportDiagnostics: () -> Void

    var body: some View {
        RepositorySettingsSection(title: L10n.string("Actions")) {
            Button(L10n.string("Reconnect Repository"), action: onReconnectRepository)
                .accessibilityIdentifier("repository-settings-reconnect-repository")

            Button(L10n.string("Choose Another Folder"), action: onChooseAnotherFolder)
                .accessibilityIdentifier("repository-settings-choose-another-folder")

            Button(diagnosticsButtonTitle, action: onExportDiagnostics)
                .disabled(isDiagnosticsDisabled)
                .help(diagnosticsDisabledReason ?? L10n.string("Diagnostics export is available."))
                .accessibilityIdentifier("repository-settings-export-diagnostics")

            Text(L10n
                .string("Diagnostics do not include your original file contents and are not uploaded automatically."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
