import SwiftUI

struct BatchChangeCategoryTrigger: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let categoryRows: [RepositorySidebarRowSnapshot]
    let changer: any CoreBatchCategoryChanging
    let undoStore: any CoreUndoActionLogging
    let errorMapper: any CoreErrorMapping
    let initialTargetCategory: String? = nil
    let acceptedCreatedCategory: String? = nil
    let onApplied: (BatchCategoryChangeReportSnapshot) -> Void
    let onUndoStateChange: (BatchTagUndoState) -> Void
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
                    undoStore: undoStore,
                    errorMapper: errorMapper,
                    initialTargetCategory: initialTargetCategory,
                    acceptedCreatedCategory: acceptedCreatedCategory,
                    onApplied: onApplied,
                    onUndoStateChange: onUndoStateChange,
                    onCreateNewCategory: { handoff in
                        isPresented = false
                        onCreateNewCategory(handoff)
                    },
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
    let undoStore: any CoreUndoActionLogging
    let errorMapper: any CoreErrorMapping
    let initialTargetCategory: String?
    let acceptedCreatedCategory: String?
    let onApplied: (BatchCategoryChangeReportSnapshot) -> Void
    let onUndoStateChange: (BatchTagUndoState) -> Void
    let onCreateNewCategory: (BatchChangeCategoryNewCategoryHandoff) -> Void
    let onClose: () -> Void
    @State var targetCategory: String
    @State var createdCategories: [String] = []
    @State var moveRepoOwnedFiles = false
    @State var previewState: BatchChangeCategoryPreviewState = .idle
    @State var isApplying = false
    @State var result: BatchCategoryChangeReportSnapshot?
    @State var failure: CoreErrorMappingSnapshot?
    @State var showsDetails = false
    @State var categorySearchText = ""

    init(
        repoPath: String,
        fileIDs: [Int64],
        selectedFiles: [FileEntrySnapshot],
        selectedCount: Int,
        disabledReason: String?,
        categoryRows: [RepositorySidebarRowSnapshot],
        changer: any CoreBatchCategoryChanging,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping,
        initialTargetCategory: String? = nil,
        acceptedCreatedCategory: String? = nil,
        onApplied: @escaping (BatchCategoryChangeReportSnapshot) -> Void,
        onUndoStateChange: @escaping (BatchTagUndoState) -> Void,
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
        self.undoStore = undoStore
        self.errorMapper = errorMapper
        self.initialTargetCategory = BatchChangeCategoryCreatedCategoryReturn
            .normalizedCategory(initialTargetCategory)
        self.acceptedCreatedCategory = BatchChangeCategoryCreatedCategoryReturn
            .normalizedCategory(acceptedCreatedCategory)
        self.onApplied = onApplied
        self.onUndoStateChange = onUndoStateChange
        self.onCreateNewCategory = onCreateNewCategory
        self.onClose = onClose
        _targetCategory = State(initialValue: self.initialTargetCategory ??
            BatchChangeCategorySelection.defaultTargetCategory(
                selectedFiles: selectedFiles,
                categoryRows: categoryRows
            ))
        _createdCategories = State(initialValue: self.acceptedCreatedCategory.map { [$0] } ?? [])
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
        .task(id: acceptedCreatedCategory) {
            guard let acceptedCreatedCategory else { return }
            await acceptCreatedCategory(acceptedCreatedCategory)
        }
    }

    @MainActor
    func refreshPreview(expandDetails: Bool = false) async {
        guard selectedCount > 0, disabledReason == nil, !targetCategory.isEmpty else { return }
        let previous = previewState.report
        previewState = .loading(previous: previous)
        failure = nil
        result = nil
        previewState = await BatchChangeCategoryAction.preview(
            request: BatchChangeCategoryPreviewRequest(
                repoPath: repoPath,
                fileIDs: fileIDs,
                targetCategory: targetCategory,
                moveRepoOwnedFiles: moveRepoOwnedFiles
            ),
            changer: changer,
            errorMapper: errorMapper
        )
        if expandDetails {
            showsDetails = BatchChangeCategoryPreviewDisclosure.shouldShowDetails(
                after: previewState,
                expandDetails: expandDetails
            )
        }
    }

    @MainActor
    func apply() async {
        guard let preview = previewState.report, canApply else { return }
        isApplying = true
        failure = nil
        result = nil
        onUndoStateChange(.idle)
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
        let undoState = await BatchChangeCategoryUndoAction.stateAfterBatchApply(
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
    func acceptCreatedCategory(_ category: String) async {
        createdCategories = BatchChangeCategoryCreatedCategoryReturn.updatedCategories(
            createdCategories,
            savedCategory: category
        )
        targetCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        await refreshPreview()
    }

    var canApply: Bool {
        BatchChangeCategoryValidation.canApply(BatchChangeCategoryApplyGate(
            targetCategory: targetCategory,
            moveRepoOwnedFiles: moveRepoOwnedFiles,
            fileIDs: fileIDs,
            preview: previewState.report,
            disabledReason: disabledReason,
            isApplying: isApplying
        ))
    }

    private var previewTaskKey: String {
        "\(fileIDs.map(String.init).joined(separator: ","))|\(targetCategory)|\(moveRepoOwnedFiles)"
    }

    var availableCategories: [String] {
        BatchChangeCategorySelection.availableCategories(
            selectedFiles: selectedFiles,
            categoryRows: categoryRows,
            createdCategories: createdCategories
        )
    }

    var filteredCategories: [String] {
        BatchChangeCategorySelection.filteredCategories(
            availableCategories,
            query: categorySearchText
        )
    }

    var currentCategoriesText: String {
        BatchChangeCategorySelection.categoryDistributionText(selectedFiles: selectedFiles)
    }
}

struct BatchChangeCategoryPicker: View {
    let categories: [String]
    let filteredCategories: [String]
    @Binding var selection: String
    @Binding var searchText: String
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New category")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search categories", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .disabled(isDisabled)
                .accessibilityIdentifier("S2-12-new-category-search")
            pickerBody
        }
    }

    @ViewBuilder
    private var pickerBody: some View {
        if filteredCategories.isEmpty {
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("S2-12-new-category-empty-search")
        } else {
            Picker("New category", selection: $selection) {
                ForEach(filteredCategories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.menu)
            .disabled(isDisabled)
            .accessibilityIdentifier("S2-12-new-category-picker")
        }
    }

    private var emptyMessage: String {
        categories.isEmpty ? "No categories available" : "No matching categories"
    }
}

struct BatchChangeCategoryPreviewTable: View {
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
