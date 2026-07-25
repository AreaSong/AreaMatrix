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
import OSLog
import UniformTypeIdentifiers

public enum MemoryLogLevel {
    case debug, info, warn, error
}

public struct LiveLogEntry: Identifiable {
    public let id = UUID()
    public let date: Date
    public let level: MemoryLogLevel
    public let category: String
    public let message: String
}

@MainActor
public final class MemoryLogStore: ObservableObject {
    public static let shared = MemoryLogStore()
    @Published public private(set) var logs: [LiveLogEntry] = []
    
    public func append(level: MemoryLogLevel, category: String, message: String) {
        let entry = LiveLogEntry(date: Date(), level: level, category: category, message: message)
        if logs.count > 1000 {
            logs.removeLast()
        }
        logs.insert(entry, at: 0)
    }
    
    public func clear() {
        logs.removeAll()
    }
}

enum LogViewMode: String, CaseIterable {
    case card = "Card"
    case terminal = "Terminal"
}

enum LogCategoryFilter: String, CaseIterable {
    case all = "All"
    case core = "Core"
    case ui = "UI"
    case sync = "Sync"
}

struct LiveLogsViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MemoryLogStore.shared
    @State private var viewMode: LogViewMode = .card
    @State private var categoryFilter: LogCategoryFilter = .all
    
    var filteredLogs: [LiveLogEntry] {
        if categoryFilter == .all { return store.logs }
        return store.logs.filter { $0.category.lowercased() == categoryFilter.rawValue.lowercased() }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.logs.isEmpty {
                Text("Waiting for incoming logs...").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if viewMode == .terminal {
                    terminalView
                } else {
                    cardView
                }
            }
            Divider()
            footer
        }
        .frame(width: 800, height: 600)
    }
    
    private var header: some View {
        HStack(spacing: 16) {
            Text(L10n.string("Activity Monitor"))
                .font(.headline)
            
            Picker("", selection: $viewMode) {
                ForEach(LogViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 150)
            
            Picker("Category:", selection: $categoryFilter) {
                ForEach(LogCategoryFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.frame(width: 150)
            
            Spacer()
            
            Button(action: { store.clear() }) {
                Label("Clear", systemImage: "trash")
            }
            Button(action: exportSanitized) {
                Label("Export Sanitized", systemImage: "lock.shield")
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var terminalView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(filteredLogs) { log in
                    Text("[\(log.date.formatted(date: .omitted, time: .standard))] [\(log.category)] \(log.message)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.black)
    }
    
    private var cardView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredLogs) { log in
                    HStack(alignment: .top) {
                        icon(for: log.level)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(log.category).font(.caption).bold().foregroundStyle(.secondary)
                                Spacer()
                                Text(log.date.formatted()).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text(log.message).font(.callout).textSelection(.enabled)
                        }
                    }
                    .padding(12)
                    .background(Material.ultraThin, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func icon(for level: MemoryLogLevel) -> some View {
        switch level {
        case .error: return Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case .info: return Image(systemName: "info.circle.fill").foregroundColor(.blue)
        case .warn: return Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
        case .debug: return Image(systemName: "ladybug.fill").foregroundColor(.orange)
        }
    }
    
    private var footer: some View {
        HStack {
            Text("\(filteredLogs.count) events found").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func exportSanitized() {
        let content = filteredLogs.map { "[\($0.date)] [\($0.category)] \($0.message)" }.joined(separator: "\n")
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let sanitized = content.replacingOccurrences(of: homeDir, with: "[REDACTED_HOME]")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sanitized, forType: .string)
    }
}

