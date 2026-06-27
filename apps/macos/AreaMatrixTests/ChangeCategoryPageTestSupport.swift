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

struct ChangeCategoryPredictionRequest: Equatable {
    var repoPath: String
    var filename: String
}

actor ChangeCategoryRecordingPredictor: CoreCategoryPredicting {
    private let result: Result<ClassifyResultSnapshot, Error>
    private var requests: [ChangeCategoryPredictionRequest] = []

    init(result: Result<ClassifyResultSnapshot, Error>) {
        self.result = result
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(ChangeCategoryPredictionRequest(repoPath: repoPath, filename: filename))
        return try result.get()
    }

    func recordedRequests() -> [ChangeCategoryPredictionRequest] {
        requests
    }
}

actor ChangeCategoryRecordingLister: CoreFileListing {
    enum Result {
        case success([FileEntrySnapshot])
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [FileFilterSnapshot] = []

    init(results: [Result]) {
        self.results = results
    }

    func listFiles(repoPath _: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        requests.append(filter)
        guard !results.isEmpty else { return [] }

        switch results.removeFirst() {
        case let .success(files):
            return files
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [FileFilterSnapshot] {
        requests
    }
}

extension FileEntrySnapshot {
    static func changeCategoryFixture(
        id: Int64,
        path: String = "docs/contracts/contract.pdf",
        category: String = "docs",
        name: String,
        updatedAt: Int64 = 1_700_000_100
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: name,
            currentName: name,
            category: category,
            sizeBytes: 512,
            hashSha256: "change-category-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: updatedAt
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func changeCategoryTree(docsCount: Int64, financeCount: Int64) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: docsCount, children: []),
                RepositoryTreeNodeSnapshot(
                    slug: "finance",
                    displayName: "finance",
                    fileCount: financeCount,
                    children: []
                )
            ]
        )
    }
}

extension MoveToCategoryPreviewSnapshot {
    static func changeCategoryFixture(
        fileID: Int64,
        targetPath: String,
        targetName: String,
        indexOnly: Bool = false,
        nameConflictResolved: Bool = false
    ) -> MoveToCategoryPreviewSnapshot {
        MoveToCategoryPreviewSnapshot(
            fileID: fileID,
            fromCategory: "docs",
            toCategory: "finance",
            currentPath: "docs/contracts/\(targetName)",
            targetPath: targetPath,
            targetName: targetName,
            storageMode: indexOnly ? "Indexed" : "Copied",
            indexOnly: indexOnly,
            nameConflictResolved: nameConflictResolved,
            willMoveFile: !indexOnly
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func changeCategoryClassify() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .classify,
            userMessage: "Target category is unavailable.",
            severity: .medium,
            suggestedAction: "Choose another category, then retry.",
            recoverability: .userActionRequired,
            rawContext: "change-category move-to-category preview_move_to_category"
        )
    }
}

func makeChangeCategoryFeatureTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixChangeCategory")
}
