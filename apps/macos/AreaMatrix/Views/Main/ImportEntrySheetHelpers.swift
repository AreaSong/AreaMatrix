import SwiftUI

struct BatchAddTagsTrigger: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedCount: Int
    let disabledReason: String?
    let tagStore: any CoreTagCRUD
    let errorMapper: any CoreErrorMapping
    @State private var isPresented = false

    var body: some View {
        Button("Add tag...") {
            isPresented = true
        }
        .disabled(disabledReason != nil)
        .help(disabledReason ?? "Add tags to the selected files")
        .accessibilityIdentifier("S2-09-batch-add-tags-open")
        .sheet(isPresented: $isPresented) {
            BatchAddTagsSheet(
                repoPath: repoPath,
                fileIDs: fileIDs,
                selectedCount: selectedCount,
                disabledReason: disabledReason,
                tagStore: tagStore,
                errorMapper: errorMapper,
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
    let errorMapper: any CoreErrorMapping
    let onClose: () -> Void
    @State private var input = ""
    @State private var pendingTags: [String] = []
    @State private var fieldError: String?
    @State private var catalogState: BatchTagCatalogState = .idle
    @State private var isApplying = false
    @State private var report: BatchMutationReportSnapshot?
    @State private var failure: CoreErrorMappingSnapshot?
    @State private var showsDetails = false

    var body: some View {
        MainFileActionSheetContainer(title: "批量添加标签", pageID: "S2-09") {
            if selectedCount == 0 {
                Text("No files selected")
                    .foregroundStyle(.secondary)
                HStack { Spacer(); Button("Close", action: onClose) }
            } else {
                content
            }
        }
        .task(id: fileIDs) { await loadTagCatalog() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已选择 \(selectedCount) 个文件")
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
            TextField("Search or create tag...", text: $input)
                .textFieldStyle(.roundedBorder)
                .disabled(isApplying || disabledReason != nil)
                .onSubmit(addPendingTag)
                .onChange(of: input) { _, _ in fieldError = nil }
                .accessibilityIdentifier("S2-09-tag-input")
            Text(inputHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tagCandidates: some View {
        if catalogState.isLoading {
            Text("Loading tags...")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let failure = catalogState.failure {
            HStack(spacing: 8) {
                Text(failure.userMessage)
                Button("Retry") { Task { await loadTagCatalog() } }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if !candidateTags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("候选标签")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(candidateTags) { tag in
                    Button(action: { addCandidateTag(tag) }) {
                        HStack {
                            Text(tag.displayName)
                            Spacer()
                            Text(candidateStatusText(tag))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(tag.selected || tag.disabled || isApplying)
                    .accessibilityLabel("\(tag.displayName), \(candidateStatusText(tag))")
                }
            }
        }
    }

    @ViewBuilder
    private var pendingTagChips: some View {
        if !pendingTags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("将添加的标签")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(pendingChips, id: \.value) { chip in
                    HStack(spacing: 8) {
                        Text(chip.value)
                        Text(chip.status.rawValue)
                            .foregroundStyle(.secondary)
                        Button {
                            pendingTags.removeAll { $0 == chip.value }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .imageScale(.small)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isApplying)
                        .accessibilityLabel("Remove pending tag \(chip.value)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Pending tag \(chip.value), \(chip.status.rawValue)")
                }
            }
        }
    }

    private var preview: some View {
        Text(previewText)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var resultSummary: some View {
        if let report {
            let presentation = BatchMutationReportPresentation(report: report)
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.addedSummaryText)
                Text(presentation.skippedSummaryText)
                Text(presentation.failedSummaryText)
                if report.undoToken != nil {
                    Label("已添加标签 [Undo]", systemImage: "arrow.uturn.backward.circle")
                }
                if report.failedCount > 0 {
                    Button("View details") { showsDetails.toggle() }
                    if showsDetails {
                        ForEach(report.itemResults.filter { $0.status == .failed }) { item in
                            Text("File \(item.fileID), \(item.tag): \(item.error ?? "Failed")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
        if let failure {
            Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Add pending tag", action: addPendingTag)
                .disabled(
                    isApplying || disabledReason != nil ||
                        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            Spacer()
            Button("Cancel", action: onClose)
                .keyboardShortcut(.cancelAction)
                .disabled(isApplying)
            Button(isApplying ? "Applying..." : "Apply") {
                Task { await apply() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
            .accessibilityIdentifier("S2-09-batch-add-tags-apply")
        }
    }

    private var previewText: String {
        guard !pendingTags.isEmpty else { return "未选择任何标签。" }
        return """
        将为 \(selectedCount) 个文件添加标签：\(pendingChips.map(\.value).joined(separator: ", "))
        已包含这些标签的文件会跳过重复写入。
        """
    }

    private var inputHelpText: String {
        fieldError ?? disabledReason.map { _ in "Tag store is read-only." } ?? ""
    }

    private var candidateTags: [TagRecordSnapshot] {
        BatchTagValidation.visibleCandidates(
            input: input,
            catalog: catalogState.tagSet,
            pendingTags: pendingTags
        )
    }

    private var pendingChips: [BatchPendingTagChip] {
        BatchTagValidation.pendingChips(pendingTags: pendingTags, disabledReason: disabledReason)
    }

    private var canApply: Bool {
        BatchTagValidation.canApply(
            isApplying: isApplying,
            disabledReason: disabledReason,
            input: input,
            pendingTags: pendingTags,
            fieldError: fieldError,
            selectedCount: selectedCount
        )
    }

    private func addPendingTag() {
        let state = BatchTagValidation.pendingStateAfterAdding(
            input: input,
            pendingTags: pendingTags,
            catalog: catalogState.tagSet,
            disabledReason: disabledReason
        )
        input = state.input
        pendingTags = state.pendingTags
        fieldError = state.fieldError
    }

    private func addCandidateTag(_ tag: TagRecordSnapshot) {
        let state = BatchTagValidation.pendingStateAfterAdding(
            input: tag.value,
            pendingTags: pendingTags,
            catalog: catalogState.tagSet,
            disabledReason: tag.disabled ? "Tag store is read-only." : disabledReason
        )
        input = state.input
        pendingTags = state.pendingTags
        fieldError = state.fieldError
    }

    private func candidateStatusText(_ tag: TagRecordSnapshot) -> String {
        if tag.disabled { return "Blocked" }
        if tag.selected { return "Already selected" }
        return "\(tag.fileCount) files"
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
        guard canApply else { return }
        switch BatchTagValidation.normalizedTagsForApply(pendingTags) {
        case let .failure(message):
            fieldError = message
            return
        case let .success(tags):
            await submit(tags: tags)
        }
    }

    @MainActor
    private func submit(tags: [String]) async {
        isApplying = true
        failure = nil
        report = nil
        let result = await BatchAddTagsAction.apply(
            repoPath: repoPath,
            fileIDs: fileIDs,
            tags: tags,
            tagStore: tagStore,
            errorMapper: errorMapper
        )
        report = result.report
        failure = result.failure
        isApplying = false
    }
}

enum ImportEntrySheetHelper {
    static func categoryOptions(
        availableCategories: [String],
        selectedCategory: String,
        predictedCategory: String?
    ) -> [String] {
        let values = availableCategories + [selectedCategory, predictedCategory, "inbox"]
        var uniqueValues: [String] = []
        for value in values.compactMap({ $0 }).filter({ !$0.isEmpty }) where !uniqueValues.contains(value) {
            uniqueValues.append(value)
        }
        return uniqueValues
    }

    static func primaryFileLabel(urls: [URL]) -> String {
        guard let firstURL = urls.first else {
            return "No valid file URL"
        }
        if urls.count == 1 {
            return firstURL.path
        }
        return "\(firstURL.path) and \(urls.count - 1) more"
    }
}

struct MainFileActionSheetContainer<Content: View>: View {
    let title: String
    let pageID: String
    private let content: Content

    init(title: String, pageID: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.pageID = pageID
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(22)
        .frame(width: 420, alignment: .leading)
        .accessibilityIdentifier("\(pageID)-file-action-sheet")
    }
}

struct MissingFileActionContext: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The selected file context is no longer available.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}

func metadataRow(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(value)
            .font(.callout)
            .textSelection(.enabled)
    }
}

extension ImportEntrySheetView {
    func batchCategoryOptions(
        row: ImportBatchCopyImportRow,
        destination: ImportBatchDestinationOption
    ) -> [String] {
        ImportEntrySheetHelper.categoryOptions(
            availableCategories: request.availableCategories,
            selectedCategory: row.displayCategory(for: destination),
            predictedCategory: row.predictedCategory
        )
    }
}

extension ImportEntryRequest {
    var initialBatchDestination: ImportBatchDestinationOption {
        switch destination {
        case .autoClassify:
            .autoClassify
        case let .category(slug):
            .category(slug)
        case .repositoryRoot:
            .repositoryRoot
        }
    }
}

struct DetailMetaMetadataRow: Equatable, Identifiable {
    let label: String
    let value: String

    var id: String {
        label
    }
}

func detailMetaMetadataRows(for detail: FileEntrySnapshot) -> [DetailMetaMetadataRow] {
    [
        DetailMetaMetadataRow(label: "Category", value: detail.category),
        DetailMetaMetadataRow(label: "Path", value: detail.path),
        DetailMetaMetadataRow(label: "Size", value: detail.sizeDisplay),
        DetailMetaMetadataRow(label: "Storage", value: detail.storageMode),
        DetailMetaMetadataRow(label: "Origin", value: detail.origin),
        DetailMetaMetadataRow(label: "Imported", value: detail.importedAtDisplay),
        DetailMetaMetadataRow(label: "Modified", value: detail.updatedAtDisplay),
        DetailMetaMetadataRow(label: "SHA-256", value: detail.hashSha256),
        DetailMetaMetadataRow(label: "Source", value: detailMetaDisplayValue(detail.sourcePath)),
        DetailMetaMetadataRow(label: "Status", value: detail.statusDisplay)
    ]
}

private func detailMetaDisplayValue(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "Not available" }
    return value
}
