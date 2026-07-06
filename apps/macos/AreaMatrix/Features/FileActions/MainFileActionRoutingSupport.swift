import SwiftUI

extension MainRepositoryContentView {
    var actionDestinationBinding: Binding<MainFileActionDestination?> {
        Binding(
            get: { fileListModel.pendingActionDestination },
            set: { value in
                if value == nil {
                    fileListModel.clearPendingActionDestination()
                }
            }
        )
    }

    func actionRoutingSheet(_ destination: MainFileActionDestination) -> some View {
        MainFileActionRoutingSheet(
            destination: destination,
            file: fileListModel.actionRoutingFile(for: destination.fileID),
            candidateFiles: fileListModel.files,
            categoryRows: repositoryTree.sidebarRows,
            renameState: fileListModel.renameState,
            deleteState: fileListModel.deleteState,
            changeCategoryState: fileListModel.changeCategoryState,
            classifierCorrectionContextState: fileListModel.classifierCorrectionContextState,
            iCloudConflictResolutionState: fileListModel.iCloudConflictResolutionState,
            iCloudConflictResolutionCapability: fileListModel.iCloudConflictResolver.iCloudConflictResolutionCapability,
            repoPath: opening.config.repoPath,
            isTrashAvailable: systemCapabilityChecker.isTrashAvailable(),
            iCloudConflictPathValidator: AppCoreServices.repositoryPathValidator,
            iCloudConflictReviewer: AppCoreServices.iCloudConflictReviewer,
            iCloudConflictErrorMapper: fileListModel.errorMapper,
            onDismiss: fileListModel.clearPendingActionDestination,
            onRename: submitRename,
            onShowExistingFile: showExistingFile,
            onPreviewChangeCategory: previewChangeCategory,
            onLoadClassifierCorrectionContext: loadClassifierCorrectionContext,
            onChangeCategory: submitChangeCategory,
            onApplyAIClassificationSuggestion: submitAIClassificationSuggestion,
            onBeginClassifierRuleHandoff: fileListModel.beginClassifierRuleHandoff,
            onRenameFirstFromChangeCategory: { fileID, targetCategory in
                fileListModel.beginRenameFromChangeCategory(fileID: fileID, targetCategory: targetCategory)
            },
            onEditClassifierRule: fileListModel.beginClassifierRuleSave,
            onPreviewClassifierRuleImpact: fileListModel.beginClassifierImpactPreview,
            onClassifierRuleSaved: fileListModel.completeClassifierRuleSave,
            onOpenChangeCategoryPermissionRecovery: onOpenChangeCategoryPermissionRecovery,
            onBeginAIClassificationChange: fileListModel.beginAIClassificationChange,
            onCancelClassifierRuleRoute: fileListModel.cancelClassifierRuleRoute,
            onOpenAIRecoverySettings: onOpenAISettings,
            onDelete: submitDelete,
            onApplyICloudConflict: applyICloudConflict,
            onCollectDiagnostics: { Task { await fileListModel.collectCurrentListDiagnostics() } }
        )
    }

    private func submitRename(fileID: Int64, newName: String) {
        Task {
            let didRename = await fileListModel.submitRename(fileID: fileID, newName: newName)
            if didRename { refreshLatestUndoToast() }
        }
    }

    private func showExistingFile(fileID: Int64) {
        selectedFileIDs = [fileID]
        fileListModel.clearPendingActionDestination()
        Task { await fileListModel.selectFiles([fileID]) }
    }

    private func previewChangeCategory(fileID: Int64, targetCategory: String) {
        Task { await fileListModel.loadMoveToCategoryPreview(fileID: fileID, targetCategory: targetCategory) }
    }

    private func loadClassifierCorrectionContext(fileID: Int64, filename: String) {
        Task { await fileListModel.loadClassifierCorrectionContext(fileID: fileID, filename: filename) }
    }

    private func submitChangeCategory(
        fileID: Int64,
        targetCategory: String,
        mode: MainFileCategoryMoveMode,
        options: MainFileCategoryMoveOptions
    ) {
        Task {
            let didMove = await fileListModel.submitMoveToCategory(
                fileID: fileID,
                targetCategory: targetCategory,
                mode: mode,
                options: options,
                onMoved: { changedFile in
                    if mode == .classifierCorrection {
                        Task { await refreshAfterClassifierCorrection(changedFile) }
                    } else {
                        refreshAfterCategoryMove(changedFile)
                    }
                }
            )
            if didMove { refreshLatestUndoToast() }
        }
    }

    private func submitAIClassificationSuggestion(_ request: AIClassificationSuggestionApplyRequest) {
        Task { if await fileListModel.submitAIClassificationSuggestion(request) { refreshLatestUndoToast() } }
    }

    private func submitDelete(fileID: Int64, operation: MainFileDeleteOperation) {
        Task {
            let didDelete = await fileListModel.submitDelete(fileID: fileID, operation: operation)
            if didDelete { refreshLatestUndoToast() }
        }
    }

    private func applyICloudConflict(_ context: ICloudConflictApplyContext) {
        Task {
            let result = context.result
            if let report = result.report {
                await fileListModel.completePreviewedICloudConflictResolution(
                    fileID: context.fileID,
                    strategy: result.strategy,
                    report: report
                )
                return
            }
            if let failure = result.failure {
                fileListModel.recordICloudConflictResolutionFailure(
                    fileID: context.fileID,
                    strategy: result.strategy,
                    mapping: failure
                )
                return
            }
            await fileListModel.applyICloudConflictResolution(
                fileID: context.fileID,
                strategy: result.strategy,
                originalPath: context.originalPath,
                conflictedCopyPath: context.conflictedCopyPath
            )
        }
    }
}
