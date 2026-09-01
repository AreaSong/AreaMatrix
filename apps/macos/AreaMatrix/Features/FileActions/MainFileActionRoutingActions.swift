import Foundation

extension FileActionCoordinator {
    func beginRename(fileID: Int64) {
        renameState = .idle
        pendingActionDestination = .rename(fileID: fileID)
    }

    func beginChangeCategory(fileID: Int64) {
        changeCategoryState = .idle
        classifierCorrectionContextState = .idle
        classifierCorrectionResult = nil
        pendingActionDestination = .changeCategory(fileID: fileID)
    }

    func beginClassifierCorrection(fileID: Int64) {
        changeCategoryState = .idle
        classifierCorrectionContextState = .idle
        classifierCorrectionResult = nil
        pendingActionDestination = .changeCategory(fileID: fileID, mode: .classifierCorrection)
    }

    func beginRenameFromChangeCategory(fileID: Int64, targetCategory: String) {
        guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
              !changeCategoryState.isMoving(fileID: fileID) else { return }
        renameState = .returningToChangeCategory(fileID: fileID, targetCategory: targetCategory)
        pendingActionDestination = .rename(fileID: fileID)
    }

    func beginDelete(fileID: Int64) {
        pendingActionDestination = .delete(fileID: fileID)
    }

    func clearPendingActionDestination(canClearExternalState: Bool) {
        if !renameState.isRenaming,
           !deleteState.isDeleting,
           !isMovingCategory,
           canClearExternalState {
            pendingActionDestination = nil
            renameState = .idle
            deleteState = .idle
            changeCategoryState = .idle
            classifierCorrectionContextState = .idle
            classifierCorrectionResult = nil
        }
    }

    private var isMovingCategory: Bool {
        guard let destination = pendingActionDestination else { return false }
        return changeCategoryState.isMoving(fileID: destination.fileID)
    }
}
