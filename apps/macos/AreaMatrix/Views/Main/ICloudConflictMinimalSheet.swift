import SwiftUI

extension ICloudConflictVersionSnapshot {
    static func originalCandidate(repoPath: String, file: FileEntrySnapshot?) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot(
            role: .original,
            path: file.flatMap { originalCandidatePath(repoPath: repoPath, file: $0) },
            modifiedAt: file?.updatedAt,
            sizeBytes: nil
        )
    }

    static func conflictedCandidate(repoPath: String, file: FileEntrySnapshot?) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot(
            role: .conflictedCopy,
            path: file.map { absolutePath(repoPath: repoPath, relativePath: $0.path) },
            modifiedAt: file?.updatedAt,
            sizeBytes: file?.sizeBytes
        )
    }

    private static func originalCandidatePath(repoPath: String, file: FileEntrySnapshot) -> String {
        let relativePath = file.path.replacingOccurrences(of: " (Conflicted Copy)", with: "")
        return absolutePath(repoPath: repoPath, relativePath: relativePath)
    }

    private static func absolutePath(repoPath: String, relativePath: String) -> String {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(relativePath)
            .path
    }
}

struct ICloudConflictMinimalSheet: View {
    let resolutionState: ICloudConflictResolutionState
    let resolutionCapability: ICloudConflictResolutionCapability
    let isTrashAvailable: Bool
    let onCancel: () -> Void
    let onApply: (
        ICloudConflictResolutionStrategy,
        ICloudConflictResolveReportSnapshot?,
        CoreErrorMappingSnapshot?
    ) -> Void
    let onCollectDiagnostics: () -> Void
    @StateObject private var model: ICloudConflictMinimalModel
    @State private var selectedStrategy: ICloudConflictResolutionStrategy = .keepBoth
    @State private var didConfirmSingleVersion = false
    @State private var localResolutionState: ICloudConflictResolutionState

    init(
        model: ICloudConflictMinimalModel,
        resolutionState: ICloudConflictResolutionState = .idle,
        resolutionCapability: ICloudConflictResolutionCapability,
        isTrashAvailable: Bool,
        onCancel: @escaping () -> Void,
        onApply: @escaping (
            ICloudConflictResolutionStrategy,
            ICloudConflictResolveReportSnapshot?,
            CoreErrorMappingSnapshot?
        ) -> Void,
        onCollectDiagnostics: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: model)
        _localResolutionState = State(initialValue: resolutionState)
        self.resolutionState = resolutionState
        self.resolutionCapability = resolutionCapability
        self.isTrashAvailable = isTrashAvailable
        self.onCancel = onCancel
        self.onApply = onApply
        self.onCollectDiagnostics = onCollectDiagnostics
    }

    var body: some View {
        MainFileActionSheetContainer(title: "解决 iCloud 冲突", pageID: "S2-20") {
            VStack(alignment: .leading, spacing: 12) {
                Text("This is an iCloud conflicted copy. AreaMatrix will not delete any version automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                previewStatus
                versionList
                validationStatus
                resolutionCapabilityStatus
                strategyOptions
                singleVersionConfirmation
                resolutionStatus
                actionButtons
            }
            .task {
                await model.validateRepositoryPath()
                await model.loadPreviewIfNeeded()
            }
        }
        .accessibilityIdentifier("S2-20-C2-16-icloud-conflict-visual")
    }

    private var versionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(versionListTitle)
                .font(.headline)
            ForEach(model.previewVersions) { version in
                versionRow(version)
            }
        }
    }

    private func versionRow(_ version: ICloudConflictVersionMetadataSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            metadataRow(version.role.displayName, version.displayName)
            metadataRow("Path", version.path.isEmpty ? "Unknown path" : version.path)
            metadataRow("Modified", modifiedLabel(for: version.modifiedAt))
            metadataRow("Size", sizeLabel(for: version.sizeBytes))
            metadataRow("Hash", version.hashDisplay)
            metadataRow("Preview", version.previewDisplay)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var previewStatus: some View {
        switch model.previewState {
        case .notLoaded, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading conflict details...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("S2-20-C2-16-loading")
        case let .loaded(preview):
            VStack(alignment: .leading, spacing: 5) {
                statusLabel("Conflict details loaded", systemImage: "checkmark.circle", color: .green)
                if let blockedReason = preview.blockedReason, !blockedReason.isEmpty {
                    statusLabel(blockedReason, systemImage: "exclamationmark.triangle", color: .orange)
                }
                if !preview.metadataComplete {
                    statusLabel("Metadata is incomplete; destructive resolution is disabled.", systemImage: "info.circle", color: .orange)
                }
                if !preview.trashAvailable {
                    statusLabel("Trash is unavailable; Keep left/right are disabled.", systemImage: "trash.slash", color: .orange)
                }
            }
            .accessibilityIdentifier("S2-20-C2-16-preview-loaded")
        case .empty:
            VStack(alignment: .leading, spacing: 8) {
                statusLabel("Conflict no longer exists", systemImage: "exclamationmark.triangle", color: .orange)
                Button("Refresh") {
                    Task { await model.loadPreview() }
                }
            }
            .accessibilityIdentifier("S2-20-C2-16-empty")
        case let .failed(mapping):
            mappedPreviewError(mapping)
        }
    }

    private func mappedPreviewError(_ mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLabel("Conflict detail failed: \(mapping.kind.rawValue)", systemImage: "exclamationmark.triangle", color: .red)
            Text(mapping.userMessage)
                .font(.caption)
            Text(mapping.suggestedAction)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Severity: \(mapping.severity.rawValue); Recoverability: \(mapping.recoverability.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !mapping.rawContext.isEmpty {
                Text(mapping.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Button("Retry") {
                Task { await model.loadPreview() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S2-20-C2-16-preview-error")
    }

    @ViewBuilder
    private var validationStatus: some View {
        switch model.repositoryValidationState {
        case .notChecked:
            statusLabel("Repository path not checked", systemImage: "clock", color: .secondary)
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking repository path...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case let .ready(validation, warnings):
            VStack(alignment: .leading, spacing: 5) {
                statusLabel("Repository path validated", systemImage: "checkmark.circle", color: .green)
                metadataRow("Repository", validation.repoPath)
                ForEach(warnings, id: \.self) { warning in
                    statusLabel(warning, systemImage: "icloud", color: .orange)
                }
            }
        case let .blocked(validation, reasons):
            VStack(alignment: .leading, spacing: 6) {
                statusLabel("Repository path blocks Apply", systemImage: "exclamationmark.triangle", color: .orange)
                metadataRow("Repository", validation.repoPath)
                ForEach(reasons, id: \.self) { reason in
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Retry repository check") {
                    Task { await model.validateRepositoryPath() }
                }
            }
        case let .failed(mapping):
            mappedErrorStatus(mapping)
        }
    }

    private func mappedErrorStatus(_ mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLabel(
                "Repository check failed: \(mapping.kind.rawValue)",
                systemImage: "exclamationmark.triangle",
                color: .red
            )
            Text(mapping.userMessage)
                .font(.caption)
            Text(mapping.suggestedAction)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Severity: \(mapping.severity.rawValue); Recoverability: \(mapping.recoverability.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !mapping.rawContext.isEmpty {
                Text(mapping.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Button("Retry repository check") {
                Task { await model.validateRepositoryPath() }
            }
            .accessibilityIdentifier("S1-25-C1-21-retry-repository-check")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S1-25-C1-21-error-mapping")
    }

    @ViewBuilder
    private var resolutionCapabilityStatus: some View {
        if let blocker = resolutionCapability.blocker {
            VStack(alignment: .leading, spacing: 6) {
                statusLabel(blocker.title, systemImage: "exclamationmark.triangle", color: .orange)
                Text(blocker.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(blocker.suggestedAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(blocker.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .accessibilityIdentifier("S1-25-core-resolution-blocked")
        }
    }

    private var strategyOptions: some View {
        Picker("Resolution", selection: $selectedStrategy) {
            ForEach(ICloudConflictResolutionStrategy.allCases) { strategy in
                Text(strategy.title).tag(strategy)
            }
        }
        .pickerStyle(.radioGroup)
        .disabled(currentResolutionState.isApplying || model.previewState.isLoading)
        .onChange(of: selectedStrategy) { _, newValue in
            if !newValue.requiresSecondConfirmation { didConfirmSingleVersion = false }
        }
    }

    @ViewBuilder
    private var singleVersionConfirmation: some View {
        if selectedStrategy.requiresSecondConfirmation {
            VStack(alignment: .leading, spacing: 8) {
                Text("Move the other version to Trash?")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("AreaMatrix will move the other version to system Trash and keep a change-log record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let disabledReason = selectedOption?.disabledReason, !disabledReason.isEmpty {
                    statusLabel(disabledReason, systemImage: "exclamationmark.triangle", color: .orange)
                }
                if !isTrashAvailable || !model.canResolveDestructive {
                    statusLabel(
                        "Single-version resolution requires system Trash",
                        systemImage: "trash.slash",
                        color: .orange
                    )
                } else {
                    Toggle(
                        "我理解另一份冲突副本会被移到系统废纸篓",
                        isOn: $didConfirmSingleVersion
                    )
                    .disabled(currentResolutionState.isApplying)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(
                    [
                        "This action keeps both versions and requires Core support",
                        "to clear conflict state and write change_log."
                    ].joined(separator: " ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if let disabledReason = selectedOption?.disabledReason, !disabledReason.isEmpty {
                    statusLabel(disabledReason, systemImage: "info.circle", color: .orange)
                }
                if !isTrashAvailable {
                    statusLabel(
                        "Single-version resolution requires system Trash",
                        systemImage: "trash.slash",
                        color: .orange
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var resolutionStatus: some View {
        if case let .applying(_, strategy) = currentResolutionState {
            statusLabel(strategy.runningTitle, systemImage: "arrow.triangle.2.circlepath", color: .secondary)
        } else if let failure = currentResolutionState.failure(fileID: resolutionFileID) {
            applyFailureView(failure)
        }
    }

    private func applyFailureView(_ failure: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            statusLabel("Apply failed: \(failure.kind.rawValue)", systemImage: "exclamationmark.triangle", color: .red)
            Text(failure.userMessage)
                .font(.caption)
            Text(failure.suggestedAction)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(failure.rawContext)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            HStack {
                Button("Retry") {
                    Task { await submit() }
                }
                    .disabled(!canApplySelectedStrategy)
                Button("Cancel", action: onCancel)
                Button("Collect Diagnostics...", action: onCollectDiagnostics)
            }
        }
        .accessibilityIdentifier("S1-25-C1-21-apply-failure")
    }

    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(currentResolutionState.isApplying)
            Button(primaryActionTitle, role: selectedStrategy.requiresSecondConfirmation ? .destructive : nil) {
                Task { await submit() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canApplySelectedStrategy)
        }
    }

    private var canApplySelectedStrategy: Bool {
        resolutionCapability.canResolve
            && !currentResolutionState.isApplying
            && model.canApply(
                strategy: selectedStrategy,
                isTrashAvailable: isTrashAvailable,
                didConfirmSingleVersion: didConfirmSingleVersion
            )
    }

    private var primaryActionTitle: String {
        currentResolutionState.primaryTitle(fileID: resolutionFileID, selectedStrategy: selectedStrategy)
    }

    private var resolutionFileID: Int64 {
        currentResolutionState.fileID ?? -1
    }

    private var selectedOption: ICloudConflictResolutionOptionSnapshot? {
        model.option(for: selectedStrategy)
    }

    private var versionListTitle: String {
        let count = model.previewVersions.count
        return count > 2 ? "\(count) versions found" : "Versions"
    }

    private var currentResolutionState: ICloudConflictResolutionState {
        resolutionState == .idle ? localResolutionState : resolutionState
    }

    @MainActor
    private func submit() async {
        guard canApplySelectedStrategy else { return }

        localResolutionState = .applying(fileID: -1, strategy: selectedStrategy)
        switch await model.resolveConflict(strategy: selectedStrategy) {
        case let .resolved(result):
            localResolutionState = .idle
            onApply(selectedStrategy, result.report, nil)
        case let .failed(mapping):
            localResolutionState = .failed(fileID: -1, strategy: selectedStrategy, mapping)
            onApply(selectedStrategy, nil, mapping)
        }
    }

    private func statusLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func modifiedLabel(for timestamp: Int64?) -> String {
        guard let timestamp else { return "Unknown" }
        return Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .abbreviated, time: .shortened)
    }

    private func sizeLabel(for bytes: Int64?) -> String {
        guard let bytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

}

private extension ICloudConflictResolutionState {
    var fileID: Int64? {
        switch self {
        case .idle:
            nil
        case let .applying(fileID, _), let .failed(fileID, _, _):
            fileID
        }
    }
}
