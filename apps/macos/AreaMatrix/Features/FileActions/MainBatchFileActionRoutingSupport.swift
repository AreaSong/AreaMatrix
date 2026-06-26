import SwiftUI

extension MainRepositoryContentView {
    func batchAddTagsRoutingSheet(_ route: BatchAddTagsRoute) -> some View {
        BatchAddTagsSheet(
            repoPath: opening.config.repoPath,
            fileIDs: route.fileIDs,
            selectedCount: route.selectedCount,
            disabledReason: route.disabledReason,
            tagStore: fileListModel.tagStore,
            undoStore: fileListModel.undoActionStore,
            errorMapper: fileListModel.errorMapper,
            onUndoStateChange: updateBatchTagUndoState,
            onClose: { pendingBatchAddTagsRoute = nil }
        )
    }

    func batchChangeCategoryRoutingSheet(_ route: BatchChangeCategoryRoute) -> some View {
        BatchChangeCategorySheet(
            repoPath: opening.config.repoPath,
            fileIDs: route.fileIDs,
            selectedFiles: route.selectedFiles,
            selectedCount: route.selectedCount,
            disabledReason: route.disabledReason,
            categoryRows: repositoryTree.sidebarRows,
            changer: fileListModel.batchCategoryChanger,
            undoStore: fileListModel.undoActionStore,
            errorMapper: fileListModel.errorMapper,
            initialTargetCategory: route.initialTargetCategory,
            acceptedCreatedCategory: route.acceptedCreatedCategory,
            onApplied: applyBatchCategoryChangeResult,
            onUndoStateChange: updateBatchTagUndoState,
            onCreateNewCategory: { openClassifierRuleEditorFromBatchCategory($0, route: route) },
            onClose: { pendingBatchChangeCategoryRoute = nil }
        )
    }

    func batchDeleteRoutingSheet(_ route: BatchDeleteRoute) -> some View {
        BatchDeleteConfirmSheet(
            repoPath: opening.config.repoPath,
            fileIDs: route.fileIDs,
            selectedFiles: route.selectedFiles,
            selectedCount: route.selectedCount,
            disabledReason: route.disabledReason,
            deleter: fileListModel.batchDeleter,
            undoStore: fileListModel.undoActionStore,
            errorMapper: fileListModel.errorMapper,
            onApplied: applyBatchDeleteResult,
            onUndoStateChange: updateBatchTagUndoState,
            onClose: { pendingBatchDeleteRoute = nil }
        )
    }

    func batchRenameRoutingSheet(_ route: BatchRenameRoute) -> some View {
        BatchRenameSheet(
            repoPath: opening.config.repoPath,
            fileIDs: route.fileIDs,
            selectedFiles: route.selectedFiles,
            selectedCount: route.selectedCount,
            disabledReason: route.disabledReason,
            renamer: batchRenamer,
            undoStore: fileListModel.undoActionStore,
            errorMapper: fileListModel.errorMapper,
            onApplied: applyBatchRenameResult,
            onUndoStateChange: updateBatchTagUndoState,
            onClose: { pendingBatchRenameRoute = nil }
        )
    }

    func openBatchAddTagsRoute(_ ids: Set<Int64>, source: BatchAddTagsRouteSource) {
        let selectedFiles = filesForBatchAddTags(ids)
        pendingBatchAddTagsRoute = BatchAddTagsRoute(
            source: source,
            fileIDs: selectedFiles.map(\.id),
            selectedCount: selectedFiles.count,
            disabledReason: batchAddTagsDisabledReason(for: selectedFiles)
        )
    }

    func openBatchChangeCategoryRoute(_ ids: Set<Int64>, source: BatchChangeCategoryRouteSource) {
        let selectedFiles = filesForBatchChangeCategory(ids)
        pendingBatchChangeCategoryRoute = BatchChangeCategoryRoute(
            source: source,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchChangeCategoryDisabledReason(for: selectedFiles)
        )
    }

    func openBatchDeleteRoute(_ ids: Set<Int64>, source: BatchDeleteRouteSource) {
        let selectedFiles = filesForBatchDelete(ids)
        pendingBatchDeleteRoute = BatchDeleteRoute(
            source: source,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchDeleteDisabledReason(for: selectedFiles)
        )
    }

    func openBatchRenameRoute(_ ids: Set<Int64>, source: BatchRenameRouteSource) {
        let selectedFiles = filesForBatchRename(ids)
        pendingBatchRenameRoute = BatchRenameRoute(
            source: source,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchRenameDisabledReason(for: selectedFiles)
        )
    }

    func commandPaletteBatchAddTagsRoute() -> BatchAddTagsRoute {
        let selectedFiles = filesForBatchAddTags(selectedFileIDs)
        return BatchAddTagsRoute(
            source: .commandPalette,
            fileIDs: selectedFiles.map(\.id),
            selectedCount: selectedFiles.count,
            disabledReason: batchAddTagsDisabledReason(for: selectedFiles)
        )
    }

    func commandPaletteBatchChangeCategoryRoute() -> BatchChangeCategoryRoute {
        let selectedFiles = filesForBatchChangeCategory(selectedFileIDs)
        return BatchChangeCategoryRoute(
            source: .commandPalette,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchChangeCategoryDisabledReason(for: selectedFiles)
        )
    }

    func applyBatchCategoryChangeResult(_ report: BatchCategoryChangeReportSnapshot) {
        Task {
            if !report.updatedFiles.isEmpty {
                fileListModel.files = fileListModel.files.map { current in
                    report.updatedFiles.first { $0.id == current.id } ?? current
                }
            }
            await fileListModel.retryCurrentCategory()
            let changedCount = report.movedCount + report.metadataOnlyCount
            fileListModel.statusBanner = .changedBatchCategory(count: changedCount, category: report.targetCategory)
        }
    }

    func applyBatchDeleteResult(_ report: BatchDeleteReportSnapshot) {
        Task {
            selectedFileIDs.subtract(report.affectedFileIDs)
            await fileListModel.retryCurrentCategory()
            await fileListModel.retrySelectedFileDetail()
            fileListModel.statusBanner = .batchDeleted(count: report.successfulDeleteCount)
        }
    }

    func applyBatchRenameResult(_ report: BatchRenameReportSnapshot) {
        Task {
            if !report.updatedFiles.isEmpty {
                fileListModel.files = fileListModel.files.map { current in
                    report.updatedFiles.first { $0.id == current.id } ?? current
                }
            }
            await fileListModel.retryCurrentCategory()
            await fileListModel.retrySelectedFileDetail()
        }
    }

    func openClassifierRuleEditorFromBatchCategory(
        _ handoff: BatchChangeCategoryNewCategoryHandoff,
        route: BatchChangeCategoryRoute
    ) {
        guard handoff.targetPageID == "classifier-rule-editor" else { return }
        pendingBatchChangeCategoryRoute = nil
        let context = BatchChangeCategoryReturnContext(route: route, handoff: handoff)
        fileListModel.openClassifierRuleEditorForBatchCategory(context: context)
    }

    func cancelClassifierRuleEditorFromBatchCategory(_ context: BatchChangeCategoryReturnContext) {
        pendingBatchChangeCategoryRoute = BatchChangeCategoryClassifierReturn.cancelledRoute(context: context)
        fileListModel.clearPendingSearchDestination()
    }

    func acceptClassifierRuleEditorCategory(
        _ category: String,
        context: BatchChangeCategoryReturnContext
    ) {
        let notification = ClassifierRuleEditorSaveEvents.notification(savedCategory: category)
        guard let route = BatchChangeCategoryClassifierReturn.acceptedRoute(
            notification: notification,
            context: context
        )
        else { return }
        pendingBatchChangeCategoryRoute = route
        fileListModel.clearPendingSearchDestination()
    }

    private func filesForBatchAddTags(_ ids: Set<Int64>) -> [FileEntrySnapshot] {
        selectedVisibleFiles(ids)
    }

    private func filesForBatchChangeCategory(_ ids: Set<Int64>) -> [FileEntrySnapshot] {
        selectedVisibleFiles(ids)
    }

    private func filesForBatchDelete(_ ids: Set<Int64>) -> [FileEntrySnapshot] {
        selectedVisibleFiles(ids)
    }

    private func filesForBatchRename(_ ids: Set<Int64>) -> [FileEntrySnapshot] {
        selectedVisibleFiles(ids)
    }

    private func selectedVisibleFiles(_ ids: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { ids.contains($0.id) }
    }

    private func batchAddTagsDisabledReason(for files: [FileEntrySnapshot]) -> String? {
        BatchAddTagsEntryPolicy.disabledReason(
            selectedFiles: files,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }

    private func batchChangeCategoryDisabledReason(for files: [FileEntrySnapshot]) -> String? {
        BatchChangeCategoryEntryPolicy.disabledReason(
            selectedFiles: files,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }

    private func batchDeleteDisabledReason(for files: [FileEntrySnapshot]) -> String? {
        BatchDeleteEntryPolicy.disabledReason(
            selectedFiles: files,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }

    private func batchRenameDisabledReason(for files: [FileEntrySnapshot]) -> String? {
        BatchRenameEntryPolicy.disabledReason(
            selectedFiles: files,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }
}

enum CommandPaletteBatchRouteBuilder {
    static func batchDeleteRoute(
        selectedFileIDs: Set<Int64>,
        visibleFiles: [FileEntrySnapshot],
        isReadOnly: Bool,
        isLoading: Bool,
        writeLockedFileIDs: Set<Int64>
    ) -> BatchDeleteRoute {
        let files = selectedFiles(selectedFileIDs, visibleFiles: visibleFiles)
        return BatchDeleteRoute(
            source: .commandPalette,
            fileIDs: files.map(\.id),
            selectedFiles: files,
            selectedCount: files.count,
            disabledReason: BatchDeleteEntryPolicy.disabledReason(
                selectedFiles: files,
                isReadOnly: isReadOnly,
                isLoading: isLoading,
                writeLockedFileIDs: writeLockedFileIDs
            )
        )
    }

    static func batchRenameRoute(
        selectedFileIDs: Set<Int64>,
        visibleFiles: [FileEntrySnapshot],
        isReadOnly: Bool,
        isLoading: Bool,
        writeLockedFileIDs: Set<Int64>
    ) -> BatchRenameRoute {
        let files = selectedFiles(selectedFileIDs, visibleFiles: visibleFiles)
        return BatchRenameRoute(
            source: .commandPalette,
            fileIDs: files.map(\.id),
            selectedFiles: files,
            selectedCount: files.count,
            disabledReason: BatchRenameEntryPolicy.disabledReason(
                selectedFiles: files,
                isReadOnly: isReadOnly,
                isLoading: isLoading,
                writeLockedFileIDs: writeLockedFileIDs
            )
        )
    }

    private static func selectedFiles(
        _ selectedFileIDs: Set<Int64>,
        visibleFiles: [FileEntrySnapshot]
    ) -> [FileEntrySnapshot] {
        visibleFiles.filter { selectedFileIDs.contains($0.id) }
    }
}
