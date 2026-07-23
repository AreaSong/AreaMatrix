import SwiftUI

struct AdvancedSettingsRecoveryToolsSection: View {
    let onOpenRecoveryTools: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recovery tools")
                .font(.headline)
            Button {
                onOpenRecoveryTools()
            } label: {
                Label("Open recovery tools...", systemImage: "arrow.clockwise.circle")
            }
            .accessibilityIdentifier("advanced-settings-startup-recovery-core-open-recovery-tools")
            Text(
                "Startup cleanup and staging recovery stay in the dedicated recovery flow " +
                    "with confirmation before metadata actions."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AdvancedSettingsDiagnosticsSection: View {
    let versionInfo: AdvancedSettingsVersionInfo
    let buttonTitle: String
    let isCollecting: Bool
    let onExportDiagnostics: () -> Void

    var body: some View {
        AdvancedSettingsSection(title: L10n.string("Diagnostics")) {
            AdvancedSettingsKeyValueRow(label: L10n.string("App version"), value: versionInfo.appVersion)
            AdvancedSettingsKeyValueRow(label: L10n.string("Core version"), value: versionInfo.coreVersion)
            AdvancedSettingsKeyValueRow(
                label: L10n.string("Repo schema version"),
                value: versionInfo.repoSchemaVersionLabel
            )

            Button {
                onExportDiagnostics()
            } label: {
                Label(buttonTitle, systemImage: "doc.badge.gearshape")
            }
            .disabled(isCollecting)
            .accessibilityIdentifier("advanced-settings-export-diagnostics")

            Text(
                "Repository diagnostics copy AreaMatrix metadata and may include paths, file names, tags, " +
                    "notes, and other sensitive metadata. Original file contents are not copied, and " +
                    "diagnostics are not uploaded automatically. Review the snapshot before sharing."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AdvancedSettingsLogsSection: View {
    let isCollecting: Bool
    let onOpenLogsFolder: () -> Void
    let onCopyDiagnosticSummary: () -> Void

    var body: some View {
        AdvancedSettingsSection(title: L10n.string("Logs")) {
            HStack(spacing: 10) {
                Button {
                    onOpenLogsFolder()
                } label: {
                    Label("Open logs folder", systemImage: "folder")
                }
                .disabled(isCollecting)
                .accessibilityIdentifier("advanced-settings-open-logs-folder")

                Button {
                    onCopyDiagnosticSummary()
                } label: {
                    Label("Copy diagnostic summary", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("advanced-settings-copy-diagnostic-summary")
            }

            Text("Diagnostics do not include your original file contents.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct AdvancedSettingsOverviewOutputSection: View {
    let selection: Binding<AdvancedSettingsOverviewOutput>
    let writesDisabled: Bool

    var body: some View {
        AdvancedSettingsSection(title: L10n.string("Generated overview output")) {
            Picker("Generated overview output", selection: selection) {
                ForEach(AdvancedSettingsOverviewOutput.allCases) { output in
                    Text(output.label).tag(output)
                }
            }
            .pickerStyle(.segmented)
            .disabled(writesDisabled)
            .frame(maxWidth: 320)
            .accessibilityIdentifier(AdvancedSettingsAccessibilityID.overviewOutput)

            Text("Generated only writes under .areamatrix/generated/.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Root AREAMATRIX.md adds a managed marker block to the repository root file.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("README.md is never managed.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct AdvancedSettingsAllowReplaceSection: View {
    let isOn: Binding<Bool>
    let writesDisabled: Bool

    var body: some View {
        AdvancedSettingsSection(title: L10n.string("Dangerous import option")) {
            Toggle("Allow replace during import", isOn: isOn)
                .disabled(writesDisabled)
                .accessibilityIdentifier("advanced-settings-repository-config-allow-replace")

            Text(
                "When enabled, ImportSheet may show Replace for duplicate or name conflicts. " +
                    "Replace still requires Trash and a second confirmation."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AdvancedSettingsKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        SettingsKeyValueRow(label: label, value: value, labelWidth: 150)
    }
}

struct AdvancedSettingsInlineBanner: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let error: AdvancedSettingsError
    let tint: Color
    var body: some View {
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

struct AdvancedRootOverviewConfirmationSheet: View {
    let status: RootOverviewFileStatus
    let onCancel: () -> Void
    let onEnable: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enable root AREAMATRIX.md?")
                .font(.title2.weight(.semibold))
            Text(
                "AreaMatrix may create or update AREAMATRIX.md at the repository root " +
                    "on the next overview regeneration. " +
                    "Existing content outside the managed marker block is preserved. README.md is never modified."
            )
            .fixedSize(horizontal: false, vertical: true)
            Text(status.confirmationDetail)
                .foregroundStyle(status.canEnableRootOverview ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Enable root file", action: onEnable)
                    .buttonStyle(.borderedProminent)
                    .disabled(!status.canEnableRootOverview)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
