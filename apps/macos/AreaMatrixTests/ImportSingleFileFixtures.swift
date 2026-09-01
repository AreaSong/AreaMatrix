@testable import AreaMatrix
import AreaMatrixFeatureIngestion
import Foundation

func importSingleFileContractURL() -> URL {
    URL(fileURLWithPath: "/tmp/合同.pdf")
}

func importSingleFileSourceURL() -> URL {
    URL(fileURLWithPath: importSingleFileSourcePath())
}

func importSingleFileSourcePath() -> String {
    "/tmp/source.pdf"
}

func importSingleFileRepoPath() -> String {
    "/tmp/repo"
}

extension ClassifyResultSnapshot {
    static func importSingleFileFixture(
        category: String = "docs",
        suggestedName: String = "source.pdf",
        reason: ClassifyReasonSnapshot = .extension,
        confidence: Float = 0.7
    ) -> ClassifyResultSnapshot {
        makeImportSingleFileFixture(
            category: category,
            suggestedName: suggestedName,
            reason: reason,
            confidence: confidence
        )
    }

    private static func makeImportSingleFileFixture(
        category: String,
        suggestedName: String,
        reason: ClassifyReasonSnapshot,
        confidence: Float
    ) -> ClassifyResultSnapshot {
        .testFixture(
            category: category,
            suggestedName: suggestedName,
            reason: reason,
            confidence: confidence
        )
    }
}

extension FileEntrySnapshot {
    static func importSingleFileFixture(
        currentName: String,
        category: String,
        hashSha256: String = "hash",
        storageMode: String = "Copied"
    ) -> FileEntrySnapshot {
        makeImportSingleFileFixture(
            id: 42,
            currentName: currentName,
            category: category,
            hashSha256: hashSha256,
            storageMode: storageMode
        )
    }

    private static func makeImportSingleFileFixture(
        id: Int64,
        currentName: String,
        category: String,
        hashSha256: String,
        storageMode: String
    ) -> FileEntrySnapshot {
        FileEntrySnapshot.testFixture(
            id: id,
            path: "\(category)/\(currentName)",
            currentName: currentName,
            category: category
        ) {
            $0.originalName = "source.pdf"
            $0.sizeBytes = 12
            $0.hashSha256 = hashSha256
            $0.storageMode = storageMode
            $0.sourcePath = importSingleFileSourcePath()
            $0.updatedAt = 1_700_000_000
        }
    }

    static func importMoveFixture(currentName: String, category: String) -> FileEntrySnapshot {
        importSingleFileFixture(currentName: currentName, category: category, storageMode: "Moved")
    }

    static func importIndexFixture(currentName: String, category: String) -> FileEntrySnapshot {
        FileEntrySnapshot.testFixture(
            id: 43,
            path: importSingleFileSourcePath(),
            currentName: currentName,
            category: category
        ) {
            $0.originalName = "source.pdf"
            $0.sizeBytes = 12
            $0.hashSha256 = "hash"
            $0.storageMode = "Indexed"
            $0.sourcePath = importSingleFileSourcePath()
            $0.updatedAt = 1_700_000_000
        }
    }

    static func importNameConflictReplaceFixture() -> FileEntrySnapshot {
        importReplaceExistingFileFixture(path: "docs/reports/报告.pdf", hashSha256: "existing-hash", id: 125)
    }

    static func importDuplicateReplaceFixture() -> FileEntrySnapshot {
        importReplaceExistingFileFixture(path: "docs/reports/报告.pdf", hashSha256: "duplicate-hash")
    }

    static func importReplaceExistingFileFixture(
        path: String,
        hashSha256: String,
        id: Int64 = 124
    ) -> FileEntrySnapshot {
        let currentName = (path as NSString).lastPathComponent
        return FileEntrySnapshot.testFixture(
            id: id,
            path: path,
            currentName: currentName,
            category: (path as NSString).deletingLastPathComponent
        ) {
            $0.sizeBytes = 860 * 1024
            $0.hashSha256 = hashSha256
            $0.updatedAt = 1_776_660_840
        }
    }
}

extension ImportEntryRequest {
    static func importSingleFileImportRequest(
        repoPath: String = importSingleFileRepoPath(),
        source: ImportEntrySource = .filePicker,
        destination: ImportEntryDestination = .autoClassify,
        sourcePath: String = importSingleFileSourcePath()
    ) -> ImportEntryRequest {
        ImportEntryRequest(
            repoPath: repoPath,
            source: source,
            destination: destination,
            urls: [URL(fileURLWithPath: sourcePath)],
            kind: .singleFile
        )
    }

    static func importSingleFileFixture(
        repoPath: String = importSingleFileRepoPath(),
        sourcePath: String = importSingleFileSourcePath(),
        allowReplaceDuringImport: Bool = true,
        isTrashAvailable: Bool = true
    ) -> ImportEntryRequest {
        ImportEntryRequest(
            repoPath: repoPath,
            source: .filePicker,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: sourcePath)],
            kind: .singleFile,
            allowReplaceDuringImport: allowReplaceDuringImport,
            isTrashAvailable: isTrashAvailable
        )
    }
}

extension ImportSingleFileStorageMode {
    var coreStorageMode: String {
        switch self {
        case .copy:
            "Copied"
        case .move:
            "Moved"
        case .indexOnly:
            "Indexed"
        }
    }
}

extension RepositoryOpeningResult {
    static func importSingleFileFixture(repoPath: String) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .testFixture(repoPath: repoPath),
            tree: .testRoot(
                displayName: "资料库",
                children: [
                    .testCategory("inbox"),
                    .testCategory("docs"),
                    .testCategory("finance")
                ]
            ),
            currentCategoryFiles: []
        )
    }
}
