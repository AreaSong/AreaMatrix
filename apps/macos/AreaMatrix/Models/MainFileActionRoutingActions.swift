import Foundation

extension MainFileListModel {
    func beginRename(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        renameState = .idle
        pendingActionDestination = .rename(fileID: fileID)
    }

    func beginChangeCategory(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        changeCategoryState = .idle
        pendingActionDestination = .changeCategory(fileID: fileID)
    }

    func beginDelete(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        pendingActionDestination = .delete(fileID: fileID)
    }

    func clearPendingActionDestination() {
        if !renameState.isRenaming && !deleteState.isDeleting && !isMovingCategory {
            pendingActionDestination = nil
            renameState = .idle
            deleteState = .idle
            changeCategoryState = .idle
        }
    }

    private var isMovingCategory: Bool {
        guard let destination = pendingActionDestination else { return false }
        return changeCategoryState.isMoving(fileID: destination.fileID)
    }
}
