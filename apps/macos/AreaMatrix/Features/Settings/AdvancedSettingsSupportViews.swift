import SwiftUI

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

struct AdvancedSettingsLogsSection: View {
    let isCollecting: Bool
    let onOpenLogsFolder: () -> Void
    let onShowLogs: () -> Void
    let onCopyDiagnosticSummary: () -> Void

    var body: some View {
        AdvancedSettingsSection(title: L10n.string("Logs")) {
            HStack(spacing: 10) {
                Button {
                    onOpenLogsFolder()
                } label: {
                    Label(L10n.string("Open logs folder"), systemImage: "folder")
                }
                .disabled(isCollecting)
                .accessibilityIdentifier("advanced-settings-open-logs-folder")

                Button {
                    onShowLogs()
                } label: {
                    Label(L10n.string("View Logs..."), systemImage: "text.alignleft")
                }
                .disabled(isCollecting)
                .accessibilityIdentifier("advanced-settings-show-logs")

                Button {
                    onCopyDiagnosticSummary()
                } label: {
                    Label(L10n.string("Copy diagnostic summary"), systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("advanced-settings-copy-diagnostic-summary")
            }

            Text(L10n.string("Diagnostics do not include your original file contents."))
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
import SwiftUI

struct LiveLogsViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent: String = ""
    @State private var isLoading: Bool = true
    @State private var resolvedPath: String = ""
    
    private let logsPath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".areamatrix/logs/core.log")
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string("Core Action Logs"))
                    .font(.headline)
                Spacer()
                Button {
                    loadLogs()
                } label: {
                    Label(L10n.string("Refresh"), systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(logContent)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
            }
            
            Divider()
            
            HStack {
                Text(resolvedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.string("Close")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 800, height: 600)
        .onAppear {
            loadLogs()
        }
    }
    
    private func loadLogs() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var content: String = ""
            var resolvedPath: String = self.logsPath.path
            
            let logsDir = self.logsPath.deletingLastPathComponent()
            do {
                let files = try FileManager.default.contentsOfDirectory(atPath: logsDir.path)
                let coreLogFiles = files.filter { $0.hasPrefix("core.log") }.sorted(by: >)
                
                if let latestLog = coreLogFiles.first {
                    let latestPath = logsDir.appendingPathComponent(latestLog)
                    resolvedPath = latestPath.path
                    content = try String(contentsOf: latestPath, encoding: .utf8)
                } else {
                    content = "No logs found in \(logsDir.path)"
                }
            } catch {
                content = "Failed to read logs directory: \(error.localizedDescription)"
            }
            
            DispatchQueue.main.async {
                self.logContent = content
                self.resolvedPath = resolvedPath
                self.isLoading = false
            }
        }
    }
}
