import Foundation

extension MainFileListModel {
    func beginRename(fileID: Int64? = nil) {
        guard let fileID = writableActionFileID(fileID) else { return }
        renameState = .idle
        pendingActionDestination = .rename(fileID: fileID)
    }

    func beginChangeCategory(fileID: Int64? = nil) {
        guard let fileID = writableActionFileID(fileID) else { return }
        changeCategoryState = .idle
        classifierCorrectionContextState = .idle
        classifierCorrectionResult = nil
        pendingActionDestination = .changeCategory(fileID: fileID)
    }

    func beginClassifierCorrection(fileID: Int64? = nil) {
        guard let fileID = writableActionFileID(fileID) else { return }
        changeCategoryState = .idle
        classifierCorrectionContextState = .idle
        classifierCorrectionResult = nil
        pendingActionDestination = .changeCategory(fileID: fileID, mode: .classifierCorrection)
    }

    func beginRenameFromChangeCategory(fileID: Int64, targetCategory: String) {
        guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
              canPerformWriteAction(fileID: fileID),
              !changeCategoryState.isMoving(fileID: fileID) else { return }
        renameState = .returningToChangeCategory(fileID: fileID, targetCategory: targetCategory)
        pendingActionDestination = .rename(fileID: fileID)
    }

    func beginDelete(fileID: Int64? = nil) {
        guard let fileID = writableActionFileID(fileID) else { return }
        pendingActionDestination = .delete(fileID: fileID)
    }

    func openClassifierRuleEditorForBatchCategory(context: BatchChangeCategoryReturnContext) {
        pendingSearchDestination = .classifierRuleEditor(context: context)
    }

    func clearPendingActionDestination() {
        if !renameState.isRenaming,
           !deleteState.isDeleting,
           !isMovingCategory,
           !iCloudConflictResolutionState.isApplying {
            pendingActionDestination = nil
            renameState = .idle
            deleteState = .idle
            changeCategoryState = .idle
            classifierCorrectionContextState = .idle
            classifierCorrectionResult = nil
            iCloudConflictResolutionState = .idle
        }
    }

    func actionRoutingFile(for fileID: Int64) -> FileEntrySnapshot? {
        files.first { $0.id == fileID } ??
            selectedFileDetail.flatMap { $0.id == fileID ? $0 : nil }
    }

    private var isMovingCategory: Bool {
        guard let destination = pendingActionDestination else { return false }
        return changeCategoryState.isMoving(fileID: destination.fileID)
    }
}
