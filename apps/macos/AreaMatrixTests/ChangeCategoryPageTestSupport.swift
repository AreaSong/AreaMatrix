@testable import AreaMatrix
import Foundation

@MainActor
func changeCategoryModel(
    file: FileEntrySnapshot,
    fileLister: any CoreFileListing = NoopFileLister(),
    fileCategoryMover: any CoreFileCategoryMoving,
    categoryPredictor: any CoreCategoryPredicting = ChangeCategoryRecordingPredictor(
        result: .success(changeCategoryPredictionFixture())
    ),
    changeLogLister: any CoreChangeLogListing = DetailLogRecordingLister(results: [.success([])]),
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
