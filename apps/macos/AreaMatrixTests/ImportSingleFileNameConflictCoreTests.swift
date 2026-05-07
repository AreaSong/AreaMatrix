import XCTest
@testable import AreaMatrix

final class ImportSingleFileNameConflictCoreTests: XCTestCase {
    @MainActor
    func testS123RealCoreSameNameDifferentContentDefaultsToNumberedKeepBothImport() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s123-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "s123-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let existingURL = sourceRoot.appendingPathComponent("existing.pdf")
        let incomingURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("existing bytes".utf8).write(to: existingURL)
        try Data("incoming bytes".utf8).write(to: incomingURL)

        let model = try await makeNameConflictModel(
            repoURL: repoURL,
            existingURL: existingURL,
            incomingURL: incomingURL
        )

        XCTAssertEqual(model.activeConflictPage, .name)
        XCTAssertEqual(model.currentPreflightResult?.conflict, .name(path: "docs/source.pdf"))
        XCTAssertEqual(model.currentPreflightResult?.keepBothTargetRelativePath, "docs/source_1.pdf")
        XCTAssertEqual(model.nameConflictResolution, .keepBoth)

        let imported = await model.importSelectedFile()
        let docsURL = repoURL.appendingPathComponent("docs")
        let repoFiles = try FileManager.default.contentsOfDirectory(atPath: docsURL.path)

        XCTAssertEqual(model.progressCurrentPath, "docs/source_1.pdf")
        XCTAssertEqual(imported?.path, "docs/source_1.pdf")
        XCTAssertEqual(repoFiles.sorted(), ["source.pdf", "source_1.pdf"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: incomingURL.path))
    }

    @MainActor
    func testS123RealCoreRenameIncomingUsesEditedSafeName() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s123-rename-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "s123-rename-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let existingURL = sourceRoot.appendingPathComponent("existing.pdf")
        let incomingURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("existing bytes".utf8).write(to: existingURL)
        try Data("incoming bytes".utf8).write(to: incomingURL)

        let model = try await makeNameConflictModel(
            repoURL: repoURL,
            existingURL: existingURL,
            incomingURL: incomingURL
        )
        model.renameIncomingNameConflictFile(to: "renamed.pdf")

        let imported = await model.importSelectedFile()

        XCTAssertEqual(model.progressCurrentPath, "docs/renamed.pdf")
        XCTAssertEqual(imported?.path, "docs/renamed.pdf")
        XCTAssertEqual(imported?.currentName, "renamed.pdf")
    }

    @MainActor
    private func makeNameConflictModel(
        repoURL: URL,
        existingURL: URL,
        incomingURL: URL
    ) async throws -> ImportSingleFilePreviewModel {
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        _ = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: existingURL,
            overrideCategory: "docs",
            overrideFilename: "source.pdf"
        )

        let model = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: bridge,
            preflight: CoreImportSingleFilePreflight(),
            errorMapper: S117RecordingErrorMapper()
        )
        await model.load(request: ImportEntryRequest(
            repoPath: repoURL.path,
            source: .filePicker,
            destination: .autoClassify,
            urls: [incomingURL],
            kind: .singleFile
        ))
        return model
    }
}
