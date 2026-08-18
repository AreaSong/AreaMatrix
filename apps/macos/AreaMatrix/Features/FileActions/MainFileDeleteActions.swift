import Foundation

extension FileActionCoordinator {
    @discardableResult
    func submitDelete(fileID: Int64, operation: MainFileDeleteOperation) async -> FileActionDeleteOutcome? {
        guard destination == .delete(fileID: fileID),
              !deleteState.isDeleting,
              !Task.isCancelled else { return nil }

        deleteState = .deleting(fileID: fileID, operation: operation)
        do {
            try await performDelete(fileID: fileID, operation: operation)
            guard destination == .delete(fileID: fileID) else { return nil }
            deleteState = .idle
            destination = nil
            return FileActionDeleteOutcome(fileID: fileID, operation: operation)
        } catch {
            let mapping = await mapCoreError(error)
            guard destination == .delete(fileID: fileID) else { return nil }
            deleteState = .failed(fileID: fileID, operation: operation, mapping)
            return nil
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

    static func successBanner(
        for operation: MainFileDeleteOperation,
        fileID: Int64
    ) -> MainListStatusBanner {
        switch operation {
        case .moveToTrash:
            .movedFileToTrash(fileID: fileID)
        case .removeFromIndex:
            .removedFileFromIndex(fileID: fileID)
        }
    }
}
