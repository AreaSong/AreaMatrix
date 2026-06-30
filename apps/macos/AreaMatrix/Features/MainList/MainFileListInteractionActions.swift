import Foundation

extension MainFileListModel {
    func clearStatusBanner() {
        statusBanner = nil
    }

    func showUnsavedNoteDraftPreserved(fileID: Int64) {
        statusBanner = .unsavedNoteDraftPreserved(fileID: fileID)
    }

    func writeActionDisabledReason(fileID: Int64) -> MainFileWriteActionDisabledReason? {
        MainFileWriteActionEligibility.disabledReason(
            fileID: fileID,
            isReadOnly: isReadOnly,
            isLoading: isLoading,
            writeLockedFileIDs: writeLockedFileIDs
        )
    }

    func canPerformWriteAction(fileID: Int64) -> Bool {
        writeActionDisabledReason(fileID: fileID) == nil
    }

    func writeActionDisabledMessage(fileID: Int64) -> String? {
        writeActionDisabledReason(fileID: fileID)?.message
    }

    func selectedWriteActionDisabledMessage(noSelectionMessage: String) -> String? {
        guard let fileID = selection.singleFileID else { return noSelectionMessage }
        return writeActionDisabledMessage(fileID: fileID)
    }

    func beginAIClassificationSuggestion(fileID: Int64? = nil) {
        guard let fileID = writableActionFileID(fileID) else { return }
        pendingActionDestination = .aiClassificationSuggestion(fileID: fileID)
    }

    func beginAIClassificationChange(fileID: Int64, targetCategory: String?) {
        guard let fileID = writableActionFileID(fileID) else { return }
        changeCategoryState = .idle
        classifierCorrectionContextState = .idle
        classifierCorrectionResult = nil
        pendingActionDestination = .changeCategory(
            fileID: fileID,
            initialTargetCategory: targetCategory,
            mode: .classifierCorrection
        )
    }

    func writableActionFileID(_ fileID: Int64? = nil) -> Int64? {
        guard let resolvedFileID = fileID ?? selection.singleFileID,
              canPerformWriteAction(fileID: resolvedFileID) else {
            return nil
        }
        return resolvedFileID
    }
}
