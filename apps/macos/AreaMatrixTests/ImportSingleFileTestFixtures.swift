import Foundation
import XCTest
@testable import AreaMatrix

extension ClassifyResultSnapshot {
    static func s117Fixture() -> ClassifyResultSnapshot {
        makeImportSingleFileFixture()
    }

    static func importSingleFileFixture() -> ClassifyResultSnapshot {
        makeImportSingleFileFixture()
    }

    private static func makeImportSingleFileFixture() -> ClassifyResultSnapshot {
        ClassifyResultSnapshot(
            category: "docs",
            suggestedName: "source.pdf",
            reason: .extension,
            confidence: 0.7
        )
    }
}

extension FileEntrySnapshot {
    static func s117Fixture(
        currentName: String,
        category: String,
        storageMode: String = "Copied"
    ) -> FileEntrySnapshot {
        makeImportSingleFileFixture(
            id: 117,
            currentName: currentName,
            category: category,
            storageMode: storageMode
        )
    }

    static func importSingleFileFixture(
        currentName: String,
        category: String,
        storageMode: String = "Copied"
    ) -> FileEntrySnapshot {
        makeImportSingleFileFixture(
            id: 42,
            currentName: currentName,
            category: category,
            storageMode: storageMode
        )
    }

    private static func makeImportSingleFileFixture(
        id: Int64,
        currentName: String,
        category: String,
        storageMode: String
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "\(category)/\(currentName)",
            originalName: "source.pdf",
            currentName: currentName,
            category: category,
            sizeBytes: 12,
            hashSha256: "hash",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: "/tmp/source.pdf",
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }
}

extension ImportEntryRequest {
    static func s117ImportRequest() -> ImportEntryRequest {
        ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: "/tmp/source.pdf")],
            kind: .singleFile
        )
    }

    static func importSingleFileFixture(
        allowReplaceDuringImport: Bool = true,
        isTrashAvailable: Bool = true
    ) -> ImportEntryRequest {
        ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: "/tmp/source.pdf")],
            kind: .singleFile,
            allowReplaceDuringImport: allowReplaceDuringImport,
            isTrashAvailable: isTrashAvailable
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func s117Error(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        makeImportSingleFileError(
            kind: kind,
            suggestedAction: "Resolve the conflict and retry.",
            rawContext: "S1-17 import-single-sheet"
        )
    }

    static func importCopyFixture(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        makeImportSingleFileError(
            kind: kind,
            suggestedAction: "Choose a different file or resolve the conflict.",
            rawContext: "copy import"
        )
    }

    private static func makeImportSingleFileError(
        kind: CoreErrorKindSnapshot,
        suggestedAction: String,
        rawContext: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "Import failed",
            severity: .high,
            suggestedAction: suggestedAction,
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }
}

extension ImportSingleFileStorageMode {
    var coreStorageMode: String {
        switch self {
        case .copy:
            return "Copied"
        case .move:
            return "Moved"
        case .indexOnly:
            return "Indexed"
        }
    }
}

extension RepositoryOpeningResult {
    static func s117Fixture(repoPath: String) -> RepositoryOpeningResult {
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
                    ),
                ]
            ),
            currentCategoryFiles: []
        )
    }
}

func makeImportSingleFileTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixImportSingleFile-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
func waitForImportSingleFilePreflightToSettle(
    _ model: ImportSingleFilePreviewModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    for _ in 0..<100 {
        if !model.preflightStatus.isChecking {
            return
        }
        await Task.yield()
    }
    XCTFail("Timed out waiting for import preflight to settle", file: file, line: line)
}
