@testable import AreaMatrix
import XCTest

final class ImportSingleFileMoveImportTests: XCTestCase {
    @MainActor
    func testMoveImportCallsImportMoveFileCoreImporterWithEditedCategoryAndFilename() async {
        let sourceURL = importSingleFileSourceURL()
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(.importSingleFileFixture())
        ])
        let movedEntry = FileEntrySnapshot.importMoveFixture(
            currentName: "moved.pdf",
            category: "docs"
        )
        let importer = ImportSingleFileRecordingImporter(results: [.success(movedEntry)])
        let model = makeImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: RecordingCoreErrorMapper.importMove()
        )
        let request = ImportEntryRequest.importSingleFileImportRequest(sourcePath: sourceURL.path)

        await model.load(request: request)
        model.selectedStorageMode = .move
        model.selectedCategory = " docs "
        model.suggestedName = " moved.pdf "
        await waitForImportSingleFilePreflightToSettle(model)
        await model.importSelectedFile()
        let requests = await importer.recordedCoreRequests()

        XCTAssertEqual(requests, [
            ImportSingleFileCoreImportRequest(
                repoPath: importSingleFileRepoPath(),
                sourceURL: sourceURL,
                mode: .move,
                overrideCategory: "docs",
                overrideFilename: "moved.pdf"
            )
        ])
        XCTAssertEqual(model.importStatus, .imported(movedEntry))
    }

    @MainActor
    func testMoveImportMapsCoreFailureWithoutCreatingStaticSuccess() async {
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(.importSingleFileFixture())
        ])
        let importer = ImportSingleFileRecordingImporter(results: [
            .failure(CoreError.PermissionDenied(path: importSingleFileSourcePath()))
        ])
        let errorMapper = RecordingCoreErrorMapper.importMove()
        let model = makeImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: errorMapper
        )
        let request = ImportEntryRequest.importSingleFileImportRequest()

        await model.load(request: request)
        model.selectedStorageMode = .move
        await model.importSelectedFile()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: importSingleFileSourcePath())])
        XCTAssertEqual(
            model.importStatus,
            .failed(CoreErrorMappingSnapshot.importMoveFixture(kind: .permissionDenied))
        )
    }

    func testDefaultCoreBridgeImportsMovedFileAndRemovesSource() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "move-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "move-source")
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("move.pdf")
        try Data("move bytes".utf8).write(to: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importMovedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "moved.pdf"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(entry.currentName, "moved.pdf")
        XCTAssertEqual(entry.category, "docs")
        XCTAssertEqual(entry.storageMode, "Moved")
        XCTAssertEqual(entry.sourcePath, sourceURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(entry.path).path))
    }
}
