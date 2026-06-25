import SwiftUI

struct MainFileActionRoutingSheet: View {
    let destination: MainFileActionDestination
    let file: FileEntrySnapshot?
    let candidateFiles: [FileEntrySnapshot]
    let categoryRows: [RepositorySidebarRowSnapshot]
    let renameState: MainFileRenameState
    let deleteState: MainFileDeleteState
    let changeCategoryState: MainFileCategoryMoveState
    let classifierCorrectionContextState: ClassifierCorrectionContextState
    let iCloudConflictResolutionState: ICloudConflictResolutionState
    let iCloudConflictResolutionCapability: ICloudConflictResolutionCapability
    let repoPath: String
    let isTrashAvailable: Bool
    let iCloudConflictPathValidator: any CoreRepositoryPathValidating
    let iCloudConflictReviewer: any CoreICloudConflictReviewing
    let iCloudConflictErrorMapper: any CoreErrorMapping
    let onDismiss: () -> Void
    let onRename: (Int64, String) -> Void
    let onShowExistingFile: (Int64) -> Void
    let onPreviewChangeCategory: (Int64, String) -> Void
    let onLoadClassifierCorrectionContext: (Int64, String) -> Void
    let onChangeCategory: (Int64, String, MainFileCategoryMoveMode, MainFileCategoryMoveOptions) -> Void
    let onApplyAIClassificationSuggestion: (AIClassificationSuggestionApplyRequest) -> Void
    let onBeginClassifierRuleHandoff: (Int64, String, Bool, ClassifierRuleHandoffDestination) -> Void
    let onRenameFirstFromChangeCategory: (Int64, String) -> Void
    let onEditClassifierRule: (ClassifierRuleHandoff) -> Void
    let onPreviewClassifierRuleImpact: (ClassifierRuleHandoff) -> Void
    let onClassifierRuleSaved: (ClassifierRuleSnapshot) -> Void
    let onOpenChangeCategoryPermissionRecovery: () -> Void
    let onBeginAIClassificationChange: (Int64, String?) -> Void
    let onCancelClassifierRuleRoute: () -> Void
    let onOpenAIRecoverySettings: () -> Void
    let onDelete: (Int64, MainFileDeleteOperation) -> Void
    let onApplyICloudConflict: (ICloudConflictApplyContext) -> Void
    let onCollectDiagnostics: () -> Void

    var body: some View {
        switch destination {
        case .rename:
            RenameFileSheet(
                file: file,
                candidateFiles: candidateFiles,
                state: renameState,
                onCancel: onDismiss,
                onRename: onRename,
                onShowExistingFile: onShowExistingFile
            )
        case .changeCategory:
            changeCategoryRouteView(destination)
        case .aiClassificationSuggestion:
            AIClassificationSuggestionRouteView(
                repoPath: repoPath,
                file: file,
                moveState: changeCategoryState,
                returnContext: destination.aiClassificationReturnContext,
                onCancel: onDismiss,
                onBeginChange: onBeginAIClassificationChange,
                onPreview: onPreviewChangeCategory,
                onApply: onApplyAIClassificationSuggestion,
                onOpenAIRecoverySettings: onOpenAIRecoverySettings
            )
        case .delete:
            DeleteFileConfirmSheet(
                file: file,
                operation: file.map(MainFileDeleteOperation.recommended),
                state: deleteState,
                isTrashAvailable: isTrashAvailable,
                onCancel: onDismiss,
                onConfirm: onDelete,
                onCollectDiagnostics: onCollectDiagnostics
            )
        case let .iCloudConflict(fileID):
            ICloudConflictMinimalSheet(
                model: ICloudConflictMinimalModel(
                    repoPath: repoPath,
                    conflictID: file?.path,
                    originalVersion: ICloudConflictVersionSnapshot.originalCandidate(repoPath: repoPath, file: file),
                    conflictedCopyVersion: ICloudConflictVersionSnapshot.conflictedCandidate(
                        repoPath: repoPath,
                        file: file
                    ),
                    pathValidator: iCloudConflictPathValidator,
                    conflictReviewer: iCloudConflictReviewer,
                    errorMapper: iCloudConflictErrorMapper
                ),
                resolutionState: iCloudConflictResolutionState,
                resolutionCapability: iCloudConflictResolutionCapability,
                isTrashAvailable: isTrashAvailable,
                onCancel: onDismiss,
                onApply: { result in
                    let original = ICloudConflictVersionSnapshot.originalCandidate(repoPath: repoPath, file: file).path
                    let conflicted = ICloudConflictVersionSnapshot.conflictedCandidate(repoPath: repoPath, file: file)
                        .path
                    onApplyICloudConflict(ICloudConflictApplyContext(
                        fileID: fileID,
                        result: result,
                        originalPath: original,
                        conflictedCopyPath: conflicted
                    ))
                },
                onCollectDiagnostics: {
                    onCollectDiagnostics()
                }
            )
        }
    }

    @ViewBuilder
    private func changeCategoryRouteView(_ destination: MainFileActionDestination) -> some View {
        if let ruleRoute = destination.classifierRuleRoute {
            classifierRuleRouteView(ruleRoute)
        } else {
            ChangeCategorySheet(
                file: file,
                categoryRows: categoryRows,
                state: changeCategoryState,
                classifierContextState: classifierCorrectionContextState,
                mode: destination.changeCategoryMode,
                initialTargetCategory: destination.initialChangeCategoryTarget,
                onCancel: onDismiss,
                onPreview: onPreviewChangeCategory,
                onLoadClassifierContext: onLoadClassifierCorrectionContext,
                onChangeCategory: onChangeCategory,
                onBeginRuleHandoff: onBeginClassifierRuleHandoff,
                onRenameFirst: onRenameFirstFromChangeCategory,
                onOpenPermissionRecovery: onOpenChangeCategoryPermissionRecovery,
                onCollectDiagnostics: onCollectDiagnostics
            )
        }
    }

    private func classifierRuleRouteView(_ route: ClassifierCorrectionRuleRoute) -> some View {
        ClassifierRuleHandoffRouteView(
            mode: route.handoffMode,
            repoPath: repoPath,
            handoff: route.handoff,
            onCancel: route.handoff.sourcePageID == "ai-category-suggestion" ? onCancelClassifierRuleRoute : onDismiss,
            onBack: onEditClassifierRule,
            onPreviewImpact: onPreviewClassifierRuleImpact,
            onSaved: onClassifierRuleSaved
        )
    }
}
