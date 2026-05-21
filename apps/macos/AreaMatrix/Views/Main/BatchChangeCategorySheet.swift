import SwiftUI

struct BatchChangeCategoryTrigger: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let categoryRows: [RepositorySidebarRowSnapshot]
    let changer: any CoreBatchCategoryChanging
    let errorMapper: any CoreErrorMapping
    let onApplied: (BatchCategoryChangeReportSnapshot) -> Void
    let onCreateNewCategory: (BatchChangeCategoryNewCategoryHandoff) -> Void
    @State private var isPresented = false

    var body: some View {
        Button("Change category...") { isPresented = true }
            .help(BatchChangeCategoryEntryPolicy.openHelp(disabledReason: disabledReason))
            .accessibilityIdentifier("S2-12-batch-change-category-open")
            .sheet(isPresented: $isPresented) {
                BatchChangeCategorySheet(
                    repoPath: repoPath,
                    fileIDs: fileIDs,
                    selectedFiles: selectedFiles,
                    selectedCount: selectedCount,
                    disabledReason: disabledReason,
                    categoryRows: categoryRows,
                    changer: changer,
                    errorMapper: errorMapper,
                    onApplied: onApplied,
                    onCreateNewCategory: onCreateNewCategory,
                    onClose: { isPresented = false }
                )
            }
    }
}

struct BatchChangeCategorySheet: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let categoryRows: [RepositorySidebarRowSnapshot]
    let changer: any CoreBatchCategoryChanging
    let errorMapper: any CoreErrorMapping
    let onApplied: (BatchCategoryChangeReportSnapshot) -> Void
    let onCreateNewCategory: (BatchChangeCategoryNewCategoryHandoff) -> Void
    let onClose: () -> Void
    @State private var targetCategory: String
    @State private var createdCategories: [String] = []
    @State private var moveRepoOwnedFiles = false
    @State private var previewState: BatchChangeCategoryPreviewState = .idle
    @State private var isApplying = false
    @State private var result: BatchCategoryChangeReportSnapshot?
    @State private var failure: CoreErrorMappingSnapshot?
    @State private var showsDetails = false

    init(
        repoPath: String,
        fileIDs: [Int64],
        selectedFiles: [FileEntrySnapshot],
        selectedCount: Int,
        disabledReason: String?,
        categoryRows: [RepositorySidebarRowSnapshot],
        changer: any CoreBatchCategoryChanging,
        errorMapper: any CoreErrorMapping,
        onApplied: @escaping (BatchCategoryChangeReportSnapshot) -> Void,
        onCreateNewCategory: @escaping (BatchChangeCategoryNewCategoryHandoff) -> Void = { _ in },
        onClose: @escaping () -> Void
    ) {
        self.repoPath = repoPath
        self.fileIDs = fileIDs
        self.selectedFiles = selectedFiles
        self.selectedCount = selectedCount
        self.disabledReason = disabledReason
        self.categoryRows = categoryRows
        self.changer = changer
        self.errorMapper = errorMapper
        self.onApplied = onApplied
        self.onCreateNewCategory = onCreateNewCategory
        self.onClose = onClose
        _targetCategory = State(initialValue: BatchChangeCategorySelection.defaultTargetCategory(
            selectedFiles: selectedFiles,
            categoryRows: categoryRows
        ))
    }

    var body: some View {
        MainFileActionSheetContainer(title: "Change category for \(selectedCount) files", pageID: "S2-12") {
            if selectedCount == 0 {
                Text("No files selected")
                    .foregroundStyle(.secondary)
                HStack { Spacer(); Button("Close", action: onClose) }
            } else {
                content
            }
        }
        .task(id: previewTaskKey) { await refreshPreview() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            summarySection
            targetSection
            previewSection
            resultSection
            actionButtons
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Selected: \(selectedCount) files")
            Text("Current categories: \(currentCategoriesText)")
            ForEach(selectedFiles.prefix(5)) { file in
                Text(file.currentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("New category", selection: $targetCategory) {
                ForEach(availableCategories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.menu)
            .disabled(isApplying || disabledReason != nil)
            Button("Create new category...") {
                onCreateNewCategory(BatchChangeCategoryNewCategoryHandoff(
                    selectedFileIDs: fileIDs,
                    currentTargetCategory: targetCategory
                ))
            }
            .disabled(isApplying || disabledReason != nil)
            .accessibilityIdentifier("S2-12-create-new-category")
            Toggle("Move files into the category folder", isOn: $moveRepoOwnedFiles)
                .disabled(isApplying || disabledReason != nil)
            Text("When off, only AreaMatrix metadata changes. Files stay in their current locations.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if previewState.isLoading {
            Label("Previewing changes...", systemImage: "arrow.triangle.2.circlepath")
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
            previewSummary(preview)
        }
        if let reason = disabledReason {
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func previewSummary(_ preview: BatchCategoryPreviewReportSnapshot) -> some View {
        let presentation = BatchCategoryPreviewReportPresentation(report: preview)
        return VStack(alignment: .leading, spacing: 6) {
            Text(presentation.moveSummaryText)
            Text(presentation.metadataSummaryText)
            Text(presentation.skippedSummaryText)
            Text(presentation.blockedSummaryText)
            if let reason = preview.applyBlockedReason, !reason.isEmpty {
                Text(reason).foregroundStyle(.secondary)
            }
            Button(showsDetails ? "Hide details" : "Preview") {
                showsDetails.toggle()
            }
            if showsDetails {
                BatchChangeCategoryPreviewTable(items: preview.items)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var resultSection: some View {
        if let result {
            let presentation = BatchCategoryChangeReportPresentation(report: result)
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.changedSummaryText)
                Text(presentation.skippedSummaryText)
                Text(presentation.failedSummaryText)
                if result.failedCount > 0 {
                    failureResultDetails(for: result)
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

    @ViewBuilder
    private func failureResultDetails(for report: BatchCategoryChangeReportSnapshot) -> some View {
        Button("View details") { showsDetails.toggle() }
        if showsDetails {
            ForEach(report.itemResults.filter { $0.status == .failed }) { item in
                Text("File \(item.fileID): \(item.error ?? "Failed")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Preview") { Task { await refreshPreview() } }
                .disabled(isApplying || targetCategory.isEmpty || disabledReason != nil)
            Spacer()
            Button("Cancel", action: onClose)
                .keyboardShortcut(.cancelAction)
                .disabled(isApplying)
            Button(isApplying ? "Applying..." : "Apply") {
                Task { await apply() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
            .accessibilityIdentifier("S2-12-batch-change-category-apply")
        }
    }

    @MainActor
    private func refreshPreview() async {
        guard selectedCount > 0, disabledReason == nil, !targetCategory.isEmpty else { return }
        let previous = previewState.report
        previewState = .loading(previous: previous)
        failure = nil
        result = nil
        previewState = await BatchChangeCategoryAction.preview(
            repoPath: repoPath,
            fileIDs: fileIDs,
            targetCategory: targetCategory,
            moveRepoOwnedFiles: moveRepoOwnedFiles,
            changer: changer,
            errorMapper: errorMapper
        )
    }

    @MainActor
    private func apply() async {
        guard let preview = previewState.report, canApply else { return }
        isApplying = true
        failure = nil
        result = nil
        let applyResult = await BatchChangeCategoryAction.apply(
            repoPath: repoPath,
            fileIDs: fileIDs,
            preview: preview,
            changer: changer,
            errorMapper: errorMapper
        )
        result = applyResult.report
        failure = applyResult.failure
        isApplying = false
        if let report = applyResult.report, report.shouldRefreshConsumerAfterApply {
            onApplied(report)
        }
        if let report = applyResult.report, report.shouldCloseSheetAfterApply {
            onClose()
        }
    }

    @MainActor
    func acceptCreatedCategory(_ category: String) async {
        createdCategories = BatchChangeCategoryCreatedCategoryReturn.updatedCategories(
            createdCategories,
            savedCategory: category
        )
        targetCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        await refreshPreview()
    }

    private var canApply: Bool {
        BatchChangeCategoryValidation.canApply(
            targetCategory: targetCategory,
            moveRepoOwnedFiles: moveRepoOwnedFiles,
            fileIDs: fileIDs,
            preview: previewState.report,
            disabledReason: disabledReason,
            isApplying: isApplying
        )
    }

    private var previewTaskKey: String {
        "\(fileIDs.map(String.init).joined(separator: ","))|\(targetCategory)|\(moveRepoOwnedFiles)"
    }

    private var availableCategories: [String] {
        BatchChangeCategorySelection.availableCategories(
            selectedFiles: selectedFiles,
            categoryRows: categoryRows,
            createdCategories: createdCategories
        )
    }

    private var currentCategoriesText: String {
        BatchChangeCategorySelection.categoryDistributionText(selectedFiles: selectedFiles)
    }
}

private struct BatchChangeCategoryPreviewTable: View {
    let items: [BatchCategoryPreviewItemSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                Text(rowText(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func rowText(_ item: BatchCategoryPreviewItemSnapshot) -> String {
        let source = item.currentPath ?? "File \(item.fileID)"
        let target = item.targetPath ?? item.toCategory
        let reason = item.reason.map { " - \($0)" } ?? ""
        return "\(source) -> \(target): \(item.status.rawValue)\(reason)"
    }
}
