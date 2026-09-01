import Foundation

extension FileActionCoordinator {
    @discardableResult
    func submitRename(fileID: Int64, newName: String) async -> FileActionRenameOutcome? {
        guard destination == .rename(fileID: fileID),
              !renameState.isRenaming,
              !Task.isCancelled else { return nil }

        let returnTargetCategory = renameState.changeCategoryReturnTarget(for: fileID)
        renameState = renameState.renamingState(fileID: fileID, targetCategory: returnTargetCategory)
        do {
            let renamedFile = try await fileRenamer.renameFile(
                repoPath: repoPath,
                fileID: fileID,
                newName: newName
            )
            guard destination == .rename(fileID: fileID) else { return nil }
            renameState = .idle
            if let returnTargetCategory {
                changeCategoryState = .idle
                destination = .changeCategory(
                    fileID: renamedFile.id,
                    initialTargetCategory: returnTargetCategory
                )
            } else {
                destination = nil
            }
            return FileActionRenameOutcome(file: renamedFile, returnTargetCategory: returnTargetCategory)
        } catch {
            let mapping = await mapCoreError(error)
            guard destination == .rename(fileID: fileID) else { return nil }
            renameState = renameState.failedState(
                fileID: fileID,
                targetCategory: returnTargetCategory,
                mapping: mapping
            )
            return nil
        }
    }
}

private extension MainFileRenameState {
    func renamingState(fileID: Int64, targetCategory: String?) -> MainFileRenameState {
        guard let targetCategory else { return .renaming(fileID: fileID) }
        return .renamingFromChangeCategory(fileID: fileID, targetCategory: targetCategory)
    }

    func failedState(
        fileID: Int64,
        targetCategory: String?,
        mapping: CoreErrorMappingSnapshot
    ) -> MainFileRenameState {
        guard let targetCategory else { return .failed(fileID: fileID, mapping) }
        return .failedFromChangeCategory(fileID: fileID, targetCategory: targetCategory, mapping)
    }
}
