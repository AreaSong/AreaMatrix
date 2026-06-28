@testable import AreaMatrix
import Foundation
import XCTest

final class ImportSingleFilePreflightTests: XCTestCase {
    func testCorePreflightComputesHashAndUsesCoreListFilesWithoutDuplicate() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer { removeTestTemporaryItems(sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("same bytes".utf8).write(to: sourceURL)
        let fileLoader = ImportSingleFileStaticFileLoader(files: [
            .importSingleFileFixture(currentName: "other.pdf", category: "docs", hashSha256: "other-hash")
        ])

        let result = await CoreImportSingleFilePreflight(fileLoader: fileLoader)
            .preflightSingleFileImport(request: .fixture(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                category: "docs",
                targetFilename: "source.pdf"
            ))
        let loadRequests = await fileLoader.recordedRequests()

        XCTAssertEqual(result.sourceSizeBytes, 10)
        XCTAssertEqual(result.hashSha256, "58100dc8fc06562ce3e578231dc948e083520ee49c4b4ee5a5a28bb4b4003feb")
        XCTAssertEqual(result.targetRelativePath, "docs/source.pdf")
        XCTAssertEqual(result.conflict, .none)
        XCTAssertNil(result.keepBothTargetRelativePath)
        XCTAssertNil(result.importBlockingReason())
        XCTAssertEqual(loadRequests, [ImportSingleFileFileLoadRequest(repoPath: "/tmp/repo", categories: [nil])])
    }

    func testCorePreflightDetectsDuplicateHashAndComputesKeepBothPreviewFromCoreListFiles() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer { removeTestTemporaryItems(sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("new".utf8).write(to: sourceURL)
        let duplicateHash = "11507a0e2f5e69d5dfa40a62a1bd7b6ee57e6bcd85c67c9b8431b36fff21c437"
        let fileLoader = ImportSingleFileStaticFileLoader(files: [
            .importSingleFileFixture(currentName: "existing.pdf", category: "docs", hashSha256: duplicateHash),
            .importSingleFileFixture(currentName: "source.pdf", category: "docs", hashSha256: "name-only")
        ])

        let actual = await CoreImportSingleFilePreflight(fileLoader: fileLoader)
            .preflightSingleFileImport(request: .fixture(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                category: "docs",
                targetFilename: "source.pdf"
            ))

        XCTAssertEqual(actual.sourceSizeBytes, 3)
        XCTAssertNotNil(actual.sourceModifiedAt)
        XCTAssertEqual(actual.hashSha256, duplicateHash)
        XCTAssertEqual(actual.targetRelativePath, "docs/source.pdf")
        XCTAssertEqual(actual.conflict, .duplicate(existingPath: "docs/existing.pdf"))
        XCTAssertEqual(actual.keepBothTargetRelativePath, "docs/source_1.pdf")
        XCTAssertEqual(actual.existingFile?.path, "docs/existing.pdf")
        XCTAssertEqual(actual.existingFile?.sizeBytes, 12)
        XCTAssertEqual(actual.importBlockingReason(), "请先完成 duplicate-conflict conflict-duplicate 处理")
    }

    func testCorePreflightDetectsSameNameDifferentHashForNameConflict() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-name-conflict")
        defer { removeTestTemporaryItems(sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("incoming bytes".utf8).write(to: sourceURL)
        let sameName = FileEntrySnapshot.importSingleFileFixture(
            currentName: "source.pdf",
            category: "docs",
            hashSha256: "different-hash"
        )
        let fileLoader = ImportSingleFileStaticFileLoader(files: [
            sameName,
            .importSingleFileFixture(currentName: "source_1.pdf", category: "docs", hashSha256: "other")
        ])

        let actual = await CoreImportSingleFilePreflight(fileLoader: fileLoader)
            .preflightSingleFileImport(request: .fixture(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                category: "docs",
                targetFilename: "source.pdf"
            ))

        XCTAssertEqual(actual.conflict, .name(path: "docs/source.pdf"))
        XCTAssertEqual(actual.keepBothTargetRelativePath, "docs/source_2.pdf")
        XCTAssertEqual(actual.existingPaths, ["docs/source.pdf", "docs/source_1.pdf"])
        XCTAssertEqual(actual.existingFile, sameName)
        XCTAssertEqual(actual.importBlockingReason(), "请先完成 name-conflict conflict-name 处理")
    }

    func testCorePreflightRejectsInvalidTargetFilenameBeforeImport() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer { removeTestTemporaryItems(sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("new".utf8).write(to: sourceURL)

        let result = await CoreImportSingleFilePreflight(
            fileLoader: ImportSingleFileStaticFileLoader(files: [])
        ).preflightSingleFileImport(request: .fixture(
            repoPath: "/tmp/repo",
            sourceURL: sourceURL,
            category: "docs",
            targetFilename: "bad/name.pdf"
        ))

        XCTAssertEqual(result.hashSha256, nil)
        XCTAssertEqual(
            result.conflict,
            .invalidFilename("文件名不能包含 / \\ : * ? \" < > |")
        )
        XCTAssertEqual(
            result.importBlockingReason(),
            "文件名不能包含 / \\ : * ? \" < > |"
        )
    }

    func testCorePreflightBlocksICloudPlaceholderBeforeCorePreviewCall() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer { removeTestTemporaryItems(sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf.icloud")

        let fileLoader = ImportSingleFileStaticFileLoader(files: [])

        let result = await CoreImportSingleFilePreflight(fileLoader: fileLoader)
            .preflightSingleFileImport(request: .fixture(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                category: "docs",
                targetFilename: "source.pdf"
            ))

        let loadRequests = await fileLoader.recordedRequests()

        XCTAssertEqual(result.conflict, .iCloudPlaceholder(path: sourceURL.path))
        XCTAssertEqual(result.importBlockingReason(), "iCloud placeholder 需要下载后才能导入")
        XCTAssertEqual(loadRequests, [])
    }
}
