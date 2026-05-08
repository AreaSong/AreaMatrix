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
            onRename: { fileID, newName in
                Task { await fileListModel.submitRename(fileID: fileID, newName: newName) }
            },
            onShowExistingFile: { fileID in
                selectedFileIDs = [fileID]
                fileListModel.clearPendingActionDestination()
                Task {
                    await fileListModel.selectFiles([fileID])
                }
            },
            onPreviewChangeCategory: { fileID, targetCategory in
                Task { await fileListModel.loadMoveToCategoryPreview(fileID: fileID, targetCategory: targetCategory) }
            },
            onChangeCategory: { fileID, targetCategory in
                Task {
                    await fileListModel.submitMoveToCategory(
                        fileID: fileID,
                        targetCategory: targetCategory
                    ) { movedFile in
                        refreshAfterCategoryMove(movedFile)
                    }
                }
            },
            onRenameFirstFromChangeCategory: { fileID, targetCategory in
                fileListModel.beginRenameFromChangeCategory(fileID: fileID, targetCategory: targetCategory)
            },
            onOpenChangeCategoryPermissionRecovery: {
                onOpenChangeCategoryPermissionRecovery()
            },
            onDelete: { fileID, operation in
                Task { await fileListModel.submitDelete(fileID: fileID, operation: operation) }
            },
            onApplyICloudConflict: { fileID, strategy, originalPath, conflictedCopyPath in
                Task {
                    await fileListModel.applyICloudConflictResolution(
                        fileID: fileID,
                        strategy: strategy,
                        originalPath: originalPath,
                        conflictedCopyPath: conflictedCopyPath
                    )
                }
            },
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
}
