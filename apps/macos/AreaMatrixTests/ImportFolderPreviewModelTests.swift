import XCTest
@testable import AreaMatrix

final class ImportFolderPreviewModelTests: XCTestCase {
    @MainActor
    func testS119FolderPreviewScansFolderAndCallsC105PredictorForEachReadyFile() async throws {
        let rootURL = try makeImportFolderTemporaryDirectory()
        let nestedURL = rootURL.appendingPathComponent("客户A", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        let invoiceURL = rootURL.appendingPathComponent("Invoice_2026Q1.pdf")
        let contractURL = nestedURL.appendingPathComponent("合同.pdf")
        try Data("invoice".utf8).write(to: invoiceURL)
        try Data("contract".utf8).write(to: contractURL)
        let predictor = S119MappedPredictor(resultsByFilename: [
            "Invoice_2026Q1.pdf": .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
            "合同.pdf": .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "2026Q1_合同.pdf",
                reason: .keyword,
                confidence: 0.82
            )),
        ])
        let model = ImportFolderPreviewModel(predictor: predictor)

        await model.load(request: s119FolderRequest(rootURL: rootURL))
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests.map(\.repoPath), ["/tmp/repo", "/tmp/repo"])
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
        XCTAssertEqual(model.importDisabledReason, "C1-06/C1-08 导入执行由后续任务接入")
    }

    @MainActor
    func testS119FolderPreviewUsesDefaultIgnoreRulesAndNeverPredictsSkippedFiles() async throws {
        let rootURL = try makeImportFolderTemporaryDirectory()
        let gitURL = rootURL.appendingPathComponent(".git", isDirectory: true)
        let nodeModulesURL = rootURL.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: gitURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nodeModulesURL, withIntermediateDirectories: true)
        try Data("ignored".utf8).write(to: gitURL.appendingPathComponent("config"))
        try Data("ignored".utf8).write(to: rootURL.appendingPathComponent(".DS_Store"))
        try Data("ready".utf8).write(to: rootURL.appendingPathComponent("Report.pdf"))
        let predictor = S119RecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "Report.pdf",
                reason: .extension,
                confidence: 0.7
            )),
        ])
        let model = ImportFolderPreviewModel(predictor: predictor)

        await model.load(request: s119FolderRequest(rootURL: rootURL))
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [S119PredictRequest(repoPath: "/tmp/repo", filename: "Report.pdf")])
        XCTAssertEqual(model.rows.map(\.originalName), ["Report.pdf"])
        XCTAssertTrue(model.skippedRules.contains(ImportFolderSkippedRule(label: ".git/", count: 1)))
        XCTAssertTrue(model.skippedRules.contains(ImportFolderSkippedRule(label: ".DS_Store", count: 1)))
        XCTAssertTrue(model.skippedRules.contains(ImportFolderSkippedRule(label: "node_modules/", count: 1)))
    }

    @MainActor
    func testS119FolderPreviewMapsC105ClassifyFailurePerRowWithoutStaticSuccess() async throws {
        let rootURL = try makeImportFolderTemporaryDirectory()
        try Data("bad".utf8).write(to: rootURL.appendingPathComponent("Bad.pdf"))
        let predictor = S119RecordingPredictor(results: [
            .failure(CoreError.Config(reason: "classifier.yaml line 7")),
        ])
        let model = ImportFolderPreviewModel(predictor: predictor)

        await model.load(request: s119FolderRequest(rootURL: rootURL))

        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.rows.first?.status.tag, "ERROR")
        XCTAssertEqual(model.rows.first?.status.detail, "分类规则无效：classifier.yaml line 7")
        XCTAssertEqual(model.status.message, "已完成 0/1 个文件的分类预览，1 个失败")
    }

    @MainActor
    func testS119FolderPreviewDoesNotCallPredictorForICloudPlaceholderRows() async {
        let cloudURL = URL(fileURLWithPath: "/tmp/iCloudOnly.pdf.icloud")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(
                fileURL: cloudURL,
                rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
            ).withStatus(.iCloudPlaceholder(path: cloudURL.path))],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = S119RecordingPredictor(results: [])
        let model = ImportFolderPreviewModel(predictor: predictor, scanner: scanner)

        await model.load(request: s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)))
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.iCloudPlaceholderCount, 1)
        XCTAssertEqual(model.rows.first?.status.tag, "ICLOUD")
    }

    func testDefaultCoreBridgeFolderPreviewPredictsCategoryFromInitializedRepository() async throws {
        let repoURL = try makeImportFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let result = try await bridge.predictCategory(repoPath: repoURL.path, filename: "Invoice_2026Q1.pdf")

        XCTAssertEqual(result.category, "finance")
        XCTAssertEqual(result.reason, .keyword)
        XCTAssertGreaterThan(result.confidence, 0)
    }
}

private struct S119PredictRequest: Equatable, Sendable {
    var repoPath: String
    var filename: String
}

private actor S119RecordingPredictor: CoreCategoryPredicting {
    private var results: [Result<ClassifyResultSnapshot, Error>]
    private var requests: [S119PredictRequest] = []

    init(results: [Result<ClassifyResultSnapshot, Error>]) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(S119PredictRequest(repoPath: repoPath, filename: filename))
        guard !results.isEmpty else {
            throw CoreError.Classify(reason: "missing test result")
        }
        switch results.removeFirst() {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [S119PredictRequest] {
        requests
    }
}

private actor S119MappedPredictor: CoreCategoryPredicting {
    private let resultsByFilename: [String: Result<ClassifyResultSnapshot, Error>]
    private var requests: [S119PredictRequest] = []

    init(resultsByFilename: [String: Result<ClassifyResultSnapshot, Error>]) {
        self.resultsByFilename = resultsByFilename
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(S119PredictRequest(repoPath: repoPath, filename: filename))
        guard let result = resultsByFilename[filename] else {
            throw CoreError.Classify(reason: "missing test result")
        }
        switch result {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [S119PredictRequest] {
        requests
    }
}

private struct S119StaticFolderScanner: ImportFolderScanning {
    var result: ImportFolderScanResult

    func scanFolder(rootURL: URL, includeHiddenFiles: Bool, followSymlinks: Bool) async -> ImportFolderScanResult {
        result
    }
}

private func s119FolderRequest(rootURL: URL) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: .autoClassify,
        urls: [rootURL],
        kind: .folder,
        availableCategories: ["inbox", "docs", "finance"]
    )
}

private func makeImportFolderTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixImportFolderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
