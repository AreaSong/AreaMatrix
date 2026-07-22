@testable import AreaMatrix
import XCTest

final class ImportDropBatchPreviewTests: XCTestCase {
    @MainActor
    func testBatchPreviewCallsPredictorForEachFileAndUsesRealPredictions() async {
        let fixture = importBatchStandardBatchFixture()
        let predictor = ImportDropRecordingPredictor(results: importDropStandardBatchPredictions())
        let model = ImportBatchPreviewModel(predictor: predictor)

        await model.load(request: fixture.request)
        await predictor.assertCategoryPredictionRequests([
            ImportDropPredictRequest(repoPath: "/tmp/repo", filename: "Invoice_2026Q1.pdf"),
            ImportDropPredictRequest(repoPath: "/tmp/repo", filename: "合同.pdf")
        ])
        XCTAssertEqual(model.rows.count, 2)
        XCTAssertEqual(model.rows[0].predictedCategory, "finance")
        XCTAssertEqual(model.rows[1].predictedCategory, "docs")
        XCTAssertEqual(model.rows[1].suggestedName, "2026Q1_合同.pdf")
        assertImportRowStatusTags(model.rows, ["OK", "OK"])
        assertImportStatusMessage(model.status, "Completed the import preview for 2 files")
        assertImportEnabled(model.importDisabledReason)
    }

    @MainActor
    func testBatchPreviewMapsClassifyFailuresAndDuplicatePrecheckPerRow() async {
        let goodURL = importBatchInvoiceURL()
        let duplicateURL = URL(fileURLWithPath: "/tmp/Duplicate.pdf")
        let badURL = URL(fileURLWithPath: "/tmp/Bad.pdf")
        let predictor = ImportDropRecordingPredictor(results: importDropFailurePreviewPredictions())
        let duplicatePrechecker = ImportBatchStaticDuplicatePrechecker(results: [
            duplicateURL.path: .duplicate(existingPath: "finance/existing.pdf")
        ])
        let model = ImportBatchPreviewModel(
            predictor: predictor,
            duplicatePrechecker: duplicatePrechecker
        )
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [goodURL, duplicateURL, badURL],
            kind: .multipleItems(3),
            availableCategories: ["inbox", "finance"]
        )

        await model.load(request: request)
        await duplicatePrechecker.assertPrecheckedDuplicateSources(repoPath: "/tmp/repo", paths: [
            "/tmp/Invoice_2026Q1.pdf",
            "/tmp/Duplicate.pdf",
            "/tmp/Bad.pdf"
        ])
        XCTAssertEqual(model.successfulPreviewCount, 2)
        XCTAssertEqual(model.failedPreviewCount, 1)
        assertImportRowStatusTags(model.rows, ["OK", "DUP", "ERROR"])
        assertImportRowStatusDetails(model.rows, [
            1: "Skip: finance/existing.pdf",
            2: "Classification rules are invalid: classifier.yaml line 7"
        ])
        assertImportStatusMessage(model.status, "Prepared 2/3 file previews; 1 failed")
        XCTAssertTrue(model.showsRetryPreview)
    }

    @MainActor
    func testBatchPreviewDuplicatePrecheckFeedsImportBatchConflictRowsBeforeImport() async {
        let fixture = importBatchStandardBatchFixture()
        let predictor = ImportDropRecordingPredictor(results: importDropStandardBatchPredictions())
        let duplicatePrechecker = ImportBatchStaticDuplicatePrechecker(results: [
            fixture.invoiceURL.path: .duplicate(existingPath: "finance/existing-invoice.pdf")
        ])
        let previewModel = ImportBatchPreviewModel(
            predictor: predictor,
            duplicatePrechecker: duplicatePrechecker
        )
        let importModel = ImportBatchCopyImportModel(
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        await previewModel.load(request: fixture.request)
        importModel.applyPreviewRows(
            previewModel.rows,
            request: fixture.request,
            selectedDestination: previewModel.selectedDestination
        )

        assertImportRowStatusTags(previewModel.rows, ["DUP", "OK"])
        XCTAssertEqual(importModel.duplicateCount, 1)
        assertImportRowStatusTags(importModel.rows, ["DUP", "OK"])
        assertImportRowStatusDetails(importModel.rows, [0: "Skip: finance/existing-invoice.pdf"])
        assertImportEnabled(importModel.importDisabledReason)
    }

    @MainActor
    func testBatchPreviewUsesRealCoreMetadataForDuplicateAndNameConflictPrecheck() async throws {
        let fixture = try makeImportDropMetadataPrecheckFixture()
        defer { removeTestTemporaryItems(fixture.sourceRoot) }
        let predictor = ImportDropRecordingPredictor(results: importDropMetadataPrecheckPredictions())
        let duplicateFileLoader = ImportBatchStaticBatchFileLoader(pagesByCategory: [
            "__all__": [[fixture.duplicateFile, fixture.nameConflictFile]]
        ])
        let nameConflictFileLoader = ImportBatchStaticBatchFileLoader(pagesByCategory: [
            "docs": [[fixture.nameConflictFile]]
        ])
        let model = ImportBatchPreviewModel(
            predictor: predictor,
            duplicatePrechecker: CoreImportBatchDuplicatePrechecker(fileLoader: duplicateFileLoader),
            nameConflictPrechecker: CoreImportBatchNameConflictPrechecker(fileLoader: nameConflictFileLoader)
        )
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [fixture.invoiceURL, fixture.contractURL],
            kind: .multipleItems(2),
            availableCategories: ["inbox", "docs", "finance"]
        )

        await model.load(request: request)

        assertImportRowStatusTags(model.rows, ["DUP", "NAME"])
        assertImportRowStatusDetails(model.rows, [
            0: "Skip: finance/existing-invoice.pdf",
            1: "Keep both (auto-number): docs/合同.pdf"
        ])
        XCTAssertEqual(model.successfulPreviewCount, 2)
        XCTAssertEqual(model.failedPreviewCount, 0)
        await duplicateFileLoader.assertLoadedAllFilesForDuplicatePrecheck()
        await nameConflictFileLoader.assertLoadedFilesForNameConflictPrecheck(categories: ["docs"])
    }

    func testDefaultCoreBridgeBatchDuplicateDetectionUsesImportFileDuplicateError() async throws {
        let repoURL = try makeImportDropTemporaryRepositoryURL()
        let sourceRoot = try makeImportDropTemporaryDirectory(prefix: "duplicate-source")
        defer {
            removeTestTemporaryItems(repoURL, sourceRoot)
        }

        let firstURL = sourceRoot.appendingPathComponent("existing.pdf")
        let duplicateURL = sourceRoot.appendingPathComponent("incoming.pdf")
        try Data("same duplicate bytes".utf8).write(to: firstURL)
        try Data("same duplicate bytes".utf8).write(to: duplicateURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let imported = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: firstURL,
            destination: .category("finance"),
            suggestedCategory: "finance",
            overrideFilename: "existing.pdf"
        )

        do {
            _ = try await bridge.importCopiedFile(
                repoPath: repoURL.path,
                sourceURL: duplicateURL,
                destination: .category("finance"),
                suggestedCategory: "finance",
                overrideFilename: "incoming.pdf"
            )
            XCTFail("Expected import_file to return DuplicateFile for duplicate content")
        } catch let CoreError.DuplicateFile(existingPath) {
            XCTAssertEqual(existingPath, imported.path)
        } catch {
            XCTFail("Expected DuplicateFile, got \(error)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicateURL.path))
    }
}

private struct ImportBatchDuplicatePrecheckRequest: Equatable {
    var repoPath: String
    var paths: [String]
}

private struct ImportDropMetadataPrecheckFixture {
    let sourceRoot: URL
    let invoiceURL: URL
    let contractURL: URL
    let duplicateFile: FileEntrySnapshot
    let nameConflictFile: FileEntrySnapshot
}

private actor ImportBatchStaticDuplicatePrechecker: ImportBatchDuplicatePrechecking {
    private let results: [String: ImportBatchDuplicatePrecheckResult]
    private var requests: [ImportBatchDuplicatePrecheckRequest] = []

    init(results: [String: ImportBatchDuplicatePrecheckResult]) {
        self.results = results
    }

    func precheckDuplicates(
        repoPath: String,
        sourceURLs: [URL],
        destination _: ImportBatchDestinationOption
    ) async -> [String: ImportBatchDuplicatePrecheckResult] {
        requests.append(ImportBatchDuplicatePrecheckRequest(
            repoPath: repoPath,
            paths: sourceURLs.map(\.path)
        ))
        return results
    }

    func assertPrecheckedDuplicateSources(
        repoPath: String,
        paths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            requests,
            [ImportBatchDuplicatePrecheckRequest(repoPath: repoPath, paths: paths)],
            file: file,
            line: line
        )
    }

    func assertNoDuplicatePrechecks(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, [], file: file, line: line)
    }
}

private func importDropStandardBatchPredictions() -> [Result<ClassifyResultSnapshot, Error>] {
    [
        .success(.importBatchPrediction(category: "finance", suggestedName: "Invoice_2026Q1.pdf")),
        .success(.importBatchPrediction(category: "docs", suggestedName: "2026Q1_合同.pdf", confidence: 0.82))
    ]
}

private func importDropFailurePreviewPredictions() -> [Result<ClassifyResultSnapshot, Error>] {
    [
        .success(.importBatchPrediction(category: "finance", suggestedName: "Invoice_2026Q1.pdf")),
        .success(.importBatchPrediction(category: "finance", suggestedName: "Duplicate.pdf", confidence: 0.7)),
        .failure(CoreError.Config(reason: "classifier.yaml line 7"))
    ]
}

private func importDropMetadataPrecheckPredictions() -> [Result<ClassifyResultSnapshot, Error>] {
    [
        .success(.importBatchPrediction(category: "finance", suggestedName: "Invoice_2026Q1.pdf")),
        .success(.importBatchPrediction(category: "docs", suggestedName: "合同.pdf", confidence: 0.82))
    ]
}

private func makeImportDropMetadataPrecheckFixture() throws -> ImportDropMetadataPrecheckFixture {
    let sourceRoot = try makeImportDropTemporaryDirectory(prefix: "batch-precheck-source")
    let invoiceURL = sourceRoot.appendingPathComponent("Invoice_2026Q1.pdf")
    let contractURL = sourceRoot.appendingPathComponent("合同.pdf")
    try Data("same duplicate bytes".utf8).write(to: invoiceURL)
    try Data("unique contract bytes".utf8).write(to: contractURL)
    let duplicateHash = try ImportSingleFileHasher.sha256Hex(for: invoiceURL)
    return ImportDropMetadataPrecheckFixture(
        sourceRoot: sourceRoot,
        invoiceURL: invoiceURL,
        contractURL: contractURL,
        duplicateFile: .importSingleFileFixture(
            currentName: "existing-invoice.pdf",
            category: "finance",
            hashSha256: duplicateHash
        ),
        nameConflictFile: .importSingleFileFixture(
            currentName: "合同.pdf",
            category: "docs",
            hashSha256: "different-contract-hash"
        )
    )
}
