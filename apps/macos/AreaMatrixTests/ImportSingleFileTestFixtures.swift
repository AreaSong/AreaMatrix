@testable import AreaMatrix
import Foundation
import XCTest

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
        ClassifyResultSnapshot(
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
        FileEntrySnapshot(
            id: id,
            path: "\(category)/\(currentName)",
            originalName: "source.pdf",
            currentName: currentName,
            category: category,
            sizeBytes: 12,
            hashSha256: hashSha256,
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: importSingleFileSourcePath(),
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }

    static func importMoveFixture(currentName: String, category: String) -> FileEntrySnapshot {
        importSingleFileFixture(currentName: currentName, category: category, storageMode: "Moved")
    }

    static func importIndexFixture(currentName: String, category: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: 43,
            path: importSingleFileSourcePath(),
            originalName: "source.pdf",
            currentName: currentName,
            category: category,
            sizeBytes: 12,
            hashSha256: "hash",
            storageMode: "Indexed",
            origin: "Imported",
            sourcePath: importSingleFileSourcePath(),
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
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
        return FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: (path as NSString).deletingLastPathComponent,
            sizeBytes: 860 * 1024,
            hashSha256: hashSha256,
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_776_660_840
        )
    }
}

extension ImportSingleFilePreflightResult {
    static func importSingleFileReadyFixture(
        targetRelativePath: String = "docs/source.pdf"
    ) -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "hash",
            targetRelativePath: targetRelativePath,
            conflict: .none
        )
    }

    static func importICloudPlaceholderFixture(
        path: String = importSingleFileSourcePath(),
        targetRelativePath: String = "docs/source.pdf"
    ) -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: nil,
            hashSha256: nil,
            targetRelativePath: targetRelativePath,
            conflict: .iCloudPlaceholder(path: path)
        )
    }

    static func importHiddenDuplicateFixture() -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "hash",
            targetRelativePath: "docs/source.pdf",
            conflict: .duplicate(existingPath: "docs/source.pdf")
        )
    }

    static func importDuplicateFixture() -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "duplicate-hash",
            targetRelativePath: "docs/source.pdf",
            conflict: .duplicate(existingPath: "docs/existing.pdf"),
            keepBothTargetRelativePath: "docs/source_1.pdf"
        )
    }

    static func importDuplicateReplaceFixture(
        targetRelativePath: String? = nil,
        existingPath: String? = nil,
        keepBothTargetRelativePath: String = "docs/reports/报告_1.pdf",
        existingFile: FileEntrySnapshot = .importDuplicateReplaceFixture()
    ) -> ImportSingleFilePreflightResult {
        let targetPath = targetRelativePath ?? existingFile.path
        return ImportSingleFilePreflightResult(
            sourceSizeBytes: 912 * 1024,
            sourceModifiedAt: 1_777_445_400,
            hashSha256: "duplicate-hash",
            targetRelativePath: targetPath,
            conflict: .duplicate(existingPath: existingPath ?? existingFile.path),
            keepBothTargetRelativePath: keepBothTargetRelativePath,
            existingFile: existingFile
        )
    }

    static func importNameConflictFixture() -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "incoming-hash",
            targetRelativePath: "docs/source.pdf",
            conflict: .name(path: "docs/source.pdf"),
            keepBothTargetRelativePath: "docs/source_1.pdf",
            existingPaths: ["docs/source.pdf", "docs/source_1.pdf"]
        )
    }

    static func importNameConflictReplaceFixture(
        targetRelativePath: String? = nil,
        existingPath: String? = nil,
        keepBothTargetRelativePath: String = "docs/reports/报告_1.pdf",
        existingPaths: Set<String>? = nil,
        existingFile: FileEntrySnapshot = .importNameConflictReplaceFixture()
    ) -> ImportSingleFilePreflightResult {
        let targetPath = targetRelativePath ?? existingFile.path
        return ImportSingleFilePreflightResult(
            sourceSizeBytes: 912 * 1024,
            sourceModifiedAt: 1_777_445_400,
            hashSha256: "incoming-hash",
            targetRelativePath: targetPath,
            conflict: .name(path: existingPath ?? existingFile.path),
            keepBothTargetRelativePath: keepBothTargetRelativePath,
            existingPaths: existingPaths ?? [existingFile.path],
            existingFile: existingFile
        )
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
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: 0,
                children: [
                    RepositoryTreeNodeSnapshot(slug: "inbox", displayName: "inbox", fileCount: 0, children: []),
                    RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: 0, children: []),
                    RepositoryTreeNodeSnapshot(
                        slug: "finance",
                        displayName: "finance",
                        fileCount: 0,
                        children: []
                    )
                ]
            ),
            currentCategoryFiles: []
        )
    }
}

func makeImportSingleFileTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixImportSingleFile")
}

@MainActor
func waitForImportSingleFilePreflightToSettle(
    _ model: ImportSingleFilePreviewModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0 ..< 100 {
        if !model.preflightStatus.isChecking {
            return
        }
        await Task.yield()
    }
    XCTFail("Timed out waiting for import preflight to settle", file: file, line: line)
}

@MainActor
func importImportSingleFileMode(
    model: ImportSingleFilePreviewModel,
    request: ImportEntryRequest,
    mode: ImportSingleFileStorageMode,
    name: String,
    storageMode: String
) async {
    if mode != .copy {
        await model.load(request: request)
    }
    model.selectedCategory = " finance "
    model.selectedStorageMode = mode
    model.suggestedName = " \(name) "
    await waitForImportSingleFilePreflightToSettle(model)
    let imported = await model.importSelectedFile()
    XCTAssertEqual(imported?.storageMode, storageMode)
}
