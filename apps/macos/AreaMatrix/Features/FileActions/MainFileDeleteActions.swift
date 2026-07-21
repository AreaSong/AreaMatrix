import Foundation

extension MainFileListModel {
    @discardableResult
    func submitDelete(fileID: Int64, operation: MainFileDeleteOperation) async -> Bool {
        guard pendingActionDestination == .delete(fileID: fileID),
              !deleteState.isDeleting,
              canPerformWriteAction(fileID: fileID) else { return false }

        deleteState = .deleting(fileID: fileID, operation: operation)
        let selectionGeneration = detailGeneration
        clearDiagnosticsState()
        do {
            try await performDelete(fileID: fileID, operation: operation)
            await applyDeletedFile(
                fileID: fileID,
                operation: operation,
                selectionGeneration: selectionGeneration
            )
            return true
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination == .delete(fileID: fileID) else { return false }
            deleteState = .failed(fileID: fileID, operation: operation, mapping)
            return false
        }
    }

    private func performDelete(fileID: Int64, operation: MainFileDeleteOperation) async throws {
        switch operation {
        case .moveToTrash:
            try await fileDeleter.deleteFile(repoPath: repoPath, fileID: fileID)
        case .removeFromIndex:
            try await fileDeleter.removeIndexEntry(repoPath: repoPath, fileID: fileID)
        }
    }

    private func applyDeletedFile(
        fileID: Int64,
        operation: MainFileDeleteOperation,
        selectionGeneration: Int
    ) async {
        files.removeAll { $0.id == fileID }
        if detailGeneration == selectionGeneration, selection.singleFileID == fileID {
            await selectFiles([])
        }
        deleteState = .idle
        pendingActionDestination = nil
        statusBanner = operation.successBanner(fileID: fileID)
    }
}
