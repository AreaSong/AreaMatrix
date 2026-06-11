import SwiftUI

@MainActor
struct ImportBatchConflictSection: View {
    let batchImportModel: ImportBatchCopyImportModel
    @Binding var isExpanded: Bool
    @Binding var pendingReplaceConfirmation: ImportBatchReplaceConfirmation?
    let onRetryPreview: () -> Void
    let onSwitchToLocalRepo: () -> Void
    let onShowExistingFile: (String) -> Void
    @State var showsBatchReplaceConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if batchImportModel.showsCoreConflictBatchReview {
                coreConflictBatchReview
            }
            if batchImportModel.iCloudPlaceholderCount > 0 {
                iCloudActions
            }
            if isExpanded
                || batchImportModel.duplicateCount > 0
                || batchImportModel.nameConflictCount > 0
                || batchImportModel.iCloudPlaceholderCount > 0
                || batchImportModel.blockedCount > 0 {
                conflictsTable
            }
        }
        .confirmationDialog(
            ImportConflictBatchValidation.confirmationTitle(for: batchImportModel.conflictBatchPreviewReport),
            isPresented: $showsBatchReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move existing files to Trash and Replace", role: .destructive) {
                batchImportModel.confirmConflictBatchReplace()
                Task { await batchImportModel.applyImportConflictBatch(replaceConfirmed: true) }
            }
            Button("Cancel", role: .cancel) {
                batchImportModel.cancelConflictBatchReplace()
            }
        } message: {
            Text(batchImportModel.conflictBatchReplaceConfirmationMessage)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review conflicts")
                    .font(.headline)
                Text(conflictSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(isExpanded ? "Hide" : "Review conflicts") {
                isExpanded.toggle()
            }
        }
    }

    private var iCloudActions: some View {
        HStack(spacing: 10) {
            Button("Download all & retry preview") {
                Task {
                    let didDownload = await batchImportModel.downloadAllICloudPlaceholdersAndRetry()
                    if didDownload {
                        onRetryPreview()
                    }
                }
            }
            .disabled(batchImportModel.isICloudDownloading || batchImportModel.status.isImporting)
            Button("Switch to local repo...", action: onSwitchToLocalRepo)
                .disabled(batchImportModel.status.isImporting)
            if batchImportModel.isICloudDownloading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var coreConflictBatchReview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Resolve import conflicts")
                    .font(.headline)
                Spacer()
                Button("Retry") {
                    Task { await batchImportModel.refreshImportConflictBatchPreview() }
                }
                .disabled(batchImportModel.conflictBatchPreviewState.isLoading)
            }

            coreConflictBatchSummary
            coreConflictBatchStrategyControls
            coreConflictBatchRows
            coreConflictBatchPerItemQueue
            coreConflictBatchResult
            ImportConflictBatchUndoStateView(
                state: batchImportModel.conflictBatchUndoState,
                onUndo: {
                    Task { await batchImportModel.undoImportConflictBatchAction() }
                },
                onDismiss: {
                    batchImportModel.conflictBatchUndoState = .idle
                }
            )
            coreConflictBatchActions
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var coreConflictBatchSummary: some View {
        if batchImportModel.conflictBatchPreviewState.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking conflicts...")
                    .foregroundStyle(.secondary)
            }
        } else if let failure = batchImportModel.conflictBatchFailure {
            VStack(alignment: .leading, spacing: 4) {
                Text(failure.userMessage)
                    .foregroundStyle(.red)
                Text(failure.suggestedAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let preview = batchImportModel.conflictBatchPreviewReport {
            VStack(alignment: .leading, spacing: 4) {
                Text(batchImportModel.conflictBatchScopeSummary)
                Text("\(preview.includedCount) included · \(preview.pendingCount) pending · " +
                    "\(preview.blockedCount) blocked · \(preview.replaceCount) replace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Existing files will not be replaced unless you explicitly choose Replace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No conflicts remain")
                .foregroundStyle(.secondary)
        }
    }

    private var coreConflictBatchStrategyControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Apply this strategy to all similar conflicts", isOn: Binding(
                get: { batchImportModel.appliesConflictBatchToAll },
                set: { newValue in
                    batchImportModel.updateConflictBatchScope(appliesToAll: newValue)
                    Task { await batchImportModel.refreshImportConflictBatchPreview() }
                }
            ))
            .disabled(batchImportModel.status.isImporting || batchImportModel.isConflictBatchApplying)

            HStack(spacing: 12) {
                conflictBatchStrategyPicker(
                    "Duplicates by content",
                    strategies: [.skip, .keepBoth, .replace],
                    selection: Binding(
                        get: { batchImportModel.conflictBatchDuplicateStrategy },
                        set: { strategy in
                            batchImportModel.updateConflictBatchDuplicateStrategy(strategy)
                            Task { await batchImportModel.refreshImportConflictBatchPreview() }
                        }
                    )
                )
                conflictBatchStrategyPicker(
                    "Same name, different content",
                    strategies: [.keepBoth, .askPerItem, .replace],
                    selection: Binding(
                        get: { batchImportModel.conflictBatchSameNameStrategy },
                        set: { strategy in
                            batchImportModel.updateConflictBatchSameNameStrategy(strategy)
                            Task { await batchImportModel.refreshImportConflictBatchPreview() }
                        }
                    )
                )
            }
        }
    }

    private var coreConflictBatchRows: some View {
        Table(batchImportModel.coreConflictBatchRows) {
            TableColumn("Use") { item in
                Toggle("", isOn: Binding(
                    get: { batchImportModel.selectedConflictBatchIDs.contains(item.id) },
                    set: { isSelected in
                        batchImportModel.setConflictBatchItemSelected(item.id, isSelected: isSelected)
                        Task { await batchImportModel.refreshImportConflictBatchPreview() }
                    }
                ))
                .labelsHidden()
                .disabled(batchImportModel.appliesConflictBatchToAll)
            }
            TableColumn("File") { item in
                Text((item.targetPath ?? item.incomingPath).lastPathComponentFallback)
            }
            TableColumn("Conflict") { item in
                Text(item.conflictType.title)
            }
            TableColumn("Existing") { item in
                Text(item.existingPath ?? "-")
            }
            TableColumn("Selected action") { item in
                Text(item.selectedStrategy.title)
            }
            TableColumn("Status") { item in
                Text(item.status.rawValue)
            }
            TableColumn("Reason") { item in
                Text(item.reason ?? item.riskSummary)
            }
        }
        .frame(minHeight: 140)
    }

    @ViewBuilder
    private var coreConflictBatchPerItemQueue: some View {
        if let summary = batchImportModel.conflictBatchPerItemSummary {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary)
                    .font(.callout)
                Text(batchImportModel.conflictBatchPerItemRouteLabels.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var coreConflictBatchResult: some View {
        if let report = batchImportModel.conflictBatchApplyResult?.report {
            Text("\(report.resolvedCount) resolved · \(report.failedCount) failed · " +
                "\(report.pendingCount) pending · \(report.queuedForPerItemCount) queued for per-item")
                .font(.callout)
                .foregroundStyle(report.failedCount > 0 ? .orange : .secondary)
            if let failureSummary = report.failureSummary {
                Text(failureSummary)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var coreConflictBatchActions: some View {
        HStack(spacing: 10) {
            Button("Ask per item") {
                Task { await batchImportModel.askConflictBatchPerItem() }
            }
            .disabled(batchImportModel.conflictBatchAskPerItemDisabledReason != nil)
            if let reason = batchImportModel.conflictBatchAskPerItemDisabledReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply strategy") {
                if batchImportModel.conflictBatchPreviewReport?.replaceConfirmationRequired == true,
                   !batchImportModel.isConflictBatchReplaceConfirmed {
                    showsBatchReplaceConfirmation = true
                } else {
                    Task { await batchImportModel.applyImportConflictBatch() }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(batchImportModel.conflictBatchApplyDisabledReason != nil)
            if let reason = batchImportModel.conflictBatchApplyDisabledReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var conflictsTable: some View {
        Table(batchImportModel.rows.filter(\.isConflictReviewRow)) {
            TableColumn("File") { row in
                Text(row.originalName)
            }
            TableColumn("Conflict") { row in
                Text(row.conflictLabel)
            }
            TableColumn("Existing item") { row in
                Text(row.existingConflictPath ?? "-")
            }
            TableColumn("Incoming resolution") { row in
                incomingResolutionView(for: row)
            }
            TableColumn("Strategy") { row in
                strategyView(for: row)
            }
            TableColumn("Status") { row in
                Text(row.status.detail ?? row.status.tag)
            }
            TableColumn("Action") { row in
                actionView(for: row)
            }
        }
        .frame(minHeight: 120)
    }

    private var conflictSummary: String {
        [
            "\(batchImportModel.duplicateCount) duplicates",
            "\(batchImportModel.nameConflictCount) name conflict",
            "\(batchImportModel.iCloudPlaceholderCount) iCloud",
            "\(batchImportModel.blockedCount) blocked"
        ].joined(separator: " · ")
    }
}

private extension ImportBatchCopyImportModel {
    var conflictBatchReplaceConfirmationMessage: String {
        let summary = conflictBatchPreviewReport?.replaceConfirmationSummary ?? conflictBatchScopeSummary
        return [
            "Existing files in the selected scope will be moved to Trash before imported files take their place.",
            "AreaMatrix does not permanently delete files in Stage 2.",
            "Scope: \(summary)"
        ].joined(separator: " ")
    }
}

private extension String {
    var lastPathComponentFallback: String {
        let component = URL(fileURLWithPath: self).lastPathComponent
        return component.isEmpty ? self : component
    }
}

struct ImportBatchReplaceConfirmation: Identifiable, Equatable {
    var rowID: ImportBatchCopyImportRow.ID
    var context: SingleFileReplaceConfirmationContext

    var id: String {
        "\(rowID)|\(context.id)"
    }
}
