import SwiftUI

struct RepositorySettingsPathSection: View {
    let summary: RepositorySettingsSummary
    let onRevealInFinder: () -> Void
    let onCopyPath: () -> Void
    let onChangeRepository: () -> Void

    var body: some View {
        RepositorySettingsSection(title: "路径") {
            RepositorySettingsKeyValueRow(label: "Repository name", value: summary.repositoryName)
            RepositorySettingsKeyValueRow(label: "Location", value: summary.location)
            RepositorySettingsKeyValueRow(label: "Type", value: summary.locationType)
            RepositorySettingsKeyValueRow(label: "Core version", value: summary.coreVersion)
            RepositorySettingsKeyValueRow(label: "Metadata", value: summary.metadataStatus)
            repositoryPathActions
        }
    }

    private var repositoryPathActions: some View {
        HStack(spacing: 10) {
            Button("Reveal in Finder", action: onRevealInFinder)
                .accessibilityIdentifier("repository-settings-reveal-repository")

            Button("Copy path", action: onCopyPath)
                .accessibilityIdentifier("repository-settings-copy-repository-path")

            Button("Change repository...", action: onChangeRepository)
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
        RepositorySettingsSection(title: "健康") {
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

struct RepositorySettingsSafeActionsSection: View {
    let diagnosticsButtonTitle: String
    let isDiagnosticsDisabled: Bool
    let diagnosticsDisabledReason: String?
    let onReconnectRepository: () -> Void
    let onChooseAnotherFolder: () -> Void
    let onExportDiagnostics: () -> Void

    var body: some View {
        RepositorySettingsSection(title: "Actions") {
            Button("Reconnect Repository", action: onReconnectRepository)
                .accessibilityIdentifier("repository-settings-reconnect-repository")

            Button("Choose Another Folder", action: onChooseAnotherFolder)
                .accessibilityIdentifier("repository-settings-choose-another-folder")

            Button(diagnosticsButtonTitle, action: onExportDiagnostics)
                .disabled(isDiagnosticsDisabled)
                .help(diagnosticsDisabledReason ?? "Diagnostics export is available.")
                .accessibilityIdentifier("repository-settings-export-diagnostics")

            Text("Diagnostics do not include your original file contents and are not uploaded automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
