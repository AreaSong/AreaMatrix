import Foundation

extension MainFileListModel {
    func submitRename(fileID: Int64, newName: String) async {
        guard pendingActionDestination == .rename(fileID: fileID),
              !renameState.isRenaming,
              writeActionDisabledReason(fileID: fileID) == nil else { return }

        renameState = .renaming(fileID: fileID)
        do {
            let renamedFile = try await fileRenamer.renameFile(
                repoPath: repoPath,
                fileID: fileID,
                newName: newName
            )
            applyRenamedFile(renamedFile)
            renameState = .idle
            pendingActionDestination = nil
            statusBanner = .renamedPreservedSelection(fileID: renamedFile.id)
            if selection.singleFileID == renamedFile.id {
                await loadChangeLog(fileID: renamedFile.id)
                if case .loaded(let loadedFileID, _) = detailLogState, loadedFileID == renamedFile.id {
                    detailTabRequest = .automatic(.log)
                }
            }
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination == .rename(fileID: fileID) else { return }
            renameState = .failed(fileID: fileID, mapping)
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
