import SwiftUI

protocol DiagnosticsIncidentManaging: Sendable {
    func markIncident(note: String?) async -> String
    func updateIncident(id: String, status: String) async throws
    func deleteIncident(id: String) async throws
    func incidentSnapshots() async -> [ObservabilityIncidentSnapshot]
}

struct ObservabilityRuntimeIncidentAdapter: DiagnosticsIncidentManaging {
    let runtime: ObservabilityRuntimeAssembly

    func markIncident(note: String?) async -> String {
        await runtime.hub.markIncident(note: note)
    }

    func updateIncident(id: String, status: String) async throws {
        try await runtime.hub.updateIncident(id: id, status: status)
    }

    func deleteIncident(id: String) async throws {
        try await runtime.deleteIncident(id: id)
    }

    func incidentSnapshots() async -> [ObservabilityIncidentSnapshot] {
        await runtime.hub.incidentSnapshots()
    }
}

enum DiagnosticsPackageScope: String, CaseIterable {
    case recentActivity
    case selectedIncident

    var label: String {
        switch self {
        case .recentActivity: L10n.string("observability.package.scope.recent")
        case .selectedIncident: L10n.string("observability.package.scope.incident")
        }
    }
}

enum DiagnosticsPageFeedback: Equatable {
    case success(LocalizedMessage)
    case failure(LocalizedMessage)
}

struct AdvancedSettingsRecoveryToolsSection: View {
    let onOpenRecoveryTools: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Recovery tools"))
                .font(.headline)
            Button {
                onOpenRecoveryTools()
            } label: {
                Label(L10n.string("Open recovery tools..."), systemImage: "arrow.clockwise.circle")
            }
            .accessibilityIdentifier("advanced-settings-startup-recovery-core-open-recovery-tools")
            Text(L10n.string("settings.advanced.startupRecoveryDetail"))
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

            Text(L10n.string("diagnostics.repositoryPrivacyDetail"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AdvancedSettingsObservabilitySection: View {
    let isCollecting: Bool
    let onOpenDiagnostics: () -> Void
    let onCopyDiagnosticSummary: () -> Void

    var body: some View {
        AdvancedSettingsSection(title: L10n.string("settings.advanced.observability.title")) {
            HStack(spacing: 10) {
                Button {
                    onOpenDiagnostics()
                } label: {
                    Label(
                        L10n.string("settings.advanced.openDiagnostics"),
                        systemImage: "waveform.path.ecg"
                    )
                }
                .disabled(isCollecting)
                .accessibilityIdentifier("advanced-settings-open-diagnostics")

                Button {
                    onCopyDiagnosticSummary()
                } label: {
                    Label(L10n.string("Copy diagnostic summary"), systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("advanced-settings-copy-diagnostic-summary")
            }

            Text(L10n.string("settings.advanced.observability.detail"))
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
            Picker(L10n.string("Generated overview output"), selection: selection) {
                ForEach(AdvancedSettingsOverviewOutput.allCases) { output in
                    Text(output.label).tag(output)
                }
            }
            .pickerStyle(.segmented)
            .disabled(writesDisabled)
            .frame(maxWidth: 320)
            .accessibilityIdentifier(AdvancedSettingsAccessibilityID.overviewOutput)

            Text(L10n.string("Generated only writes under .areamatrix/generated/."))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(L10n.string("Root AREAMATRIX.md adds a managed marker block to the repository root file."))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(L10n.string("README.md is never managed."))
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
            Toggle(L10n.string("Allow replace during import"), isOn: isOn)
                .disabled(writesDisabled)
                .accessibilityIdentifier("advanced-settings-repository-config-allow-replace")

            Text(L10n.string("settings.advanced.allowReplaceDetail"))
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
            Text(L10n.string("Enable root AREAMATRIX.md?"))
                .font(.title2.weight(.semibold))
            Text(L10n.string("settings.advanced.rootOverviewEnableDetail"))
                .fixedSize(horizontal: false, vertical: true)
            Text(status.confirmationDetail)
                .foregroundStyle(status.canEnableRootOverview ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Enable root file"), action: onEnable)
                    .buttonStyle(.borderedProminent)
                    .disabled(!status.canEnableRootOverview)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
