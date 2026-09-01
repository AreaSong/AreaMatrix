import Foundation

extension FileActionCoordinator {
    typealias MoveToCategoryCompletion = @MainActor (FileEntrySnapshot) -> Void

    func loadClassifierCorrectionContext(fileID: Int64, filename: String) async {
        guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
              pendingActionDestination?.changeCategoryMode == .classifierCorrection else { return }

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
        guard pendingActionDestination?.supportsCategoryPreview(fileID: fileID) == true,
              true else { return }

        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        changeCategoryState = .checking(request)
        do {
            let preview = try await fileCategoryMover.previewMoveToCategory(
                repoPath: repoPath,
                fileID: fileID,
                newCategory: targetCategory
            )
            guard pendingActionDestination?.supportsCategoryPreview(fileID: fileID) == true,
                  changeCategoryState.isChecking(request) else { return }
            changeCategoryState = .ready(request, preview)
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination?.supportsCategoryPreview(fileID: fileID) == true,
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
    ) async -> FileActionCategoryOutcome? {
        guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true,
              !changeCategoryState.isMoving(fileID: fileID) else { return nil }

        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        changeCategoryState = .moving(request, preview: changeCategoryState.preview(for: request))
        do {
            let result = try await submitCategoryChange(
                fileID: fileID,
                targetCategory: targetCategory,
                mode: mode,
                options: options
            )
            guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true else { return nil }
            changeCategoryState = .idle
            pendingActionDestination = nil
            onMoved?(result.updatedFile)
            return FileActionCategoryOutcome(
                file: result.updatedFile,
                mode: mode,
                correction: result.correction
            )
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination?.isChangeCategory(fileID: fileID) == true else { return nil }
            changeCategoryState = .failed(request, operation: failureOperation(for: mode), mapping)
            return nil
        }
    }

    @discardableResult
    func submitAIClassificationSuggestion(
        _ request: AIClassificationSuggestionApplyRequest
    ) async -> FileActionCategoryOutcome? {
        guard pendingActionDestination?.isAIClassificationSuggestion(fileID: request.fileID) == true,
              !changeCategoryState.isMoving(fileID: request.fileID) else { return nil }

        let previewRequest = MainFileCategoryMovePreviewRequest(
            fileID: request.fileID,
            targetCategory: request.targetCategory
        )
        changeCategoryState = .moving(previewRequest, preview: request.preview)
        do {
            let result = try await fileCategoryMover.correctFileCategory(
                repoPath: repoPath,
                fileID: request.fileID,
                targetCategory: request.targetCategory,
                moveFile: request.moveFile,
                remember: request.rememberRule
            )
            classifierCorrectionResult = result
            guard pendingActionDestination?.isAIClassificationSuggestion(fileID: request.fileID) == true else {
                return nil
            }
            changeCategoryState = .idle
            return FileActionCategoryOutcome(
                file: result.updatedFile,
                mode: .classifierCorrection,
                correction: result
            )
        } catch {
            let mapping = await mapCoreError(error)
            guard pendingActionDestination?.isAIClassificationSuggestion(fileID: request.fileID) == true else {
                return nil
            }
            changeCategoryState = .failed(previewRequest, operation: .correction, mapping)
            return nil
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
}

private struct MainFileCategoryChangeResult {
    var updatedFile: FileEntrySnapshot
    var correction: ClassifierCorrectionResultSnapshot?
}
