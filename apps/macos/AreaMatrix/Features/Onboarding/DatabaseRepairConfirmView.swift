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
        "Reload Tree / List / Detail after repair succeeds."
    ]

    private let willNotDoItems = [
        "Move user files.",
        "Rename user files.",
        "Delete user files.",
        "Overwrite an existing README.md.",
        "Upload diagnostics automatically."
    ]

    init(
        repoPath: String,
        scanSession: ScanSessionSnapshot?,
        mapping: CoreErrorMappingSnapshot?,
        lastOpenedAt: Int64? = nil,
        metadataRepairer: any CoreMetadataRepairing = CoreBridge(),
        startupRecoverer: any CoreStartupRecovering = CoreBridge(),
        repositoryWriteCoordinator: RepositoryWriteCoordinator = AppCoreServices.repositoryWriteCoordinator,
        diagnosticsCollector: any CoreDiagnosticsCollecting = AppCoreServices.diagnosticsCollector,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
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
            repositoryWriteCoordinator: repositoryWriteCoordinator,
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
                "Repository diagnostics copy AreaMatrix metadata and may include paths, file names, tags, " +
                    "notes, and other sensitive metadata. Original file contents are not copied, and " +
                    "diagnostics are not uploaded automatically. Review the snapshot before sharing."
            )
        }
        .task {
            await model.runStartupRecoveryCheckIfNeeded()
        }
        .onDisappear(perform: model.cancelDiagnosticsExport)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("database-repair-db-repair-confirm")
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
            AreaMatrixPathBox(
                path: model.repoPath,
                style: .plain,
                lineLimit: 3,
                alignment: .leading
            )
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
            .accessibilityIdentifier("database-repair-metadata-repair-confirm-metadata-only")
        }
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch model.diagnosticsState {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            Label("Preparing repository diagnostics...", systemImage: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .collected(snapshot):
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
            .accessibilityIdentifier("database-repair-metadata-repair-diagnostics-collected")
        case let .failed(mapping):
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
            .accessibilityIdentifier("database-repair-metadata-repair-diagnostics-failed")
        }
    }

    @ViewBuilder
    private var repairStatus: some View {
        switch model.repairState {
        case .idle:
            EmptyView()
        case let .running(step):
            RepairProgressView(currentStep: step)
                .accessibilityIdentifier("database-repair-metadata-repair-repair-progress")
        case let .succeeded(report):
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
            .accessibilityIdentifier("database-repair-metadata-repair-repair-succeeded")
        case let .failed(mapping):
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
            .accessibilityIdentifier("database-repair-metadata-repair-repair-failed")
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .disabled(model.repairState.isRunning)
            Button("Export diagnostics...", action: model.requestDiagnosticsExport)
                .disabled(!model.canExportDiagnostics)
                .accessibilityIdentifier("database-repair-metadata-repair-export-diagnostics")
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
            .accessibilityIdentifier("database-repair-metadata-repair-run-full-rescan")
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
