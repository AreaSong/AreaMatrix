import Foundation

extension MainFileListModel {
    typealias MoveToCategoryCompletion = @MainActor (FileEntrySnapshot) -> Void

    func loadMoveToCategoryPreview(fileID: Int64, targetCategory: String) async {
        guard pendingActionDestination == .changeCategory(fileID: fileID),
              writeActionDisabledReason(fileID: fileID) == nil else { return }

        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        changeCategoryState = .checking(request)
        do {
            let preview = try await fileCategoryMover.previewMoveToCategory(
                repoPath: repoPath,
                fileID: fileID,
                newCategory: targetCategory
            )
            guard pendingActionDestination == .changeCategory(fileID: fileID),
                  changeCategoryState.isChecking(request) else { return }
            changeCategoryState = .ready(request, preview)
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination == .changeCategory(fileID: fileID),
                  changeCategoryState.isChecking(request) else { return }
            changeCategoryState = .failed(request, operation: .preview, mapping)
        }
    }

    func submitMoveToCategory(
        fileID: Int64,
        targetCategory: String,
        onMoved: MoveToCategoryCompletion? = nil
    ) async {
        guard pendingActionDestination == .changeCategory(fileID: fileID),
              !changeCategoryState.isMoving(fileID: fileID),
              writeActionDisabledReason(fileID: fileID) == nil else { return }

        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        changeCategoryState = .moving(request, preview: changeCategoryState.preview(for: request))
        do {
            let movedFile = try await fileCategoryMover.moveToCategory(
                repoPath: repoPath,
                fileID: fileID,
                newCategory: targetCategory
            )
            await applyMovedToCategoryFile(movedFile)
            onMoved?(movedFile)
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination == .changeCategory(fileID: fileID) else { return }
            changeCategoryState = .failed(request, operation: .move, mapping)
        }
    }

    private func applyMovedToCategoryFile(_ movedFile: FileEntrySnapshot) async {
        files = files.map { file in
            file.id == movedFile.id ? movedFile : file
        }
        if !isMovedFileVisibleInCurrentList(movedFile) {
            files.removeAll { $0.id == movedFile.id }
        }

        selection = .single(movedFile.id)
        selectedFileDetail = movedFile
        selectedFileNoteWriteBlock = noteWriteBlock(for: movedFile)
        detailErrorMapping = nil
        isDetailLoading = false
        changeCategoryState = .idle
        pendingActionDestination = nil
        statusBanner = .changedCategory(fileID: movedFile.id, category: movedFile.category)
        await loadChangeLog(fileID: movedFile.id)
        if case .loaded(let loadedFileID, _) = detailLogState, loadedFileID == movedFile.id {
            detailTabRequest = .automatic(.log)
        }
    }

    private func isMovedFileVisibleInCurrentList(_ file: FileEntrySnapshot) -> Bool {
        guard let currentCategory else { return true }
        return file.category == currentCategory
    }
}
