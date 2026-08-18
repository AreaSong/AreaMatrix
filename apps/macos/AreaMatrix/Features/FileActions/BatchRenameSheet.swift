import AreaMatrixFeatureOperation
import AreaMatrixUIFoundation
import SwiftUI

struct BatchRenameSheet: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let renamer: any CoreBatchRenaming
    let undoStore: any CoreUndoActionLogging
    let errorMapper: any CoreErrorMapping
    let onApplied: (BatchRenameReportSnapshot) -> Void
    let onUndoStateChange: (BatchTagUndoState) -> Void
    let onClose: () -> Void
    @State private var draft = BatchRenameRuleDraft()
    @State private var previewState: BatchRenamePreviewState = .idle
    @State private var isApplying = false
    @State private var result: BatchRenameReportSnapshot?
    @State private var failure: CoreErrorMappingSnapshot?

    var body: some View {
        AreaMatrixActionSheetContainer(title: L10n.string("fileActions.batchRename.title"), pageID: "batch-rename") {
            selectedCount == 0 ? AnyView(emptyContent) : AnyView(content)
        }
        .task(id: previewTaskKey) { await refreshPreview() }
        .accessibilityIdentifier("batch-rename-batch-rename-preview-batch-rename-preview")
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("No files selected")).foregroundStyle(.secondary)
            HStack { Spacer(); Button(L10n.string("Close"), action: onClose) }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            BatchRenameSelectedFilesSummary(selectedFiles: selectedFiles, selectedCount: selectedCount)
            RenameRuleEditor(draft: $draft, isDisabled: isApplying || disabledReason != nil)
            BatchRenamePreviewSection(
                previewState: previewState,
                validationMessage: draft.validationMessage,
                failure: failure,
                disabledReason: disabledReason
            )
            BatchRenameResultSummary(result: result)
            actionButtons
        }
    }

    private var actionButtons: some View {
        HStack {
            Button(L10n.string("Refresh preview")) { Task { await refreshPreview() } }
                .disabled(previewRefreshDisabled)
            Spacer()
            Button(L10n.string("Cancel"), action: onClose).keyboardShortcut(.cancelAction).disabled(isApplying)
            Button(isApplying ? L10n.string("Renaming...") : L10n.string("Apply")) { Task { await apply() } }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApplyPreview)
                .accessibilityIdentifier("batch-rename-batch-rename-preview-batch-rename-apply")
        }
    }

    @MainActor
    private func refreshPreview() async {
        guard selectedCount > 0, disabledReason == nil, draft.validationMessage == nil else { return }
        previewState = .loading(previous: previewState.displayReport)
        failure = nil
        result = nil
        previewState = await BatchRenameAction.preview(
            repoPath: repoPath,
            fileIDs: fileIDs,
            rule: draft.snapshot,
            renamer: renamer,
            errorMapper: errorMapper
        )
    }

    @MainActor
    private func apply() async {
        guard let preview = previewState.applyReport, canApplyPreview else { return }
        isApplying = true
        failure = nil
        result = nil
        onUndoStateChange(.idle)
        let applyResult = await BatchRenameAction.apply(
            repoPath: repoPath,
            fileIDs: fileIDs,
            preview: preview,
            renamer: renamer,
            errorMapper: errorMapper
        )
        result = applyResult.report
        failure = applyResult.failure
        isApplying = false
        if let report = applyResult.report, report.shouldRefreshConsumerAfterApply { onApplied(report) }
        let undoState = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: repoPath,
            report: applyResult.report,
            failure: applyResult.failure,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        if let undoState { onUndoStateChange(undoState) }
        if let report = applyResult.report, report.shouldCloseSheetAfterApply { onClose() }
    }

    private var canApplyPreview: Bool {
        BatchRenameValidation.canApply(
            fileIDs: fileIDs,
            preview: previewState.applyReport,
            rule: draft.snapshot,
            disabledReason: disabledReason,
            isApplying: isApplying
        )
    }

    private var previewRefreshDisabled: Bool {
        isApplying || disabledReason != nil || draft.validationMessage != nil
    }

    private var previewTaskKey: String {
        [fileIDs.map(String.init).joined(separator: ","), draft.previewKey].joined(separator: "|")
    }
}

private struct BatchRenameSelectedFilesSummary: View {
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.plural("file-actions.batch-rename.selected-files", count: selectedCount))
            ForEach(selectedFiles.prefix(5)) { file in
                Text(file.currentName).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
