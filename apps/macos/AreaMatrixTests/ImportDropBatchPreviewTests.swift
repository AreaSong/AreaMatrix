@testable import AreaMatrix
import XCTest

final class ImportDropBatchPreviewTests: XCTestCase {
    @MainActor
    func testBatchPreviewCallsPredictorForEachFileAndUsesRealPredictions() async {
        let fixture = importBatchStandardBatchFixture()
        let predictor = ImportDropRecordingPredictor(results: importDropStandardBatchPredictions())
        let model = ImportBatchPreviewModel(predictor: predictor)

        await model.load(request: fixture.request)
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [
            ImportDropPredictRequest(repoPath: "/tmp/repo", filename: "Invoice_2026Q1.pdf"),
            ImportDropPredictRequest(repoPath: "/tmp/repo", filename: "合同.pdf")
        ])
        XCTAssertEqual(model.rows.count, 2)
        XCTAssertEqual(model.rows[0].predictedCategory, "finance")
        XCTAssertEqual(model.rows[1].predictedCategory, "docs")
        XCTAssertEqual(model.rows[1].suggestedName, "2026Q1_合同.pdf")
        XCTAssertEqual(model.rows[0].status.tag, "OK")
        XCTAssertEqual(model.rows[1].status.tag, "OK")
        XCTAssertEqual(model.status.message, "已完成 2 个文件的导入预览")
        XCTAssertNil(model.importDisabledReason)
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
        let precheckRequests = await duplicatePrechecker.recordedRequests()

        XCTAssertEqual(precheckRequests, [
            ImportBatchDuplicatePrecheckRequest(repoPath: "/tmp/repo", paths: [
                "/tmp/Invoice_2026Q1.pdf",
                "/tmp/Duplicate.pdf",
                "/tmp/Bad.pdf"
            ])
        ])
        XCTAssertEqual(model.successfulPreviewCount, 2)
        XCTAssertEqual(model.failedPreviewCount, 1)
        XCTAssertEqual(model.rows[0].status.tag, "OK")
        XCTAssertEqual(model.rows[1].status.tag, "DUP")
        XCTAssertEqual(model.rows[1].status.detail, "Skip: finance/existing.pdf")
        XCTAssertEqual(model.rows[2].status.tag, "ERROR")
        XCTAssertEqual(model.rows[2].status.detail, "分类规则无效：classifier.yaml line 7")
        XCTAssertEqual(model.status.message, "已完成 2/3 个文件的导入预览，1 个失败")
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

        XCTAssertEqual(previewModel.rows.map(\.status.tag), ["DUP", "OK"])
        XCTAssertEqual(importModel.duplicateCount, 1)
        XCTAssertEqual(importModel.rows.map(\.status.tag), ["DUP", "OK"])
        XCTAssertEqual(importModel.rows.first?.status.detail, "Skip: finance/existing-invoice.pdf")
        XCTAssertNil(importModel.importDisabledReason)
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
        let duplicateRequests = await duplicateFileLoader.recordedRequests()
        let nameConflictRequests = await nameConflictFileLoader.recordedRequests()

        XCTAssertEqual(model.rows.map(\.status.tag), ["DUP", "NAME"])
        XCTAssertEqual(model.rows[0].status.detail, "Skip: finance/existing-invoice.pdf")
        XCTAssertEqual(model.rows[1].status.detail, "Keep both (auto-number): docs/合同.pdf")
        XCTAssertEqual(model.successfulPreviewCount, 2)
        XCTAssertEqual(model.failedPreviewCount, 0)
        XCTAssertEqual(duplicateRequests, [
            .testFixture(limit: 200)
        ])
        XCTAssertEqual(nameConflictRequests, [
            .testFixture(category: "docs", limit: 200)
        ])
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

    func recordedRequests() -> [ImportBatchDuplicatePrecheckRequest] {
        requests
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
