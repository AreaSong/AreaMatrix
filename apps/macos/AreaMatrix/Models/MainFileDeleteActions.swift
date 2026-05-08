import Foundation

extension MainFileListModel {
    func submitDelete(fileID: Int64, operation: MainFileDeleteOperation) async {
        guard pendingActionDestination == .delete(fileID: fileID),
              !deleteState.isDeleting,
              writeActionDisabledReason(fileID: fileID) == nil else { return }

        deleteState = .deleting(fileID: fileID, operation: operation)
        clearDiagnosticsState()
        do {
            try await performDelete(fileID: fileID, operation: operation)
            await applyDeletedFile(fileID: fileID, operation: operation)
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination == .delete(fileID: fileID) else { return }
            deleteState = .failed(fileID: fileID, operation: operation, mapping)
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

    private func applyDeletedFile(fileID: Int64, operation: MainFileDeleteOperation) async {
        files.removeAll { $0.id == fileID }
        if selection.singleFileID == fileID || selectedFileDetail?.id == fileID {
            await selectFiles([])
        }
        deleteState = .idle
        pendingActionDestination = nil
        statusBanner = operation.successBanner(fileID: fileID)
    }
}
