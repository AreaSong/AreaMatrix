import SwiftUI

struct BatchDeleteTrigger: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let deleter: any CoreBatchDeleting
    let undoStore: any CoreUndoActionLogging
    let errorMapper: any CoreErrorMapping
    let onApplied: (BatchDeleteReportSnapshot) -> Void
    let onUndoStateChange: (BatchTagUndoState) -> Void
    @State private var isPresented = false

    var body: some View {
        Button("Delete...") { isPresented = true }
            .help(BatchDeleteEntryPolicy.openHelp(disabledReason: disabledReason))
            .accessibilityIdentifier("batch-delete-batch-delete-open")
            .sheet(isPresented: $isPresented) {
                BatchDeleteConfirmSheet(
                    repoPath: repoPath,
                    fileIDs: fileIDs,
                    selectedFiles: selectedFiles,
                    selectedCount: selectedCount,
                    disabledReason: disabledReason,
                    deleter: deleter,
                    undoStore: undoStore,
                    errorMapper: errorMapper,
                    onApplied: onApplied,
                    onUndoStateChange: onUndoStateChange,
                    onClose: { isPresented = false }
                )
            }
    }
}

struct BatchDeleteConfirmSheet: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let deleter: any CoreBatchDeleting
    let undoStore: any CoreUndoActionLogging
    let errorMapper: any CoreErrorMapping
    let onApplied: (BatchDeleteReportSnapshot) -> Void
    let onUndoStateChange: (BatchTagUndoState) -> Void
    let onClose: () -> Void
    @State private var deleteMode: BatchDeleteModeSnapshot = .moveToTrash
    @State private var previewState: BatchDeletePreviewState = .idle
    @State private var isApplying = false
    @State private var result: BatchDeleteReportSnapshot?
    @State private var failure: CoreErrorMappingSnapshot?
    @State private var showsDetails = false
    @State private var undoConfirmationAccepted = false

    var body: some View {
        MainFileActionSheetContainer(title: title, pageID: "batch-delete") {
            if selectedCount == 0 {
                Text("No items selected")
                    .foregroundStyle(.secondary)
                HStack { Spacer(); Button("Close", action: onClose) }
            } else {
                content
            }
        }
        .task(id: previewTaskKey) { await refreshPreview() }
        .accessibilityIdentifier("batch-delete-batch-delete-trash-batch-delete-confirm")
    }

    private var title: String {
        guard selectedCount > 0 else { return L10n.string("Review deletion") }
        if previewState.report?.blockedCount ?? 0 > 0 || previewState.report?.indexOnlyCount ?? 0 > 0 {
            return L10n.plural("file-actions.delete.review-selected-items", count: selectedCount)
        }
        return L10n.plural("file-actions.delete.move-files-confirmation", count: selectedCount)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "Files managed by AreaMatrix will be moved to Trash. " +
                    "Index-only items can be removed from the index without deleting the source files."
            )
            .foregroundStyle(.secondary)
            modePicker
            previewSection
            undoConfirmationSection
            resultSection
            actionButtons
        }
    }

    private var modePicker: some View {
        Picker("Deletion mode", selection: $deleteMode) {
            Text("Move to Trash").tag(BatchDeleteModeSnapshot.moveToTrash)
            Text("Remove from index").tag(BatchDeleteModeSnapshot.removeFromIndex)
        }
        .pickerStyle(.segmented)
        .disabled(isApplying || disabledReason != nil)
        .accessibilityIdentifier("batch-delete-delete-mode")
    }

    @ViewBuilder
    private var previewSection: some View {
        if previewState.isLoading {
            Label("Checking delete impact...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        }
        if let failure = previewState.failure {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                Spacer()
                Button("Retry") { Task { await refreshPreview() } }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        if let preview = previewState.report {
            BatchDeletePreviewSummary(
                preview: preview,
                showsDetails: showsDetails,
                onToggleDetails: { showsDetails.toggle() }
            )
        }
        if let reason = disabledReason {
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var undoConfirmationSection: some View {
        if previewState.report?.undoAvailable == false {
            TintedStatusBanner(tint: .yellow, fillsWidth: false, contentPadding: 10, backgroundOpacity: 0.12) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "Undo will not be available for these items. Review the list before continuing.",
                        systemImage: "exclamationmark.triangle"
                    )
                    Toggle("I understand undo will not be available for these items.", isOn: $undoConfirmationAccepted)
                        .accessibilityLabel(
                            L10n.string(
                                "Required confirmation. Undo will not be available for this deletion or index removal."
                            )
                        )
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let result {
            BatchDeleteResultSummary(
                result: result,
                showsDetails: showsDetails,
                onToggleDetails: { showsDetails.toggle() }
            )
        }
        if let failure {
            Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Retry failed") { Task { await retryFailed() } }
                .disabled(!BatchDeleteValidation.canRetryFailed(report: result, isApplying: isApplying))
            Spacer()
            Button("Cancel", action: onClose)
                .keyboardShortcut(.cancelAction)
                .disabled(isApplying)
            if shouldShowRemoveFromIndex {
                Button(removeFromIndexTitle) {
                    Task { await apply(mode: .removeFromIndex) }
                }
                .disabled(!canApplyMode(.removeFromIndex))
                .accessibilityIdentifier("batch-delete-batch-delete-trash-remove-from-index")
            }
            Button(primaryTitle, role: .destructive) {
                Task { await apply(mode: .moveToTrash) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApplyMode(.moveToTrash))
            .accessibilityIdentifier("batch-delete-batch-delete-trash-move-to-trash")
        }
    }

    @MainActor
    private func refreshPreview() async {
        guard selectedCount > 0, disabledReason == nil else { return }
        let previous = previewState.report
        previewState = .loading(previous: previous)
        failure = nil
        result = nil
        undoConfirmationAccepted = false
        previewState = await BatchDeleteAction.preview(
            repoPath: repoPath,
            fileIDs: fileIDs,
            deleteMode: deleteMode,
            deleter: deleter,
            errorMapper: errorMapper
        )
    }

    @MainActor
    private func apply(mode: BatchDeleteModeSnapshot) async {
        guard let preview = previewState.report,
              preview.deleteMode == mode,
              canApplyMode(mode) else { return }
        isApplying = true
        failure = nil
        result = nil
        onUndoStateChange(.idle)
        let applyResult = await BatchDeleteAction.apply(
            repoPath: repoPath,
            fileIDs: preview.fileIDs,
            preview: preview,
            deleter: deleter,
            errorMapper: errorMapper
        )
        result = applyResult.report
        failure = applyResult.failure
        isApplying = false
        if let report = applyResult.report, report.shouldRefreshConsumerAfterApply {
            onApplied(report)
        }
        let undoState = await BatchDeleteUndoAction.stateAfterBatchApply(
            repoPath: repoPath,
            report: applyResult.report,
            failure: applyResult.failure,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        if let undoState {
            onUndoStateChange(undoState)
        }
        if let report = applyResult.report, report.shouldCloseSheetAfterApply {
            onClose()
        }
    }

    @MainActor
    private func retryFailed() async {
        guard let result else { return }
        let failedIDs = BatchDeleteValidation.failedFileIDs(result)
        guard !failedIDs.isEmpty else { return }
        await refreshPreview(fileIDs: failedIDs)
    }

    @MainActor
    private func refreshPreview(fileIDs retryFileIDs: [Int64]) async {
        let previous = previewState.report
        previewState = .loading(previous: previous)
        failure = nil
        previewState = await BatchDeleteAction.preview(
            repoPath: repoPath,
            fileIDs: retryFileIDs,
            deleteMode: deleteMode,
            deleter: deleter,
            errorMapper: errorMapper
        )
    }

    private func canApplyMode(_ mode: BatchDeleteModeSnapshot) -> Bool {
        BatchDeleteValidation.canApply(BatchDeleteApplyGate(
            fileIDs: fileIDs,
            preview: previewState.report,
            deleteMode: mode,
            disabledReason: disabledReason,
            undoConfirmationAccepted: undoConfirmationAccepted,
            isApplying: isApplying
        ))
    }

    private var previewTaskKey: String {
        "\(fileIDs.map(String.init).joined(separator: ","))|\(deleteMode.rawValue)"
    }

    private var shouldShowRemoveFromIndex: Bool {
        previewState.report?.hasIndexRemovalCandidates == true
    }

    private var removeFromIndexTitle: String {
        isApplying && deleteMode == .removeFromIndex
            ? L10n.string("Removing...")
            : L10n.string("Remove from index")
    }

    private var primaryTitle: String {
        if isApplying, deleteMode == .moveToTrash { return L10n.string("Moving...") }
        if previewState.report?.blockedCount ?? 0 > 0 { return L10n.string("Move available files to Trash") }
        return L10n.string("Move to Trash")
    }
}
