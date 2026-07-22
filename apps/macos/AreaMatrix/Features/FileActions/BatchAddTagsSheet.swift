import SwiftUI

struct BatchAddTagsTrigger: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedCount: Int
    let disabledReason: String?
    let tagStore: any CoreTagCRUD
    let undoStore: any CoreUndoActionLogging
    let errorMapper: any CoreErrorMapping
    let onRefreshSelection: () -> Void
    let onRefreshChangeLog: () -> Void
    let onUndoStateChange: (BatchTagUndoState) -> Void
    @State private var isPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Add tag...") { isPresented = true }
                .help(BatchAddTagsEntryPolicy.openHelp(disabledReason: disabledReason))
                .accessibilityIdentifier("batch-add-tags-batch-add-tags-open")
        }
        .sheet(isPresented: $isPresented) {
            BatchAddTagsSheet(
                repoPath: repoPath,
                fileIDs: fileIDs,
                selectedCount: selectedCount,
                disabledReason: disabledReason,
                tagStore: tagStore,
                undoStore: undoStore,
                errorMapper: errorMapper,
                onUndoStateChange: onUndoStateChange,
                onClose: { isPresented = false }
            )
        }
    }
}

struct BatchAddTagsSheet: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedCount: Int
    let disabledReason: String?
    let tagStore: any CoreTagCRUD
    let undoStore: any CoreUndoActionLogging
    let errorMapper: any CoreErrorMapping
    let onUndoStateChange: (BatchTagUndoState) -> Void
    let onClose: () -> Void
    @State private var draft = BatchAddTagsDraft()
    @State private var catalogState: BatchTagCatalogState = .idle
    @State private var isApplying = false
    @State private var report: BatchMutationReportSnapshot?
    @State private var failure: CoreErrorMappingSnapshot?
    @State private var showsDetails = false

    var body: some View {
        MainFileActionSheetContainer(title: L10n.string("fileActions.batchTags.title"), pageID: "batch-add-tags") {
            if selectedCount == 0 {
                Text("No files selected")
                    .foregroundStyle(.secondary)
                HStack { Spacer(); Button("Close", action: onClose) }
            } else {
                BatchAddTagsSheetContent(
                    selectedCount: selectedCount,
                    disabledReason: disabledReason,
                    draft: $draft,
                    catalogState: catalogState,
                    isApplying: isApplying,
                    report: report,
                    failure: failure,
                    showsDetails: $showsDetails,
                    onAddPendingTag: addPendingTag,
                    onAddCandidateTag: addCandidateTag,
                    onRetryCatalog: { Task { await loadTagCatalog() } },
                    onApply: { Task { await apply() } },
                    onCancel: onClose
                )
            }
        }
        .task(id: fileIDs) { await loadTagCatalog() }
    }

    private func addPendingTag() {
        let state = BatchTagValidation.pendingStateAfterAdding(
            input: draft.input,
            pendingTags: draft.pendingTags,
            catalog: catalogState.tagSet,
            disabledReason: disabledReason
        )
        draft.apply(state)
    }

    private func addCandidateTag(_ tag: TagRecordSnapshot) {
        let state = BatchTagValidation.pendingStateAfterAdding(
            input: tag.value,
            pendingTags: draft.pendingTags,
            catalog: catalogState.tagSet,
            disabledReason: tag.disabled ? "Tag store is read-only." : disabledReason
        )
        draft.apply(state)
    }

    @MainActor
    private func loadTagCatalog() async {
        let previous = catalogState.tagSet
        catalogState = .loading(previous: previous)
        let state = await BatchTagCatalogAction.load(
            repoPath: repoPath,
            fileIDs: fileIDs,
            tagStore: tagStore,
            errorMapper: errorMapper
        )
        switch state {
        case let .failed(mapping, _):
            catalogState = .failed(mapping, previous: previous)
        default:
            catalogState = state
        }
    }

    @MainActor
    private func apply() async {
        guard BatchTagValidation.canApply(BatchTagApplyEligibility(
            isApplying: isApplying,
            disabledReason: disabledReason,
            input: draft.input,
            pendingTags: draft.pendingTags,
            fieldError: draft.fieldError,
            selectedCount: selectedCount
        )) else { return }
        switch BatchTagValidation.normalizedTagsForApply(draft.pendingTags) {
        case let .failure(message):
            draft.fieldError = message
        case let .success(tags):
            await submit(tags: tags)
        }
    }

    @MainActor
    private func submit(tags: [String]) async {
        isApplying = true; failure = nil; report = nil
        onUndoStateChange(.idle)
        let result = await BatchAddTagsAction.apply(
            repoPath: repoPath,
            fileIDs: fileIDs,
            tags: tags,
            tagStore: tagStore,
            errorMapper: errorMapper
        )
        report = result.report; failure = result.failure; isApplying = false
        let completion = await BatchTagUndoAction.completionAfterBatchApply(
            repoPath: repoPath,
            report: result.report,
            failure: result.failure,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        if let undoState = completion.undoState {
            onUndoStateChange(undoState)
        }
        if completion.closesSheet {
            onClose()
        }
    }
}

private struct BatchAddTagsDraft: Equatable {
    var input = ""
    var pendingTags: [String] = []
    var fieldError: String?

    mutating func apply(_ state: BatchTagPendingState) {
        input = state.input
        pendingTags = state.pendingTags
        fieldError = state.fieldError
    }
}

private struct BatchAddTagsSheetContent: View {
    let selectedCount: Int
    let disabledReason: String?
    @Binding var draft: BatchAddTagsDraft
    let catalogState: BatchTagCatalogState
    let isApplying: Bool
    let report: BatchMutationReportSnapshot?
    let failure: CoreErrorMappingSnapshot?
    @Binding var showsDetails: Bool
    let onAddPendingTag: () -> Void
    let onAddCandidateTag: (TagRecordSnapshot) -> Void
    let onRetryCatalog: () -> Void
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.plural("file-actions.add-tags.selected-files", count: selectedCount))
                .font(.callout)
            tagInput
            tagCandidates
            pendingTagChips
            preview
            resultSummary
            actionButtons
        }
    }

    private var tagInput: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("Search or create tag...", text: $draft.input)
                .textFieldStyle(.roundedBorder)
                .disabled(isApplying || disabledReason != nil)
                .onSubmit(onAddPendingTag)
                .onChange(of: draft.input) { _, _ in draft.fieldError = nil }
                .accessibilityIdentifier("batch-add-tags-tag-input")
            Text(inputHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tagCandidates: some View {
        if catalogState.isLoading {
            Text("Loading tags...").font(.caption).foregroundStyle(.secondary)
        } else if let failure = catalogState.failure {
            HStack(spacing: 8) {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                Button("Retry", action: onRetryCatalog)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if !candidateTags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("候选标签").font(.caption).foregroundStyle(.secondary)
                ForEach(candidateTags) { tag in
                    candidateButton(tag)
                }
            }
        }
    }

    private func candidateButton(_ tag: TagRecordSnapshot) -> some View {
        Button {
            onAddCandidateTag(tag)
        } label: {
            HStack {
                Text(tag.displayName)
                Spacer()
                Text(candidateStatusText(tag)).foregroundStyle(.secondary)
            }
        }
        .disabled(tag.selected || tag.disabled || isApplying)
        .accessibilityLabel(
            L10n.format("file-actions.tag-suggestion.accessibility-summary", tag.displayName, candidateStatusText(tag))
        )
    }

    @ViewBuilder
    private var pendingTagChips: some View {
        if !draft.pendingTags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("将添加的标签").font(.caption).foregroundStyle(.secondary)
                ForEach(pendingChips, id: \.value) { chip in
                    pendingChip(chip)
                }
            }
        }
    }

    private func pendingChip(_ chip: BatchPendingTagChip) -> some View {
        NeutralCapsuleChip {
            HStack(spacing: 8) {
                Text(chip.value)
                Text(chip.status.displayName).foregroundStyle(.secondary)
                Button {
                    draft.pendingTags.removeAll { $0 == chip.value }
                } label: {
                    Image(systemName: "xmark.circle").imageScale(.small)
                }
                .buttonStyle(.borderless)
                .disabled(isApplying)
                .accessibilityLabel(L10n.format("file-actions.add-tags.remove-pending", chip.value))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.format("file-actions.add-tags.pending-summary", chip.value, chip.status.displayName)
        )
    }

    private var preview: some View {
        Text(previewText)
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var resultSummary: some View {
        if let report {
            let presentation = BatchMutationReportPresentation(report: report)
            NeutralSummaryPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.addedSummaryText)
                    Text(presentation.skippedSummaryText)
                    Text(presentation.failedSummaryText)
                    failureDetails(for: report)
                }
            }
        }
        if let failure {
            Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func failureDetails(for report: BatchMutationReportSnapshot) -> some View {
        if report.failedCount > 0 {
            Button("View details") { showsDetails.toggle() }
            if showsDetails {
                ForEach(report.itemResults.filter { $0.status == .failed }) { item in
                    Text(
                        L10n.format(
                            "file-actions.add-tags.file-error",
                            item.fileID,
                            item.tag,
                            item.error ?? L10n.string("Failed")
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Add pending tag", action: onAddPendingTag)
                .disabled(
                    isApplying || disabledReason != nil ||
                        draft.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(isApplying)
            Button(isApplying ? L10n.string("Applying...") : L10n.string("Apply"), action: onApply)
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
                .accessibilityIdentifier("batch-add-tags-batch-add-tags-apply")
        }
    }

    private var previewText: String {
        guard !draft.pendingTags.isEmpty else {
            return L10n.string("fileActions.batchTags.noneSelected")
        }
        return L10n.format(
            "fileActions.batchTags.preview",
            selectedCount,
            pendingChips.map(\.value).joined(separator: ", ")
        )
    }

    private var inputHelpText: String {
        draft.fieldError ?? disabledReason.map { _ in L10n.string("Tag store is read-only.") } ?? ""
    }

    private var candidateTags: [TagRecordSnapshot] {
        BatchTagValidation.visibleCandidates(
            input: draft.input,
            catalog: catalogState.tagSet,
            pendingTags: draft.pendingTags
        )
    }

    private var pendingChips: [BatchPendingTagChip] {
        BatchTagValidation.pendingChips(pendingTags: draft.pendingTags, disabledReason: disabledReason)
    }

    private var canApply: Bool {
        BatchTagValidation.canApply(BatchTagApplyEligibility(
            isApplying: isApplying,
            disabledReason: disabledReason,
            input: draft.input,
            pendingTags: draft.pendingTags,
            fieldError: draft.fieldError,
            selectedCount: selectedCount
        ))
    }

    private func candidateStatusText(_ tag: TagRecordSnapshot) -> String {
        if tag.disabled { return L10n.string("Blocked") }
        if tag.selected { return L10n.string("Already selected") }
        return L10n.plural("file-actions.add-tags.file-count", count: tag.fileCount)
    }
}
