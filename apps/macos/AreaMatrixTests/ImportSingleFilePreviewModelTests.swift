@testable import AreaMatrix
import XCTest

final class ImportSingleFilePreviewModelTests: XCTestCase {
    @MainActor
    func testSingleFileSheetCallsCorePredictorAndPrefillsVisibleFields() async {
        let sourceURL = importSingleFileContractURL()
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(.importSingleFileFixture(
                category: "docs",
                suggestedName: "2026Q1_合同_客户A.pdf",
                reason: .keyword,
                confidence: 0.93
            ))
        ])
        let request = ImportEntryRequest.importSingleFileImportRequest(sourcePath: sourceURL.path)
        let model = makeImportSingleFilePreviewModel(
            predictor: predictor,
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: RecordingCoreErrorMapper.importCopy()
        )

        await model.load(request: request)
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [
            ImportSingleFilePredictRequest(repoPath: importSingleFileRepoPath(), filename: "合同.pdf")
        ])
        XCTAssertEqual(model.source?.fileName, "合同.pdf")
        XCTAssertEqual(model.selectedCategory, "docs")
        XCTAssertEqual(model.suggestedName, "2026Q1_合同_客户A.pdf")
        XCTAssertEqual(model.selectedStorageMode, .copy)
        XCTAssertEqual(model.reasonSummary, "keyword · 93%")
        XCTAssertEqual(model.status, .ready)
    }

    @MainActor
    func testExplicitCategoryKeepsUserSelectedDestinationWhileStillPreviewingName() async {
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(.importSingleFileFixture(
                category: "docs",
                suggestedName: "2026Q1_合同_客户A.pdf",
                reason: .extension,
                confidence: 0.8
            ))
        ])
        let request = ImportEntryRequest.importSingleFileImportRequest(
            source: .dropZone,
            destination: .category("finance"),
            sourcePath: importSingleFileContractURL().path
        )
        let model = makeImportSingleFilePreviewModel(
            predictor: predictor,
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: RecordingCoreErrorMapper.importCopy()
        )

        await model.load(request: request)

        XCTAssertEqual(model.selectedCategory, "finance")
        XCTAssertEqual(model.prediction?.category, "docs")
        XCTAssertEqual(model.suggestedName, "2026Q1_合同_客户A.pdf")
        XCTAssertEqual(model.status, .ready)
    }

    @MainActor
    func testClassificationFailureDoesNotCreateStaticPreviewSuccess() async {
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .failure(CoreError.Classify(reason: "classifier unavailable"))
        ])
        let request = ImportEntryRequest.importSingleFileImportRequest()
        let model = makeImportSingleFilePreviewModel(
            predictor: predictor,
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: RecordingCoreErrorMapper.importCopy()
        )

        await model.load(request: request)

        XCTAssertNil(model.prediction)
        XCTAssertEqual(model.selectedCategory, "inbox")
        XCTAssertEqual(model.suggestedName, "source.pdf")
        XCTAssertEqual(model.status, .failed("无法预览分类：classifier unavailable"))
    }

    @MainActor
    func testNonSingleFileRequestSkipsClassifyPreviewCorePredictor() async {
        let predictor = ImportSingleFileRecordingPredictor(results: [])
        let request = ImportEntryRequest(
            repoPath: importSingleFileRepoPath(),
            source: .filePicker,
            destination: .autoClassify,
            urls: [
                URL(fileURLWithPath: "/tmp/a.pdf"),
                URL(fileURLWithPath: "/tmp/b.pdf")
            ],
            kind: .multipleItems(2)
        )
        let model = makeImportSingleFilePreviewModel(
            predictor: predictor,
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: RecordingCoreErrorMapper.importCopy()
        )

        await model.load(request: request)
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertNil(model.prediction)
        XCTAssertEqual(model.status, .unsupported("此 sheet 只处理单文件导入"))
    }

    @MainActor
    func testCopyImportCallsImportCopyFileCoreImporterWithEditedCategoryAndFilename() async {
        let sourceURL = importSingleFileSourceURL()
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(.importSingleFileFixture())
        ])
        let importedEntry = FileEntrySnapshot.importSingleFileFixture(
            currentName: "contract.pdf",
            category: "legal"
        )
        let importer = ImportSingleFileRecordingImporter(results: [.success(importedEntry)])
        let model = makeImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: RecordingCoreErrorMapper.importCopy()
        )
        let request = ImportEntryRequest.importSingleFileImportRequest(sourcePath: sourceURL.path)

        await model.load(request: request)
        model.selectedCategory = " legal "
        model.suggestedName = " contract.pdf "
        await waitForImportSingleFilePreflightToSettle(model)
        await model.importSelectedFile()
        let requests = await importer.recordedCoreRequests()

        XCTAssertEqual(requests, [
            ImportSingleFileCoreImportRequest(
                repoPath: importSingleFileRepoPath(),
                sourceURL: sourceURL,
                mode: .copy,
                overrideCategory: "legal",
                overrideFilename: "contract.pdf",
                duplicateStrategy: .ask
            )
        ])
        XCTAssertEqual(model.importStatus, .imported(importedEntry))
    }

    @MainActor
    func testCopyImportMapsNonDuplicateCoreFailureWithoutCreatingStaticSuccess() async {
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(.importSingleFileFixture())
        ])
        let importer = ImportSingleFileRecordingImporter(results: [
            .failure(CoreError.PermissionDenied(path: importSingleFileSourcePath()))
        ])
        let errorMapper = RecordingCoreErrorMapper.importCopy()
        let model = makeImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: errorMapper
        )
        let request = ImportEntryRequest.importSingleFileImportRequest()

        await model.load(request: request)
        await model.importSelectedFile()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: importSingleFileSourcePath())])
        XCTAssertEqual(
            model.importStatus,
            .failed(CoreErrorMappingSnapshot.importCopyFixture(kind: .permissionDenied))
        )
    }

    @MainActor
    func testImportRequiresCompletedPreview() async {
        let importer = ImportSingleFileRecordingImporter(results: [])
        let model = makeImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(results: []),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: RecordingCoreErrorMapper.importCopy()
        )

        await model.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.importStatus, .blocked("没有可导入的单文件来源"))
    }

    @MainActor
    func testEditingImportFieldsImmediatelyInvalidatesExistingPreflight() async {
        let model = makeImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(results: [.success(.importSingleFileFixture())]),
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: RecordingCoreErrorMapper.importCopy()
        )

        await model.load(request: .importSingleFileFixture())
        XCTAssertNil(model.importDisabledReason)

        model.suggestedName = "renamed.pdf"

        XCTAssertEqual(model.importDisabledReason, "Checking duplicate...")
    }

    @MainActor
    func testICloudPlaceholderRequiresDownloadAndRetryBeforeImport() async {
        let result = ImportSingleFilePreflightResult.importICloudPlaceholderFixture()
        let importer = ImportSingleFileRecordingImporter(results: [])
        let model = makeImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(results: [.success(.importSingleFileFixture())]),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: result),
            placeholderDownloader: ImportSingleFileStaticICloudDownloader(),
            errorMapper: RecordingCoreErrorMapper.importCopy()
        )

        await model.load(request: .importSingleFileFixture())
        XCTAssertTrue(model.showsICloudActions)
        XCTAssertEqual(model.importDisabledReason, "iCloud placeholder 需要下载后才能导入")

        let imported = await model.importSelectedFile()
        let requests = await importer.recordedRequests()
        XCTAssertNil(imported)
        XCTAssertEqual(requests, [])
    }

    @MainActor
    func testICloudDownloadFailureKeepsRecoveryActionsVisibleOnSheet() async {
        let result = ImportSingleFilePreflightResult.importICloudPlaceholderFixture()
        let model = makeImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(results: [.success(.importSingleFileFixture())]),
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight(result: result),
            placeholderDownloader: ImportSingleFileStaticICloudDownloader(
                error: ImportSingleFileStaticLocalizedError(message: "network offline")
            ),
            errorMapper: RecordingCoreErrorMapper.importCopy()
        )

        await model.load(request: .importSingleFileFixture())
        await model.downloadICloudPlaceholderAndRetry()

        XCTAssertTrue(model.showsICloudActions)
        XCTAssertFalse(model.showsRetryPreviewAction)
        XCTAssertNil(model.activeConflictPage)
        XCTAssertEqual(model.importDisabledReason, "iCloud 下载失败后请重试下载或切换本地资料库")
        guard case let .iCloudDownloadFailed(path, reason) = model.currentPreflightResult?.conflict else {
            return XCTFail("Expected iCloud download failure to remain in iCloud recovery state")
        }
        XCTAssertEqual(path, importSingleFileSourcePath())
        XCTAssertEqual(reason, "network offline")
    }
}
