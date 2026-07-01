@testable import AreaMatrix
import Foundation

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

@MainActor
func changeCategoryModel(
    file: FileEntrySnapshot,
    fileLister: any CoreFileListing = NoopFileLister(),
    fileCategoryMover: any CoreFileCategoryMoving,
    categoryPredictor: any CoreCategoryPredicting = CoreBridge(),
    changeLogLister: any CoreChangeLogListing = CoreBridge(),
    errorMapper: any CoreErrorMapping = StaticCoreErrorMapper(mapping: .changeCategoryClassify())
) -> MainFileListModel {
    MainFileListModel(
        opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
        fileLister: fileLister,
        fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
        fileCategoryMover: fileCategoryMover,
        categoryPredictor: categoryPredictor,
        changeLogLister: changeLogLister,
        errorMapper: errorMapper
    )
}

func changeCategoryMovedFile(
    from original: FileEntrySnapshot,
    updatedAt: Int64 = 1_700_000_400
) -> FileEntrySnapshot {
    FileEntrySnapshot.changeCategoryFixture(
        id: original.id,
        path: "finance/\(original.currentName)",
        category: "finance",
        name: original.currentName,
        updatedAt: updatedAt
    )
}

func changeCategoryPreview(
    for file: FileEntrySnapshot,
    targetPath: String? = nil,
    targetName: String? = nil,
    nameConflictResolved: Bool = false
) -> MoveToCategoryPreviewSnapshot {
    MoveToCategoryPreviewSnapshot.changeCategoryFixture(
        fileID: file.id,
        targetPath: targetPath ?? "finance/\(targetName ?? file.currentName)",
        targetName: targetName ?? file.currentName,
        nameConflictResolved: nameConflictResolved
    )
}

func changeCategoryPreviewRequest(fileID: Int64, targetCategory: String = "finance") -> ChangeCategoryRequest {
    .preview(repoPath: "/tmp/repo", fileID: fileID, targetCategory: targetCategory)
}

func changeCategoryMoveRequest(fileID: Int64, targetCategory: String = "finance") -> ChangeCategoryRequest {
    .move(repoPath: "/tmp/repo", fileID: fileID, targetCategory: targetCategory)
}

func makeChangeCategoryFeatureTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixChangeCategory")
}
