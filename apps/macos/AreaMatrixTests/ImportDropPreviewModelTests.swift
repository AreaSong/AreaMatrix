import XCTest
@testable import AreaMatrix

final class ImportDropPreviewModelTests: XCTestCase {
    @MainActor
    func testAutoClassifyHoverCallsInjectedCoreCategoryPredictor() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let predictor = ImportDropRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
        ])
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .autoClassify, urls: [sourceURL])
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [
            ImportDropPredictRequest(repoPath: "/tmp/repo", filename: "Invoice_2026Q1.pdf"),
        ])
        XCTAssertEqual(model.presentation?.destinationLabel, "finance")
        XCTAssertEqual(model.presentation?.predictionLabel, "Classification preview: finance · keyword · 90%")
        XCTAssertEqual(model.presentation?.headline, "Drop files to import")
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    func testDefaultCoreBridgePredictsCategoryFromInitializedRepository() async throws {
        let repoURL = try makeImportDropTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let result = try await bridge.predictCategory(
            repoPath: repoURL.path,
            filename: "Invoice_2026Q1.pdf"
        )

        XCTAssertEqual(result.category, "finance")
        XCTAssertEqual(result.reason, .keyword)
        XCTAssertGreaterThan(result.confidence, 0)
    }

    @MainActor
    func testExplicitSidebarCategoryDoesNotRunAutoClassifyPreview() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let predictor = ImportDropRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
        ])
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .category("docs"), urls: [sourceURL])
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.presentation?.destinationLabel, "docs")
        XCTAssertNil(model.presentation?.prediction)
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    @MainActor
    func testClassifyErrorsMapToHoverWarningWithoutCreatingStaticSuccess() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/bad.pdf")
        let predictor = ImportDropRecordingPredictor(results: [
            .failure(CoreError.Config(reason: "classifier.yaml line 7")),
        ])
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .autoClassify, urls: [sourceURL])

        XCTAssertEqual(model.presentation?.warning, "Classifier settings are invalid: classifier.yaml line 7")
        XCTAssertNil(model.presentation?.prediction)
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    @MainActor
    func testInvalidItemsShowAccessibleWarningAndSkipPredictor() async throws {
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/file.pdf"))
        let predictor = ImportDropRecordingPredictor(results: [])
        let model = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await model.preview(target: .autoClassify, urls: [remoteURL])
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.presentation?.warning, "Cannot import this item")
        XCTAssertEqual(model.presentation?.destinationLabel, "Auto classify")
        XCTAssertFalse(model.presentation?.isPredicting ?? true)
    }

    func testSidebarRowsExposeS116DropTargets() {
        let root = RepositorySidebarRowSnapshot(node: RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: []
        ), depth: 0)
        let finance = RepositorySidebarRowSnapshot(node: RepositoryTreeNodeSnapshot(
            slug: "finance",
            displayName: "finance",
            fileCount: 2,
            children: []
        ), depth: 0)
        let contracts = RepositorySidebarRowSnapshot(node: RepositoryTreeNodeSnapshot(
            slug: "contracts",
            displayName: "contracts",
            kind: "Subdir",
            relativePath: "finance/contracts",
            fileCount: 1,
            depth: 2,
            children: []
        ), depth: 1)

        XCTAssertEqual(root.importDropTarget, .repositoryRoot)
        XCTAssertEqual(finance.importDropTarget, .category("finance"))
        XCTAssertEqual(contracts.importDropTarget, .category("finance"))
        XCTAssertEqual(finance.importDropTarget.sidebarHelp, "Import into \"finance\"")
    }

    @MainActor
    func testBatchPreviewCallsPredictorForEachFileAndUsesRealPredictions() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let predictor = ImportDropRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "2026Q1_合同.pdf",
                reason: .keyword,
                confidence: 0.82
            )),
        ])
        let model = ImportBatchPreviewModel(predictor: predictor)
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [invoiceURL, contractURL],
            kind: .multipleItems(2),
            availableCategories: ["inbox", "docs", "finance"]
        )

        await model.load(request: request)
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [
            ImportDropPredictRequest(repoPath: "/tmp/repo", filename: "Invoice_2026Q1.pdf"),
            ImportDropPredictRequest(repoPath: "/tmp/repo", filename: "合同.pdf"),
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
        let goodURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let duplicateURL = URL(fileURLWithPath: "/tmp/Duplicate.pdf")
        let badURL = URL(fileURLWithPath: "/tmp/Bad.pdf")
        let predictor = ImportDropRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Duplicate.pdf",
                reason: .extension,
                confidence: 0.7
            )),
            .failure(CoreError.Config(reason: "classifier.yaml line 7")),
        ])
        let duplicatePrechecker = ImportBatchStaticDuplicatePrechecker(results: [
            duplicateURL.path: .duplicate(existingPath: "finance/existing.pdf"),
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
                "/tmp/Bad.pdf",
            ]),
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
    func testBatchPreviewDuplicatePrecheckFeedsS118ConflictRowsBeforeImport() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let predictor = ImportDropRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "2026Q1_合同.pdf",
                reason: .keyword,
                confidence: 0.82
            )),
        ])
        let duplicatePrechecker = ImportBatchStaticDuplicatePrechecker(results: [
            invoiceURL.path: .duplicate(existingPath: "finance/existing-invoice.pdf"),
        ])
        let previewModel = ImportBatchPreviewModel(
            predictor: predictor,
            duplicatePrechecker: duplicatePrechecker
        )
        let importModel = ImportBatchCopyImportModel(
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper()
        )
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [invoiceURL, contractURL],
            kind: .multipleItems(2),
            availableCategories: ["inbox", "docs", "finance"]
        )

        await previewModel.load(request: request)
        importModel.applyPreviewRows(
            previewModel.rows,
            request: request,
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
        let sourceRoot = try makeImportDropTemporaryDirectory(prefix: "batch-precheck-source")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let invoiceURL = sourceRoot.appendingPathComponent("Invoice_2026Q1.pdf")
        let contractURL = sourceRoot.appendingPathComponent("合同.pdf")
        try Data("same duplicate bytes".utf8).write(to: invoiceURL)
        try Data("unique contract bytes".utf8).write(to: contractURL)
        let duplicateHash = try ImportSingleFileHasher.sha256Hex(for: invoiceURL)
        let duplicateFile = FileEntrySnapshot.s117Fixture(
            currentName: "existing-invoice.pdf",
            category: "finance",
            hashSha256: duplicateHash
        )
        let nameConflictFile = FileEntrySnapshot.s117Fixture(
            currentName: "合同.pdf",
            category: "docs",
            hashSha256: "different-contract-hash"
        )
        let predictor = ImportDropRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "合同.pdf",
                reason: .keyword,
                confidence: 0.82
            )),
        ])
        let duplicateFileLoader = S118StaticBatchFileLoader(pagesByCategory: [
            "__all__": [[duplicateFile, nameConflictFile]],
        ])
        let nameConflictFileLoader = S118StaticBatchFileLoader(pagesByCategory: [
            "docs": [[nameConflictFile]],
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
            urls: [invoiceURL, contractURL],
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
            FileFilterSnapshot(
                category: nil,
                includeDeleted: false,
                importedAfter: nil,
                importedBefore: nil,
                limit: 200,
                offset: 0
            ),
        ])
        XCTAssertEqual(nameConflictRequests, [
            FileFilterSnapshot(
                category: "docs",
                includeDeleted: false,
                importedAfter: nil,
                importedBefore: nil,
                limit: 200,
                offset: 0
            ),
        ])
    }

    func testDefaultCoreBridgeBatchDuplicateDetectionUsesImportFileDuplicateError() async throws {
        let repoURL = try makeImportDropTemporaryRepositoryURL()
        let sourceRoot = try makeImportDropTemporaryDirectory(prefix: "duplicate-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
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
                overrideFilename: "incoming.pdf",
                duplicateStrategy: .ask
            )
            XCTFail("Expected import_file to return DuplicateFile for duplicate content")
        } catch CoreError.DuplicateFile(let existingPath) {
            XCTAssertEqual(existingPath, imported.path)
        } catch {
            XCTFail("Expected DuplicateFile, got \(error)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicateURL.path))
    }
}

private struct ImportDropPredictRequest: Equatable, Sendable {
    var repoPath: String
    var filename: String
}

private actor ImportDropRecordingPredictor: CoreCategoryPredicting {
    private var results: [Result<ClassifyResultSnapshot, Error>]
    private var requests: [ImportDropPredictRequest] = []

    init(results: [Result<ClassifyResultSnapshot, Error>]) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(ImportDropPredictRequest(repoPath: repoPath, filename: filename))
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

    func recordedRequests() -> [ImportDropPredictRequest] {
        requests
    }
}

private struct ImportBatchDuplicatePrecheckRequest: Equatable, Sendable {
    var repoPath: String
    var paths: [String]
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
        destination: ImportBatchDestinationOption
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

private func makeImportDropTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixImportDropTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeImportDropTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixImportDropTests-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
