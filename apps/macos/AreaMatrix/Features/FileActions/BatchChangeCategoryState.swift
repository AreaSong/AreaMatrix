import Foundation

struct BatchChangeCategoryRoute: Identifiable, Equatable {
    let source: MainFileBatchActionRouteSource
    private let payload: MainFileBatchActionRoutePayload
    let initialTargetCategory: String?
    let acceptedCreatedCategory: String?

    var fileIDs: [Int64] {
        payload.fileIDs
    }

    var selectedFiles: [FileEntrySnapshot] {
        payload.selectedFiles
    }

    var selectedCount: Int {
        payload.selectedCount
    }

    var disabledReason: String? {
        payload.disabledReason
    }

    init(
        source: MainFileBatchActionRouteSource,
        fileIDs: [Int64],
        selectedFiles: [FileEntrySnapshot],
        selectedCount: Int,
        disabledReason: String?,
        initialTargetCategory: String? = nil,
        acceptedCreatedCategory: String? = nil
    ) {
        self.source = source
        payload = MainFileBatchActionRoutePayload(
            fileIDs: fileIDs,
            selectedFiles: selectedFiles,
            selectedCount: selectedCount,
            disabledReason: disabledReason
        )
        self.initialTargetCategory = BatchChangeCategoryCreatedCategoryReturn
            .normalizedCategory(initialTargetCategory)
        self.acceptedCreatedCategory = BatchChangeCategoryCreatedCategoryReturn
            .normalizedCategory(acceptedCreatedCategory)
    }

    var id: String {
        (
            [source.rawValue] + payload.identityParts + [
                initialTargetCategory ?? "",
                acceptedCreatedCategory ?? ""
            ]
        ).joined(separator: ":")
    }

    func returningFromCategoryEditor(
        targetCategory: String?,
        acceptedCreatedCategory: String? = nil
    ) -> BatchChangeCategoryRoute {
        BatchChangeCategoryRoute(
            source: source,
            fileIDs: fileIDs,
            selectedFiles: selectedFiles,
            selectedCount: selectedCount,
            disabledReason: disabledReason,
            initialTargetCategory: targetCategory,
            acceptedCreatedCategory: acceptedCreatedCategory
        )
    }
}

extension BatchChangeCategoryRoute {
    init(
        source: MainFileBatchActionRouteSource,
        context: MainFileBatchActionRouteContext,
        initialTargetCategory: String? = nil,
        acceptedCreatedCategory: String? = nil
    ) {
        self.init(
            source: source,
            payload: MainFileBatchActionRoutePayload(context: context),
            initialTargetCategory: initialTargetCategory,
            acceptedCreatedCategory: acceptedCreatedCategory
        )
    }

    private init(
        source: MainFileBatchActionRouteSource,
        payload: MainFileBatchActionRoutePayload,
        initialTargetCategory: String? = nil,
        acceptedCreatedCategory: String? = nil
    ) {
        self.source = source
        self.payload = payload
        self.initialTargetCategory = BatchChangeCategoryCreatedCategoryReturn
            .normalizedCategory(initialTargetCategory)
        self.acceptedCreatedCategory = BatchChangeCategoryCreatedCategoryReturn
            .normalizedCategory(acceptedCreatedCategory)
    }
}

struct BatchChangeCategoryApplyResult: Equatable {
    var report: BatchCategoryChangeReportSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

struct BatchChangeCategoryPreviewRequest {
    var repoPath: String
    var fileIDs: [Int64]
    var targetCategory: String
    var moveRepoOwnedFiles: Bool
}

struct BatchChangeCategoryApplyGate {
    var targetCategory: String
    var moveRepoOwnedFiles: Bool
    var fileIDs: [Int64]
    var preview: BatchCategoryPreviewReportSnapshot?
    var disabledReason: String?
    var isApplying: Bool
}

enum BatchChangeCategoryUndoAction {
    static func stateAfterBatchApply(
        repoPath: String,
        report: BatchCategoryChangeReportSnapshot?,
        failure: CoreErrorMappingSnapshot?,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoState? {
        guard failure == nil, let report, report.shouldRefreshConsumerAfterApply else { return nil }
        guard let token = normalizedToken(report.undoToken) else {
            return .unavailable(reason: "Undo is unavailable for this result.")
        }

        let loadResult = await BatchTagUndoAction.loadAction(
            repoPath: repoPath,
            undoToken: token,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        return loadResult.toastState ?? .unavailable(reason: "Undo action is no longer available.")
    }

    private static func normalizedToken(_ undoToken: String?) -> String? {
        let token = undoToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }
}

struct BatchChangeCategoryNewCategoryHandoff: Equatable, Identifiable {
    var sourcePageID: String = "batch-change-category"
    var targetPageID: String = "classifier-rule-editor"
    var selectedFileIDs: [Int64]
    var currentTargetCategory: String

    var id: String {
        "\(sourcePageID)-\(targetPageID)-\(selectedFileIDs.map(String.init).joined(separator: ","))"
    }
}

struct BatchChangeCategoryReturnContext: Equatable {
    var route: BatchChangeCategoryRoute
    var handoff: BatchChangeCategoryNewCategoryHandoff

    func routeRestoringOriginalTarget() -> BatchChangeCategoryRoute {
        route.returningFromCategoryEditor(targetCategory: handoff.currentTargetCategory)
    }

    func routeSelectingCreatedCategory(_ category: String) -> BatchChangeCategoryRoute {
        route.returningFromCategoryEditor(
            targetCategory: category,
            acceptedCreatedCategory: category
        )
    }
}

enum BatchChangeCategoryClassifierReturn {
    static func cancelledRoute(
        context: BatchChangeCategoryReturnContext
    ) -> BatchChangeCategoryRoute {
        context.routeRestoringOriginalTarget()
    }

    static func acceptedRoute(
        category: String,
        context: BatchChangeCategoryReturnContext
    ) -> BatchChangeCategoryRoute? {
        guard let normalized = BatchChangeCategoryCreatedCategoryReturn.normalizedCategory(category) else {
            return nil
        }
        return context.routeSelectingCreatedCategory(normalized)
    }
}

enum BatchChangeCategoryPreviewState: Equatable {
    case idle
    case loading(previous: BatchCategoryPreviewReportSnapshot?)
    case loaded(BatchCategoryPreviewReportSnapshot)
    case failed(CoreErrorMappingSnapshot, previous: BatchCategoryPreviewReportSnapshot?)

    var report: BatchCategoryPreviewReportSnapshot? {
        switch self {
        case let .loaded(report), let .loading(report?), let .failed(_, report?):
            report
        case .idle, .loading, .failed:
            nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var failure: CoreErrorMappingSnapshot? {
        guard case let .failed(mapping, _) = self else { return nil }
        return mapping
    }
}

enum BatchChangeCategoryEntryPolicy {
    static func openHelp(disabledReason: String?) -> String {
        MainFileBatchEntryPolicy.openHelp(
            disabledReason: disabledReason,
            defaultHelp: "Change category for the selected files",
            blockedHelpSuffix: "You can still preview selected files and category impact."
        )
    }
}

enum BatchChangeCategorySelection {
    static func availableCategories(
        selectedFiles: [FileEntrySnapshot],
        categoryRows: [RepositorySidebarRowSnapshot],
        createdCategories: [String] = []
    ) -> [String] {
        let sidebarCategories = categoryRows.compactMap(\.categoryForFileList)
        let selectedCategories = selectedFiles.map(\.category)
        let normalizedCreated = createdCategories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(sidebarCategories + selectedCategories + normalizedCreated)).sorted()
    }

    static func defaultTargetCategory(
        selectedFiles: [FileEntrySnapshot],
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> String {
        let currentCategories = Set(selectedFiles.map(\.category))
        return availableCategories(selectedFiles: selectedFiles, categoryRows: categoryRows)
            .first { !currentCategories.contains($0) } ?? selectedFiles.first?.category ?? ""
    }

    static func categoryDistributionText(selectedFiles: [FileEntrySnapshot]) -> String {
        let counts = Dictionary(grouping: selectedFiles, by: \.category)
            .mapValues { Int64($0.count) }
        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .map { "\($0.key) (\($0.value))" }
            .joined(separator: ", ")
    }

    static func filteredCategories(_ categories: [String], query: String) -> [String] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return categories }
        return categories.filter {
            $0.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}

enum BatchChangeCategoryCreatedCategoryReturn {
    static func normalizedCategory(_ category: String?) -> String? {
        let normalized = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    static func updatedCategories(_ categories: [String], savedCategory: String) -> [String] {
        guard let normalized = normalizedCategory(savedCategory) else { return categories }
        return BatchChangeCategorySelection.availableCategories(
            selectedFiles: [],
            categoryRows: [],
            createdCategories: categories + [normalized]
        )
    }
}

enum BatchChangeCategoryPreviewDisclosure {
    static func shouldShowDetails(after state: BatchChangeCategoryPreviewState, expandDetails: Bool) -> Bool {
        expandDetails && state.report != nil
    }
}

enum BatchChangeCategoryAction {
    static func preview(
        request: BatchChangeCategoryPreviewRequest,
        changer: any CoreBatchCategoryChanging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchChangeCategoryPreviewState {
        do {
            let report = try await changer.previewBatchMoveToCategory(
                repoPath: request.repoPath,
                fileIDs: request.fileIDs,
                targetCategory: request.targetCategory,
                moveRepoOwnedFiles: request.moveRepoOwnedFiles
            )
            return .loaded(report)
        } catch {
            return await .failed(errorMapper.mapError(error), previous: nil)
        }
    }

    static func apply(
        repoPath: String,
        fileIDs: [Int64],
        preview: BatchCategoryPreviewReportSnapshot,
        changer: any CoreBatchCategoryChanging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchChangeCategoryApplyResult {
        do {
            let report = try await changer.batchMoveToCategory(
                repoPath: repoPath,
                fileIDs: fileIDs,
                targetCategory: preview.targetCategory,
                moveRepoOwnedFiles: preview.moveRepoOwnedFiles,
                previewToken: preview.previewToken
            )
            return BatchChangeCategoryApplyResult(report: report, failure: nil)
        } catch {
            return await BatchChangeCategoryApplyResult(
                report: nil,
                failure: errorMapper.mapError(error)
            )
        }
    }
}

enum BatchChangeCategoryValidation {
    static func canApply(_ gate: BatchChangeCategoryApplyGate) -> Bool {
        guard !gate.isApplying,
              gate.disabledReason == nil,
              !gate.targetCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !gate.fileIDs.isEmpty,
              let preview = gate.preview,
              preview.canApply else { return false }
        return preview.targetCategory == gate.targetCategory &&
            preview.moveRepoOwnedFiles == gate.moveRepoOwnedFiles &&
            preview.requestedFileCount == Int64(Set(gate.fileIDs).count) &&
            Set(preview.items.map(\.fileID)) == Set(gate.fileIDs)
    }
}

extension BatchCategoryChangeReportSnapshot {
    var successfulChangeCount: Int64 {
        movedCount + metadataOnlyCount
    }

    var shouldRefreshConsumerAfterApply: Bool {
        successfulChangeCount > 0 || !updatedFiles.isEmpty || undoToken != nil
    }

    var shouldCloseSheetAfterApply: Bool {
        failedCount == 0
    }
}
