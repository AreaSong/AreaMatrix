import Foundation

enum BatchChangeCategoryRouteSource: String, Equatable {
    case detailMulti
    case listContextMenu
    case commandPalette
}

struct BatchChangeCategoryRoute: Identifiable, Equatable {
    let source: BatchChangeCategoryRouteSource
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let initialTargetCategory: String?
    let acceptedCreatedCategory: String?

    init(
        source: BatchChangeCategoryRouteSource,
        fileIDs: [Int64],
        selectedFiles: [FileEntrySnapshot],
        selectedCount: Int,
        disabledReason: String?,
        initialTargetCategory: String? = nil,
        acceptedCreatedCategory: String? = nil
    ) {
        self.source = source
        self.fileIDs = fileIDs
        self.selectedFiles = selectedFiles
        self.selectedCount = selectedCount
        self.disabledReason = disabledReason
        self.initialTargetCategory = BatchChangeCategoryCreatedCategoryReturn
            .normalizedCategory(initialTargetCategory)
        self.acceptedCreatedCategory = BatchChangeCategoryCreatedCategoryReturn
            .normalizedCategory(acceptedCreatedCategory)
    }

    var id: String {
        [
            source.rawValue,
            fileIDs.map(String.init).joined(separator: ","),
            "\(selectedCount)",
            disabledReason ?? "",
            initialTargetCategory ?? "",
            acceptedCreatedCategory ?? ""
        ].joined(separator: ":")
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
    var sourcePageID: String = "S2-12"
    var targetPageID: String = "S2-19"
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

    static func acceptedRoute(
        notification: Notification,
        context: BatchChangeCategoryReturnContext
    ) -> BatchChangeCategoryRoute? {
        guard let category = ClassifierRuleEditorSaveEvents.savedCategory(from: notification) else {
            return nil
        }
        return acceptedRoute(category: category, context: context)
    }
}

enum ClassifierRuleEditorSaveEvents {
    static let savedCategoryNotification = Notification.Name(
        "AreaMatrixClassifierRuleEditorSavedCategory"
    )
    static let categoryUserInfoKey = "savedCategory"

    static func savedCategory(from notification: Notification) -> String? {
        BatchChangeCategoryCreatedCategoryReturn.normalizedCategory(
            notification.userInfo?[categoryUserInfoKey] as? String
        )
    }

    static func notification(savedCategory: String) -> Notification {
        Notification(
            name: savedCategoryNotification,
            object: nil,
            userInfo: [categoryUserInfoKey: savedCategory]
        )
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
        disabledReason.map { "\($0). You can still preview selected files and category impact." } ??
            "Change category for the selected files"
    }

    static func disabledReason(
        selectedFiles: [FileEntrySnapshot],
        isReadOnly: Bool,
        isLoading: Bool,
        writeLockedFileIDs: Set<Int64>
    ) -> String? {
        if selectedFiles.isEmpty { return "No files selected" }
        if isReadOnly { return MainFileWriteActionDisabledReason.repoReadOnly.rawValue }
        if isLoading { return MainFileWriteActionDisabledReason.listLoading.rawValue }
        if selectedFiles.contains(where: { writeLockedFileIDs.contains($0.id) }) {
            return MainFileWriteActionDisabledReason.importLocked.rawValue
        }
        return nil
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
            return await .failed(mapError(error, errorMapper: errorMapper), previous: nil)
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
                failure: mapError(error, errorMapper: errorMapper)
            )
        }
    }

    private static func mapError(_ error: Error, errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
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

struct BatchCategoryPreviewReportPresentation: Equatable {
    var moveSummaryText: String
    var metadataSummaryText: String
    var skippedSummaryText: String
    var blockedSummaryText: String

    init(report: BatchCategoryPreviewReportSnapshot) {
        moveSummaryText = "\(Self.fileText(report.willMoveCount)) will move"
        metadataSummaryText = "\(Self.fileText(report.metadataOnlyCount)) will update only"
        skippedSummaryText = "\(Self.fileText(report.skippedCount)) cannot move"
        blockedSummaryText = "\(Self.fileText(report.blockedCount)) blocked"
    }

    private static func fileText(_ count: Int64) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }
}

struct BatchCategoryChangeReportPresentation: Equatable {
    var changedSummaryText: String
    var skippedSummaryText: String
    var failedSummaryText: String

    init(report: BatchCategoryChangeReportSnapshot) {
        let changed = report.movedCount + report.metadataOnlyCount
        changedSummaryText = "\(Self.fileText(changed)) changed"
        skippedSummaryText = "\(Self.fileText(report.skippedCount + report.unchangedCount)) skipped or unchanged"
        failedSummaryText = "\(Self.fileText(report.failedCount)) failed"
    }

    private static func fileText(_ count: Int64) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }
}
