@testable import AreaMatrix
import XCTest

final class ImportFolderPreviewModelTests: XCTestCase {
    @MainActor
    func testImportFolderFolderPreviewScansFolderAndCallsClassifyPreviewCorePredictorForEachReadyFile() async throws {
        let rootURL = try makeImportFolderTemporaryDirectory()
        let nestedURL = rootURL.appendingPathComponent("客户A", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        let invoiceURL = rootURL.appendingPathComponent("Invoice_2026Q1.pdf")
        let contractURL = nestedURL.appendingPathComponent("合同.pdf")
        try Data("invoice".utf8).write(to: invoiceURL)
        try Data("contract".utf8).write(to: contractURL)
        let predictor = ImportFolderMappedPredictor(resultsByFilename: [
            "Invoice_2026Q1.pdf": .success(.importFolderPrediction(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf"
            )),
            "合同.pdf": .success(.importFolderPrediction(
                category: "docs",
                suggestedName: "2026Q1_合同.pdf",
                confidence: 0.82
            ))
        ])
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker()
        )

        await model.load(request: importFolderFolderRequest(rootURL: rootURL))
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests.map(\.repoPath), [importBatchRepoPath(), importBatchRepoPath()])
        XCTAssertEqual(Set(requests.map(\.filename)), ["Invoice_2026Q1.pdf", "合同.pdf"])
        let rowsByName = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.originalName, $0) })

        XCTAssertEqual(rowsByName["Invoice_2026Q1.pdf"]?.relativePath, "Invoice_2026Q1.pdf")
        XCTAssertEqual(rowsByName["Invoice_2026Q1.pdf"]?.predictedCategory, "finance")
        XCTAssertEqual(rowsByName["Invoice_2026Q1.pdf"]?.suggestedName, "Invoice_2026Q1.pdf")
        XCTAssertEqual(rowsByName["合同.pdf"]?.relativePath, "客户A/合同.pdf")
        XCTAssertEqual(rowsByName["合同.pdf"]?.predictedCategory, "docs")
        XCTAssertEqual(rowsByName["合同.pdf"]?.suggestedName, "2026Q1_合同.pdf")
        XCTAssertEqual(model.rows.map(\.status.tag), ["OK", "OK"])
        XCTAssertEqual(model.folderCount, 1)
        XCTAssertEqual(model.status.message, "已完成 2 个文件的分类预览")
        XCTAssertNil(model.importDisabledReason)
    }

    @MainActor
    func testImportFolderFolderPreviewUsesDefaultIgnoreRulesAndNeverPredictsSkippedFiles() async throws {
        let rootURL = try makeImportFolderTemporaryDirectory()
        let gitURL = rootURL.appendingPathComponent(".git", isDirectory: true)
        let nodeModulesURL = rootURL.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: gitURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nodeModulesURL, withIntermediateDirectories: true)
        try Data("ignored".utf8).write(to: gitURL.appendingPathComponent("config"))
        try Data("ignored".utf8).write(to: rootURL.appendingPathComponent(".DS_Store"))
        try Data("ready".utf8).write(to: rootURL.appendingPathComponent("Report.pdf"))
        let predictor = ImportFolderRecordingPredictor(results: [
            .success(.importFolderPrediction(
                suggestedName: "Report.pdf",
                reason: .extension,
                confidence: 0.7
            ))
        ])
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker()
        )

        await model.load(request: importFolderFolderRequest(rootURL: rootURL))
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [ImportFolderPredictRequest(repoPath: importBatchRepoPath(), filename: "Report.pdf")])
        XCTAssertEqual(model.rows.map(\.originalName), ["Report.pdf"])
        XCTAssertTrue(model.skippedRules.contains(ImportFolderSkippedRule(label: ".git/", count: 1)))
        XCTAssertTrue(model.skippedRules.contains(ImportFolderSkippedRule(label: ".DS_Store", count: 1)))
        XCTAssertTrue(model.skippedRules.contains(ImportFolderSkippedRule(label: "node_modules/", count: 1)))
    }

    @MainActor
    func testImportFolderFolderPreviewMapsClassifyPreviewCoreClassifyFailurePerRowWithoutStaticSuccess() async throws {
        let rootURL = try makeImportFolderTemporaryDirectory()
        try Data("bad".utf8).write(to: rootURL.appendingPathComponent("Bad.pdf"))
        let predictor = ImportFolderRecordingPredictor(results: [
            .failure(CoreError.Config(reason: "classifier.yaml line 7"))
        ])
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker()
        )

        await model.load(request: importFolderFolderRequest(rootURL: rootURL))

        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.rows.first?.status.tag, "ERROR")
        XCTAssertEqual(model.rows.first?.status.detail, "分类规则无效：classifier.yaml line 7")
        XCTAssertEqual(model.status.message, "已完成 0/1 个文件的分类预览，1 个失败")
    }

    @MainActor
    func testImportFolderFolderPreviewDoesNotCallPredictorForICloudPlaceholderRows() async {
        let cloudURL = importBatchICloudPlaceholderURL()
        let scanner = ImportFolderStaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(
                fileURL: cloudURL,
                rootURL: importBatchFixtureRootURL()
            ).withStatus(.iCloudPlaceholder(path: cloudURL.path))],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = ImportFolderRecordingPredictor(results: [])
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker(),
            scanner: scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: importBatchFixtureRootURL()))
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.iCloudPlaceholderCount, 1)
        XCTAssertEqual(model.rows.first?.status.tag, "ICLOUD")
    }

    func testDefaultCoreBridgeFolderPreviewPredictsCategoryFromInitializedRepository() async throws {
        let repoURL = try makeImportFolderTemporaryDirectory()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let result = try await bridge.predictCategory(repoPath: repoURL.path, filename: "Invoice_2026Q1.pdf")

        XCTAssertEqual(result.category, "finance")
        XCTAssertEqual(result.reason, .keyword)
        XCTAssertGreaterThan(result.confidence, 0)
    }
}
