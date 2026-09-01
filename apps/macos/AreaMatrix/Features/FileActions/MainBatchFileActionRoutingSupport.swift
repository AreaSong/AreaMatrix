import AreaMatrixFeatureOperation
import SwiftUI

extension MainRepositoryContentView {
    func applyMainRepositoryBatchFileActionSheets(to content: some View) -> some View {
        content
            .sheet(item: $fileActionCoordinator.routingState.batchAddTagsRoute, content: batchAddTagsRoutingSheet)
            .sheet(
                item: $fileActionCoordinator.routingState.batchChangeCategoryRoute,
                content: batchChangeCategoryRoutingSheet
            )
            .sheet(item: $fileActionCoordinator.routingState.batchDeleteRoute, content: batchDeleteRoutingSheet)
            .sheet(item: $fileActionCoordinator.routingState.batchRenameRoute, content: batchRenameRoutingSheet)
            .sheet(item: $fileActionCoordinator.routingState.undoHistoryRequest, content: undoHistorySheet)
    }

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
            onClose: { fileActionCoordinator.routingState.batchAddTagsRoute = nil }
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
            onClose: { fileActionCoordinator.routingState.batchChangeCategoryRoute = nil }
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
            onClose: { fileActionCoordinator.routingState.batchDeleteRoute = nil }
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
            onClose: { fileActionCoordinator.routingState.batchRenameRoute = nil }
        )
    }

    func openBatchAddTagsRoute(_ ids: Set<Int64>, source: MainFileBatchActionRouteSource) {
        let context = batchActionRouteContext(ids)
        fileActionCoordinator.routingState.batchAddTagsRoute = BatchFileActionRouteBuilder.batchAddTagsRoute(
            source: source,
            context: context
        )
    }

    func openBatchChangeCategoryRoute(_ ids: Set<Int64>, source: MainFileBatchActionRouteSource) {
        let context = batchActionRouteContext(ids)
        fileActionCoordinator.routingState.batchChangeCategoryRoute = BatchFileActionRouteBuilder
            .batchChangeCategoryRoute(
                source: source,
                context: context
            )
    }

    func openBatchDeleteRoute(_ ids: Set<Int64>, source: MainFileBatchActionRouteSource) {
        let context = batchActionRouteContext(ids)
        fileActionCoordinator.routingState.batchDeleteRoute = BatchFileActionRouteBuilder.batchDeleteRoute(
            source: source,
            context: context
        )
    }

    func openBatchRenameRoute(_ ids: Set<Int64>, source: MainFileBatchActionRouteSource) {
        let context = batchActionRouteContext(ids)
        fileActionCoordinator.routingState.batchRenameRoute = BatchFileActionRouteBuilder.batchRenameRoute(
            source: source,
            context: context
        )
    }

    func commandPaletteBatchAddTagsRoute() -> BatchAddTagsRoute {
        let context = batchActionRouteContext(selectionModel.fileIDs)
        return BatchFileActionRouteBuilder.commandPaletteBatchAddTagsRoute(context: context)
    }

    func commandPaletteBatchChangeCategoryRoute() -> BatchChangeCategoryRoute {
        let context = batchActionRouteContext(selectionModel.fileIDs)
        return BatchFileActionRouteBuilder.commandPaletteBatchChangeCategoryRoute(context: context)
    }

    func commandPaletteBatchDeleteRoute() -> BatchDeleteRoute {
        let context = batchActionRouteContext(selectionModel.fileIDs)
        return BatchFileActionRouteBuilder.commandPaletteBatchDeleteRoute(context: context)
    }

    func commandPaletteBatchRenameRoute() -> BatchRenameRoute {
        let context = batchActionRouteContext(selectionModel.fileIDs)
        return BatchFileActionRouteBuilder.commandPaletteBatchRenameRoute(context: context)
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
            selectionModel.fileIDs.subtract(report.affectedFileIDs)
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
        fileActionCoordinator.routingState.batchChangeCategoryRoute = nil
        let context = BatchChangeCategoryReturnContext(route: route, handoff: handoff)
        fileListModel.openClassifierRuleEditorForBatchCategory(context: context)
    }

    func cancelClassifierRuleEditorFromBatchCategory(_ context: BatchChangeCategoryReturnContext) {
        fileActionCoordinator.routingState.batchChangeCategoryRoute = BatchChangeCategoryClassifierReturn
            .cancelledRoute(
                context: context
            )
        searchModel.clearPendingSearchDestination()
    }

    func acceptClassifierRuleEditorCategory(
        _ category: String,
        context: BatchChangeCategoryReturnContext
    ) {
        guard let route = BatchChangeCategoryClassifierReturn.acceptedRoute(
            category: category,
            context: context
        )
        else { return }
        fileActionCoordinator.routingState.batchChangeCategoryRoute = route
        searchModel.clearPendingSearchDestination()
    }

    func batchActionRouteContext(_ ids: Set<Int64>) -> MainFileBatchActionRouteContext {
        MainFileBatchActionRouteContext(
            selectedFileIDs: ids,
            visibleFiles: mainListPresentation.visibleFiles,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }
}
