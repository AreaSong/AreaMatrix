import SwiftUI

struct DBRepairConfirmView: View {
    @StateObject private var model: DatabaseRepairConfirmModel

    private let onCancel: () -> Void
    private let onRepairSucceeded: () async -> Void
    private let onOpenRepositoryInFinder: () -> Void

    private let willDoItems = [
        "Back up or preserve the current .areamatrix/ metadata state for diagnostics.",
        "Rescan the repository folder.",
        "Rebuild the local metadata index.",
        "Reload Tree / List / Detail after repair succeeds.",
    ]

    private let willNotDoItems = [
        "Move user files.",
        "Rename user files.",
        "Delete user files.",
        "Overwrite an existing README.md.",
        "Upload diagnostics automatically.",
    ]

    init(
        repoPath: String,
        scanSession: ScanSessionSnapshot?,
        mapping: CoreErrorMappingSnapshot?,
        lastOpenedAt: Int64? = nil,
        metadataRepairer: any CoreMetadataRepairing = CoreBridge(),
        startupRecoverer: any CoreStartupRecovering = CoreBridge(),
        diagnosticsCollector: any CoreDiagnosticsCollecting = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        onCancel: @escaping () -> Void,
        onRepairSucceeded: @escaping () async -> Void,
        onOpenRepositoryInFinder: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: DatabaseRepairConfirmModel(
            repoPath: repoPath,
            scanSession: scanSession,
            mapping: mapping,
            lastOpenedAt: lastOpenedAt,
            metadataRepairer: metadataRepairer,
            startupRecoverer: startupRecoverer,
            diagnosticsCollector: diagnosticsCollector,
            errorMapper: errorMapper
        ))
        self.onCancel = onCancel
        self.onRepairSucceeded = onRepairSucceeded
        self.onOpenRepositoryInFinder = onOpenRepositoryInFinder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    repositoryContext
                    startupRecoveryStatus
                    repairPlan
                    diagnosticsStatus
                    repairStatus
                }
                .frame(maxWidth: 720, alignment: .leading)
            }
            footer
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .confirmationDialog("Export diagnostics?", isPresented: diagnosticsConfirmationBinding) {
            Button("Cancel", role: .cancel, action: model.cancelDiagnosticsExport)
            Button("Export diagnostics") {
                Task {
                    await model.collectDiagnostics()
                }
            }
        } message: {
            Text(
                "Diagnostics do not include user file contents, are not uploaded automatically, " +
                    "and paths and usernames are redacted before display."
            )
        }
        .task {
            await model.runStartupRecoveryCheckIfNeeded()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S1-37-db-repair-confirm")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Repair Repository Metadata?", systemImage: "wrench.and.screwdriver")
                .font(.system(size: 34, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("AreaMatrix cannot read the repository metadata database. Your files remain in the repository folder.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Repair only affects .areamatrix/ metadata after you confirm the safety boundary.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var repositoryContext: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repository")
                .font(.headline)
            Text(model.repoPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            if let mapping = model.initialMapping {
                Text("Error: \(mapping.kind.rawValue)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(mapping.userMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Technical Details") {
                    Text(mapping.rawContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.callout)
            }
            Text(lastOpenedLine)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var startupRecoveryStatus: some View {
        StartupRecoveryCheckStatusView(
            state: model.startupRecoveryState,
            onRetry: {
                Task {
                    await model.retryStartupRecovery()
                }
            }
        )
    }

    private var repairPlan: some View {
        VStack(alignment: .leading, spacing: 16) {
            RepairChecklistSection(title: "Will do", systemImage: "arrow.clockwise.circle", items: willDoItems)
            RepairChecklistSection(title: "Will not do", systemImage: "checkmark.shield", items: willNotDoItems)
            Toggle(
                "我理解修复只处理 AreaMatrix 元数据，不会删除我的资料库文件",
                isOn: Binding(
                    get: { model.isMetadataSafetyConfirmed },
                    set: { model.isMetadataSafetyConfirmed = $0 }
                )
            )
            .toggleStyle(.checkbox)
            .disabled(model.repairState.isRunning)
            .accessibilityIdentifier("S1-37-C1-26-confirm-metadata-only")
        }
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch model.diagnosticsState {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            Label("Preparing redacted diagnostics...", systemImage: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .collected(let snapshot):
            VStack(alignment: .leading, spacing: 6) {
                Label("Diagnostics collected", systemImage: "doc.badge.gearshape")
                    .foregroundStyle(.green)
                Text(snapshot.snapshotPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                ForEach(snapshot.warnings.prefix(3), id: \.self) { warning in
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("S1-37-C1-26-diagnostics-collected")
        case .failed(let mapping):
            VStack(alignment: .leading, spacing: 6) {
                Label("Diagnostics could not be created", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(mapping.userMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Full rescan is disabled until diagnostics can be preserved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("S1-37-C1-26-diagnostics-failed")
        }
    }

    @ViewBuilder
    private var repairStatus: some View {
        switch model.repairState {
        case .idle:
            EmptyView()
        case .running(let step):
            RepairProgressView(currentStep: step)
                .accessibilityIdentifier("S1-37-C1-26-repair-progress")
        case .succeeded(let report):
            VStack(alignment: .leading, spacing: 8) {
                Label("Repair completed", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Text(report.summaryText)
                    .font(.callout)
                if let diagnosticsPath = report.diagnosticsSnapshotPath {
                    Text("Diagnostics snapshot: \(diagnosticsPath)")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                if !report.errors.isEmpty {
                    Text("Warnings: \(report.errors.prefix(3).joined(separator: "\n"))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("S1-37-C1-26-repair-succeeded")
        case .failed(let mapping):
            VStack(alignment: .leading, spacing: 8) {
                Label("Repair failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(mapping.userMessage)
                    .font(.callout)
                Text(mapping.suggestedAction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Technical Details") {
                    Text(mapping.rawContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.callout)
            }
            .accessibilityIdentifier("S1-37-C1-26-repair-failed")
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .disabled(model.repairState.isRunning)
            Button("Export diagnostics...", action: model.requestDiagnosticsExport)
                .disabled(!model.canExportDiagnostics)
                .accessibilityIdentifier("S1-37-C1-26-export-diagnostics")
            if model.repairState.failure != nil {
                Button("Open repository in Finder", action: onOpenRepositoryInFinder)
                    .disabled(model.repairState.isRunning)
            }
            Spacer()
            Button(model.primaryButtonTitle) {
                Task {
                    await model.runFullRescan()
                    if model.repairState.isSucceeded {
                        await onRepairSucceeded()
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRunFullRescan)
            .accessibilityIdentifier("S1-37-C1-26-run-full-rescan")
        }
        .frame(maxWidth: 720)
        .padding(.top, 18)
    }

    private var diagnosticsConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                if case .confirmingPrivacy = model.diagnosticsState { return true }
                return false
            },
            set: { isPresented in
                if !isPresented { model.cancelDiagnosticsExport() }
            }
        )
    }

    private var lastOpenedLine: String {
        guard let lastOpenedAt = model.lastOpenedAt else {
            return "Last successful open: Not recorded"
        }

        let date = Date(timeIntervalSince1970: TimeInterval(lastOpenedAt))
        return "Last successful open: \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct StartupRecoveryCheckStatusView: View {
    let state: DatabaseStartupRecoveryState
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .idle, .checking:
            Label("Checking startup recovery state...", systemImage: "arrow.clockwise.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("S1-37-C1-16-startup-recovery-checking")
        case .completed(let report):
            completedContent(report)
                .accessibilityIdentifier("S1-37-C1-16-startup-recovery-completed")
        case .failed(let mapping):
            failedContent(mapping)
                .accessibilityIdentifier("S1-37-C1-16-startup-recovery-failed")
        }
    }

    private func completedContent(_ report: RecoveryReportSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Startup recovery checked", systemImage: "checkmark.circle")
                .font(.headline)
                .foregroundStyle(.green)
            if let report {
                Text(report.startupRecoverySummaryText)
                    .font(.callout)
                ForEach(report.warnings.prefix(3), id: \.self) { warning in
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("No leftover staging files or staging DB rows required recovery.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func failedContent(_ mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Startup recovery failed", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.red)
            Text(mapping.userMessage)
                .font(.callout)
            Text(mapping.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            DisclosureGroup("Technical Details") {
                Text(mapping.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.callout)
            Button("Retry startup recovery", action: onRetry)
                .accessibilityIdentifier("S1-37-C1-16-retry-startup-recovery")
        }
    }
}

private struct RepairChecklistSection: View {
    let title: String
    let systemImage: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "checkmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RepairProgressView: View {
    let currentStep: DatabaseRepairProgressStep

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Repair in progress", systemImage: "arrow.clockwise.circle")
                .font(.headline)
            ForEach(DatabaseRepairProgressStep.allCases, id: \.self) { step in
                HStack(spacing: 8) {
                    if step == currentStep {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                    }
                    Text(step.rawValue)
                        .font(.callout)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
