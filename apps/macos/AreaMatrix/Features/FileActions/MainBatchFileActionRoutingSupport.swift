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
        let context = batchActionRouteContext(ids)
        pendingBatchAddTagsRoute = BatchAddTagsRoute(source: source, context: context)
    }

    func openBatchChangeCategoryRoute(_ ids: Set<Int64>, source: BatchChangeCategoryRouteSource) {
        let context = batchActionRouteContext(ids)
        pendingBatchChangeCategoryRoute = BatchChangeCategoryRoute(source: source, context: context)
    }

    func openBatchDeleteRoute(_ ids: Set<Int64>, source: BatchDeleteRouteSource) {
        let context = batchActionRouteContext(ids)
        pendingBatchDeleteRoute = BatchDeleteRoute(source: source, context: context)
    }

    func openBatchRenameRoute(_ ids: Set<Int64>, source: BatchRenameRouteSource) {
        let context = batchActionRouteContext(ids)
        pendingBatchRenameRoute = BatchRenameRoute(source: source, context: context)
    }

    func commandPaletteBatchAddTagsRoute() -> BatchAddTagsRoute {
        let context = batchActionRouteContext(selectedFileIDs)
        return BatchAddTagsRoute(source: .commandPalette, context: context)
    }

    func commandPaletteBatchChangeCategoryRoute() -> BatchChangeCategoryRoute {
        let context = batchActionRouteContext(selectedFileIDs)
        return BatchChangeCategoryRoute(source: .commandPalette, context: context)
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

    func batchActionRouteContext(_ ids: Set<Int64>) -> MainFileBatchActionRouteContext {
        MainFileBatchActionRouteContext(
            selectedFileIDs: ids,
            visibleFiles: visibleFiles,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }
}

enum CommandPaletteBatchRouteBuilder {
    static func batchDeleteRoute(context: MainFileBatchActionRouteContext) -> BatchDeleteRoute {
        BatchDeleteRoute(source: .commandPalette, context: context)
    }

    static func batchRenameRoute(context: MainFileBatchActionRouteContext) -> BatchRenameRoute {
        BatchRenameRoute(source: .commandPalette, context: context)
    }
}
