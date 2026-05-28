import Foundation

extension MainFileListModel {
    typealias MoveToCategoryCompletion = @MainActor (FileEntrySnapshot) -> Void

    func loadClassifierCorrectionContext(fileID: Int64, filename: String) async {
        guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
              pendingActionDestination?.changeCategoryMode == .classifierCorrection,
              writeActionDisabledReason(fileID: fileID) == nil else { return }

        let request = ClassifierCorrectionContextRequest(fileID: fileID, filename: filename)
        guard classifierCorrectionContextState.needsLoad(request) else { return }

        classifierCorrectionContextState = .loading(request)
        do {
            let result = try await categoryPredictor.predictCategory(repoPath: repoPath, filename: filename)
            guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
                  classifierCorrectionContextState.isLoading(request) else { return }
            classifierCorrectionContextState = .loaded(request, result)
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
                  classifierCorrectionContextState.isLoading(request) else { return }
            classifierCorrectionContextState = .failed(request, mapping)
        }
    }

    func loadMoveToCategoryPreview(fileID: Int64, targetCategory: String) async {
        guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
              writeActionDisabledReason(fileID: fileID) == nil else { return }

        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        changeCategoryState = .checking(request)
        do {
            let preview = try await fileCategoryMover.previewMoveToCategory(
                repoPath: repoPath,
                fileID: fileID,
                newCategory: targetCategory
            )
            guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
                  changeCategoryState.isChecking(request) else { return }
            changeCategoryState = .ready(request, preview)
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
                  changeCategoryState.isChecking(request) else { return }
            changeCategoryState = .failed(request, operation: .preview, mapping)
        }
    }

    @discardableResult
    func submitMoveToCategory(
        fileID: Int64,
        targetCategory: String,
        mode: MainFileCategoryMoveMode = .moveToCategory,
        options: MainFileCategoryMoveOptions = MainFileCategoryMoveOptions(moveFile: true, remember: false),
        onMoved: MoveToCategoryCompletion? = nil
    ) async -> Bool {
        guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
              !changeCategoryState.isMoving(fileID: fileID),
              writeActionDisabledReason(fileID: fileID) == nil else { return false }

        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        changeCategoryState = .moving(request, preview: changeCategoryState.preview(for: request))
        do {
            let result = try await submitCategoryChange(
                fileID: fileID,
                targetCategory: targetCategory,
                mode: mode,
                options: options
            )
            let movedFile = result.updatedFile
            await applyMovedToCategoryFile(movedFile, mode: mode)
            onMoved?(movedFile)
            return true
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true else { return false }
            changeCategoryState = .failed(request, operation: failureOperation(for: mode), mapping)
            return false
        }
    }

    private func submitCategoryChange(
        fileID: Int64,
        targetCategory: String,
        mode: MainFileCategoryMoveMode,
        options: MainFileCategoryMoveOptions
    ) async throws -> MainFileCategoryChangeResult {
        switch mode {
        case .moveToCategory:
            let movedFile = try await fileCategoryMover.moveToCategory(
                repoPath: repoPath,
                fileID: fileID,
                newCategory: targetCategory
            )
            return MainFileCategoryChangeResult(updatedFile: movedFile)
        case .classifierCorrection:
            let correction = try await fileCategoryMover.correctFileCategory(
                repoPath: repoPath,
                fileID: fileID,
                targetCategory: targetCategory,
                moveFile: options.moveFile,
                remember: options.remember
            )
            classifierCorrectionResult = correction
            return MainFileCategoryChangeResult(updatedFile: correction.updatedFile, correction: correction)
        }
    }

    private func failureOperation(for mode: MainFileCategoryMoveMode) -> MainFileCategoryMoveFailureOperation {
        mode == .classifierCorrection ? .correction : .move
    }

    private func applyMovedToCategoryFile(
        _ movedFile: FileEntrySnapshot,
        mode: MainFileCategoryMoveMode
    ) async {
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
        if mode == .classifierCorrection {
            statusBanner = classifierCorrectionStatusBanner(for: movedFile)
            detailTabRequest = .automatic(.log)
        } else {
            statusBanner = .changedCategory(fileID: movedFile.id, category: movedFile.category)
        }
        await loadChangeLog(fileID: movedFile.id)
        if case let .loaded(loadedFileID, _) = detailLogState, loadedFileID == movedFile.id {
            detailTabRequest = .automatic(.log)
        }
    }

    private func classifierCorrectionStatusBanner(for file: FileEntrySnapshot) -> MainListStatusBanner {
        .correctedClassification(
            fileID: file.id,
            category: file.category,
            ruleConfirmationRequired: classifierCorrectionResult?.ruleConfirmationRequired ?? false
        )
    }

    private func isMovedFileVisibleInCurrentList(_ file: FileEntrySnapshot) -> Bool {
        guard let currentCategory else { return true }
        return file.category == currentCategory
    }
}

private struct MainFileCategoryChangeResult {
    var updatedFile: FileEntrySnapshot
    var correction: ClassifierCorrectionResultSnapshot?
}
