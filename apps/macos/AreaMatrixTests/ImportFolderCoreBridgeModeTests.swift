import XCTest
@testable import AreaMatrix

final class ImportFolderCoreBridgeModeTests: XCTestCase {
    @MainActor
    func testDefaultCoreBridgeFolderCopyImportKeepsSourceAndCreatesRepoCopy() async throws {
        let repoURL = try makeImportFolderTemporaryDirectory()
        let sourceRoot = try makeImportFolderTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        let sourceURL = sourceRoot.appendingPathComponent("invoice.pdf")
        try Data("invoice bytes".utf8).write(to: sourceURL)
        let sourceBefore = try Data(contentsOf: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            destination: .autoClassify,
            suggestedCategory: "finance",
            overrideFilename: "folder-invoice.pdf"
        )

        XCTAssertEqual(entry.currentName, "folder-invoice.pdf")
        XCTAssertEqual(entry.category, "finance")
        XCTAssertEqual(entry.storageMode, "Copied")
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(entry.path).path))
    }

    @MainActor
    func testDefaultCoreBridgeFolderIndexOnlyImportKeepsSourceWithoutRepoCopy() async throws {
        let repoURL = try makeImportFolderTemporaryDirectory()
        let sourceRoot = try makeImportFolderTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        let sourceURL = sourceRoot.appendingPathComponent("reference.pdf")
        try Data("reference bytes".utf8).write(to: sourceURL)
        let sourceBefore = try Data(contentsOf: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importBatchFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            storageMode: .indexOnly,
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "reference-index.pdf",
            duplicateStrategy: .ask
        )

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertEqual(entry.currentName, "reference-index.pdf")
        XCTAssertEqual(entry.category, "docs")
        XCTAssertEqual(entry.storageMode, "Indexed")
        XCTAssertEqual(entry.sourcePath, sourceURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(entry.path).path))
    }
}
