@testable import AreaMatrix

enum ChangeCategoryRequest: Equatable {
    case preview(repoPath: String, fileID: Int64, targetCategory: String)
    case move(repoPath: String, fileID: Int64, targetCategory: String)
    case correction(repoPath: String, fileID: Int64, targetCategory: String, moveFile: Bool, remember: Bool)
}

actor ChangeCategoryRecordingMover: CoreFileCategoryMoving {
    private let previewResult: Result<MoveToCategoryPreviewSnapshot, Error>
    private let moveResult: Result<FileEntrySnapshot, Error>
    private let correctionResult: Result<ClassifierCorrectionResultSnapshot, Error>
    private var requests: [ChangeCategoryRequest] = []

    init(
        previewResult: Result<MoveToCategoryPreviewSnapshot, Error>,
        moveResult: Result<FileEntrySnapshot, Error> = .failure(CoreError.Internal(message: "unexpected move")),
        correctionResult: Result<ClassifierCorrectionResultSnapshot, Error> = .failure(
            CoreError.Internal(message: "unexpected classifier correction")
        )
    ) {
        self.previewResult = previewResult
        self.moveResult = moveResult
        self.correctionResult = correctionResult
    }

    func previewMoveToCategory(
        repoPath: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot {
        requests.append(.preview(repoPath: repoPath, fileID: fileID, targetCategory: newCategory))
        return try previewResult.get()
    }

    func moveToCategory(repoPath: String, fileID: Int64, newCategory: String) async throws -> FileEntrySnapshot {
        requests.append(.move(repoPath: repoPath, fileID: fileID, targetCategory: newCategory))
        return try moveResult.get()
    }

    func correctFileCategory(
        repoPath: String,
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        remember: Bool
    ) async throws -> ClassifierCorrectionResultSnapshot {
        requests.append(.correction(
            repoPath: repoPath,
            fileID: fileID,
            targetCategory: targetCategory,
            moveFile: moveFile,
            remember: remember
        ))
        return try correctionResult.get()
    }

    func recordedRequests() -> [ChangeCategoryRequest] {
        requests
    }
}

typealias ChangeCategoryPredictionRequest = CategoryPredictionRequest
typealias ChangeCategoryRecordingPredictor = RecordingCategoryPredictor
typealias ChangeCategoryRecordingLister = RecordingFileLister
