import Foundation

extension MainFileListModel {
    @discardableResult
    func submitRename(fileID: Int64, newName: String) async -> Bool {
        guard pendingActionDestination == .rename(fileID: fileID),
              !renameState.isRenaming,
              writeActionDisabledReason(fileID: fileID) == nil else { return false }

        let returnTargetCategory = renameState.changeCategoryReturnTarget(for: fileID)
        renameState = renameState.renamingState(fileID: fileID, targetCategory: returnTargetCategory)
        do {
            let renamedFile = try await fileRenamer.renameFile(
                repoPath: repoPath,
                fileID: fileID,
                newName: newName
            )
            applyRenamedFile(renamedFile)
            renameState = .idle
            if let returnTargetCategory {
                changeCategoryState = .idle
                pendingActionDestination = .changeCategory(
                    fileID: renamedFile.id,
                    initialTargetCategory: returnTargetCategory
                )
            } else {
                pendingActionDestination = nil
            }
            statusBanner = .renamedPreservedSelection(fileID: renamedFile.id)
            if selection.singleFileID == renamedFile.id {
                await loadChangeLog(fileID: renamedFile.id)
                if case let .loaded(loadedFileID, _) = detailLogState, loadedFileID == renamedFile.id {
                    detailTabRequest = .automatic(.log)
                }
            }
            return true
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination == .rename(fileID: fileID) else { return false }
            renameState = renameState.failedState(
                fileID: fileID,
                targetCategory: returnTargetCategory,
                mapping: mapping
            )
            return false
        }
    }

    private func applyRenamedFile(_ renamedFile: FileEntrySnapshot) {
        files = files.map { file in
            file.id == renamedFile.id ? renamedFile : file
        }
        selection = .single(renamedFile.id)
        selectedFileDetail = renamedFile
        selectedFileNoteWriteBlock = noteWriteBlock(for: renamedFile)
        detailErrorMapping = nil
        isDetailLoading = false
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
