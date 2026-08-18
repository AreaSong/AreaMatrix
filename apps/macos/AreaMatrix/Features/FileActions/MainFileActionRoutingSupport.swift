import SwiftUI

extension MainRepositoryContentView {
    func applyMainRepositoryPrimaryFileActionSheet(to content: some View) -> some View {
        content.sheet(item: actionDestinationBinding, content: actionRoutingSheet)
    }

    var actionDestinationBinding: Binding<MainFileActionDestination?> {
        Binding(
            get: { fileActionCoordinator.destination },
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
            renameState: fileActionCoordinator.renameState,
            deleteState: fileActionCoordinator.deleteState,
            changeCategoryState: fileActionCoordinator.changeCategoryState,
            classifierCorrectionContextState: fileActionCoordinator.classifierCorrectionContextState,
            iCloudConflictResolutionState: syncConflictCoordinator.resolutionState,
            iCloudConflictResolutionCapability: syncConflictCoordinator.resolver.iCloudConflictResolutionCapability,
            repoPath: opening.config.repoPath,
            isTrashAvailable: systemCapabilityChecker.isTrashAvailable(),
            aiDependencies: aiDependencies,
            iCloudConflictPathValidator: fileActionsDependencies.repositoryPathValidator,
            iCloudConflictReviewer: fileActionsDependencies.iCloudConflictReviewer,
            iCloudConflictErrorMapper: fileListModel.errorMapper,
            classifierRuleSaver: fileActionsDependencies.classifierRuleSaver,
            classifierImpactPreviewer: fileActionsDependencies.classifierImpactPreviewer,
            onDismiss: fileListModel.clearPendingActionDestination,
            onRename: submitRename,
            onShowExistingFile: showExistingFile,
            onPreviewChangeCategory: previewChangeCategory,
            onLoadClassifierCorrectionContext: loadClassifierCorrectionContext,
            onChangeCategory: submitChangeCategory,
            onApplyAIClassificationSuggestion: submitAIClassificationSuggestion,
            onBeginClassifierRuleHandoff: beginClassifierRuleHandoff,
            onRenameFirstFromChangeCategory: { fileID, targetCategory in
                fileListModel.beginRenameFromChangeCategory(fileID: fileID, targetCategory: targetCategory)
            },
            onEditClassifierRule: fileActionCoordinator.beginClassifierRuleSave,
            onPreviewClassifierRuleImpact: fileActionCoordinator.beginClassifierImpactPreview,
            onClassifierRuleSaved: completeClassifierRuleSave,
            onOpenChangeCategoryPermissionRecovery: onOpenChangeCategoryPermissionRecovery,
            onBeginAIClassificationChange: fileListModel.beginAIClassificationChange,
            onCancelClassifierRuleRoute: fileActionCoordinator.cancelClassifierRuleRoute,
            onOpenAIRecoverySettings: onOpenAISettings,
            onDelete: submitDelete,
            onApplyICloudConflict: applyICloudConflict,
            onCollectDiagnostics: fileListModel.currentListDiagnostics.requestCollection
        )
    }

    private func submitRename(fileID: Int64, newName: String) {
        Task {
            let didRename = await fileListModel.submitRename(fileID: fileID, newName: newName)
            if didRename { refreshLatestUndoToast() }
        }
    }

    private func showExistingFile(fileID: Int64) {
        selectionModel.fileIDs = [fileID]
        fileListModel.clearPendingActionDestination()
        Task { await fileListModel.selectFiles([fileID]) }
    }

    private func previewChangeCategory(fileID: Int64, targetCategory: String) {
        guard fileListModel.canPerformWriteAction(fileID: fileID) else { return }
        Task { await fileActionCoordinator.loadMoveToCategoryPreview(fileID: fileID, targetCategory: targetCategory) }
    }

    private func loadClassifierCorrectionContext(fileID: Int64, filename: String) {
        guard fileListModel.canPerformWriteAction(fileID: fileID) else { return }
        Task { await fileActionCoordinator.loadClassifierCorrectionContext(fileID: fileID, filename: filename) }
    }

    private func beginClassifierRuleHandoff(
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        destination: ClassifierRuleHandoffDestination
    ) {
        guard fileListModel.canPerformWriteAction(fileID: fileID),
              let file = fileListModel.actionRoutingFile(for: fileID) else { return }
        fileActionCoordinator.beginClassifierRuleHandoff(
            file: file,
            targetCategory: targetCategory,
            moveFile: moveFile,
            destination: destination
        )
    }

    private func completeClassifierRuleSave(_ savedRule: ClassifierRuleSnapshot) {
        fileActionCoordinator.completeClassifierRuleSave(savedRule)
        fileListModel.statusBanner = .savedClassifierRule(category: savedRule.targetCategory)
    }

    private func submitChangeCategory(
        fileID: Int64,
        targetCategory: String,
        mode: MainFileCategoryMoveMode,
        options: MainFileCategoryMoveOptions
    ) {
        guard fileListModel.canPerformWriteAction(fileID: fileID) else { return }
        Task {
            guard let outcome = await fileActionCoordinator.submitMoveToCategory(
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
            ) else { return }
            await fileListModel.applyCategoryMoveOutcome(outcome)
            refreshLatestUndoToast()
        }
    }

    private func submitAIClassificationSuggestion(_ request: AIClassificationSuggestionApplyRequest) {
        guard fileListModel.canPerformWriteAction(fileID: request.fileID) else { return }
        Task {
            guard let outcome = await fileActionCoordinator.submitAIClassificationSuggestion(request) else { return }
            await fileListModel.applyAIClassificationOutcome(outcome, request: request)
            refreshLatestUndoToast()
        }
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
