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
            file: file(for: destination.fileID),
            candidateFiles: fileListModel.files,
            categoryRows: repositoryTree.sidebarRows,
            renameState: fileListModel.renameState,
            deleteState: fileListModel.deleteState,
            changeCategoryState: fileListModel.changeCategoryState,
            iCloudConflictResolutionState: fileListModel.iCloudConflictResolutionState,
            iCloudConflictResolutionCapability: fileListModel.iCloudConflictResolver.iCloudConflictResolutionCapability,
            repoPath: opening.config.repoPath,
            isTrashAvailable: OnboardingModel.isSystemTrashAvailable(),
            iCloudConflictPathValidator: CoreBridge(),
            iCloudConflictErrorMapper: fileListModel.errorMapper,
            onDismiss: fileListModel.clearPendingActionDestination,
            onRename: submitRename,
            onShowExistingFile: showExistingFile,
            onPreviewChangeCategory: previewChangeCategory,
            onChangeCategory: submitChangeCategory,
            onRenameFirstFromChangeCategory: { fileID, targetCategory in
                fileListModel.beginRenameFromChangeCategory(fileID: fileID, targetCategory: targetCategory)
            },
            onOpenChangeCategoryPermissionRecovery: {
                onOpenChangeCategoryPermissionRecovery()
            },
            onDelete: submitDelete,
            onApplyICloudConflict: applyICloudConflict,
            onCollectDiagnostics: {
                Task {
                    await fileListModel.collectCurrentListDiagnostics()
                }
            }
        )
    }

    private func file(for fileID: Int64) -> FileEntrySnapshot? {
        fileListModel.files.first { $0.id == fileID } ??
            fileListModel.selectedFileDetail.flatMap { $0.id == fileID ? $0 : nil }
    }

    private func submitRename(fileID: Int64, newName: String) {
        Task { await fileListModel.submitRename(fileID: fileID, newName: newName) }
    }

    private func showExistingFile(fileID: Int64) {
        selectedFileIDs = [fileID]
        fileListModel.clearPendingActionDestination()
        Task { await fileListModel.selectFiles([fileID]) }
    }

    private func previewChangeCategory(fileID: Int64, targetCategory: String) {
        Task { await fileListModel.loadMoveToCategoryPreview(fileID: fileID, targetCategory: targetCategory) }
    }

    private func submitChangeCategory(fileID: Int64, targetCategory: String) {
        Task {
            await fileListModel.submitMoveToCategory(fileID: fileID, targetCategory: targetCategory) { movedFile in
                refreshAfterCategoryMove(movedFile)
            }
        }
    }

    private func submitDelete(fileID: Int64, operation: MainFileDeleteOperation) {
        Task { await fileListModel.submitDelete(fileID: fileID, operation: operation) }
    }

    private func applyICloudConflict(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        originalPath: String?,
        conflictedCopyPath: String?
    ) {
        Task {
            await fileListModel.applyICloudConflictResolution(
                fileID: fileID,
                strategy: strategy,
                originalPath: originalPath,
                conflictedCopyPath: conflictedCopyPath
            )
        }
    }
}
