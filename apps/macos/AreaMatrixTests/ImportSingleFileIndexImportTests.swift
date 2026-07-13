@testable import AreaMatrix
import XCTest

final class ImportSingleFileIndexImportTests: XCTestCase {
    @MainActor
    func testIndexOnlyImportCallsImportIndexFileCoreImporterWithEditedCategoryAndFilename() async {
        let sourceURL = importSingleFileSourceURL()
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(.importSingleFileFixture())
        ])
        let indexedEntry = FileEntrySnapshot.importIndexFixture(
            currentName: "indexed.pdf",
            category: "docs"
        )
        let importer = ImportSingleFileRecordingImporter(results: [.success(indexedEntry)])
        let model = makeImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: RecordingCoreErrorMapper.importIndex()
        )
        let request = ImportEntryRequest.importSingleFileImportRequest(sourcePath: sourceURL.path)

        await model.load(request: request)
        model.selectedStorageMode = .indexOnly
        model.selectedCategory = " docs "
        model.suggestedName = " indexed.pdf "
        await waitForImportSingleFilePreflightToSettle(model)
        await model.importSelectedFile()

        await importer.assertCoreImportRequests([
            ImportSingleFileCoreImportRequest(
                repoPath: importSingleFileRepoPath(),
                sourceURL: sourceURL,
                mode: .indexOnly,
                overrideCategory: "docs",
                overrideFilename: "indexed.pdf"
            )
        ])
        XCTAssertEqual(model.importStatus, .imported(indexedEntry))
    }

    @MainActor
    func testIndexOnlyImportMapsCoreFailureWithoutCreatingStaticSuccess() async {
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(.importSingleFileFixture())
        ])
        let importer = ImportSingleFileRecordingImporter(results: [
            .failure(CoreError.ICloudPlaceholder(path: importSingleFileSourcePath()))
        ])
        let errorMapper = RecordingCoreErrorMapper.importIndex()
        let model = makeImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: errorMapper
        )
        let request = ImportEntryRequest.importSingleFileImportRequest()

        await model.load(request: request)
        model.selectedStorageMode = .indexOnly
        await model.importSelectedFile()

        await errorMapper.assertMappedCoreErrors([CoreError.ICloudPlaceholder(path: importSingleFileSourcePath())])
        XCTAssertEqual(
            model.importStatus,
            .failed(CoreErrorMappingSnapshot.importIndexFixture(kind: .iCloudPlaceholder))
        )
    }

    func testDefaultCoreBridgeImportsIndexedFileWithoutMovingOrCopyingSource() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "index-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "index-source")
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("indexed.pdf")
        try Data("indexed bytes".utf8).write(to: sourceURL)
        let sourceBefore = try Data(contentsOf: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importIndexedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "indexed-display.pdf"
        )

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertEqual(entry.currentName, "indexed-display.pdf")
        XCTAssertEqual(entry.category, "docs")
        XCTAssertEqual(entry.storageMode, "Indexed")
        XCTAssertEqual(entry.sourcePath, sourceURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(entry.path).path))
    }
}
