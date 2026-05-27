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
    let onApply: (ICloudConflictApplyResult) -> Void
    let onCollectDiagnostics: () -> Void
    @StateObject var model: ICloudConflictMinimalModel
    @State var selectedStrategy: ICloudConflictResolutionStrategy = .keepBoth
    @State var didConfirmSingleVersion = false
    @State private var localResolutionState: ICloudConflictResolutionState

    init(
        model: ICloudConflictMinimalModel,
        resolutionState: ICloudConflictResolutionState = .idle,
        resolutionCapability: ICloudConflictResolutionCapability,
        isTrashAvailable: Bool,
        onCancel: @escaping () -> Void,
        onApply: @escaping (ICloudConflictApplyResult) -> Void,
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

    var actionButtons: some View {
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

    var canApplySelectedStrategy: Bool {
        resolutionCapability.canResolve
            && !currentResolutionState.isApplying
            && model.canApply(
                strategy: selectedStrategy,
                isTrashAvailable: isTrashAvailable,
                didConfirmSingleVersion: didConfirmSingleVersion
            )
    }

    var primaryActionTitle: String {
        currentResolutionState.primaryTitle(fileID: resolutionFileID, selectedStrategy: selectedStrategy)
    }

    var resolutionFileID: Int64 {
        currentResolutionState.fileID ?? -1
    }

    var selectedOption: ICloudConflictResolutionOptionSnapshot? {
        model.option(for: selectedStrategy)
    }

    var versionListTitle: String {
        let count = model.previewVersions.count
        return count > 2 ? "\(count) versions found" : "Versions"
    }

    var currentResolutionState: ICloudConflictResolutionState {
        resolutionState == .idle ? localResolutionState : resolutionState
    }

    @MainActor
    private func submit() async {
        guard canApplySelectedStrategy else { return }

        localResolutionState = .applying(fileID: -1, strategy: selectedStrategy)
        switch await model.resolveConflict(strategy: selectedStrategy) {
        case let .resolved(result):
            localResolutionState = .idle
            onApply(ICloudConflictApplyResult(strategy: selectedStrategy, report: result.report, failure: nil))
        case let .failed(mapping):
            localResolutionState = .failed(fileID: -1, strategy: selectedStrategy, mapping)
            onApply(ICloudConflictApplyResult(strategy: selectedStrategy, report: nil, failure: mapping))
        }
    }

    func statusLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
    }

    func modifiedLabel(for timestamp: Int64?) -> String {
        guard let timestamp else { return "Unknown" }
        return Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .abbreviated, time: .shortened)
    }

    func sizeLabel(for bytes: Int64?) -> String {
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
