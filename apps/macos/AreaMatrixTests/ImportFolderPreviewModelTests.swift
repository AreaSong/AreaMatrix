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
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker()
        )

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
        XCTAssertNil(model.importDisabledReason)
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
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker()
        )

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
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker()
        )

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
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner
        )

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

    @MainActor
    func testS119FolderCopyImportUsesRealImporterForReadyRowsOnly() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let cloudURL = URL(fileURLWithPath: "/tmp/iCloudOnly.pdf.icloud")
        let errorURL = URL(fileURLWithPath: "/tmp/unreadable.mov")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [
                ImportFolderPreviewRow.loading(
                    fileURL: invoiceURL,
                    rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
                ),
                ImportFolderPreviewRow.loading(
                    fileURL: cloudURL,
                    rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
                ).withStatus(.iCloudPlaceholder(path: cloudURL.path)),
                ImportFolderPreviewRow.loading(
                    fileURL: errorURL,
                    rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
                ).withStatus(.error("无法读取文件属性")),
            ],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = S119RecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
        ])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner
        )
        var progressSnapshots: [ImportBatchProgressSnapshot] = []

        await model.load(request: s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)))
        let outcome = await model.importReadyFiles { progress in
            progressSnapshots.append(progress)
        }
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            ),
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.failedCount, 0)
        XCTAssertEqual(outcome?.previewErrorCount, 1)
        XCTAssertEqual(outcome?.pendingICloudCount, 1)
        XCTAssertEqual(model.rows.map(\.status.tag), ["IMPORTED", "ICLOUD", "ERROR"])
        XCTAssertEqual(progressSnapshots.last?.completed, 1)
        XCTAssertEqual(progressSnapshots.last?.failed, 0)
        XCTAssertEqual(progressSnapshots.last?.total, 1)
        XCTAssertEqual(progressSnapshots.last?.remaining, 0)
        XCTAssertEqual(progressSnapshots.last?.currentPath, "finance/Invoice_2026Q1.pdf")
        XCTAssertEqual(progressSnapshots.last?.items.map(\.phase), [.done, .pending, .failed])
        XCTAssertEqual(progressSnapshots.last?.items.last?.errorMessage, "无法预览分类：missing test result")
    }

    @MainActor
    func testS119FolderResultSummaryKeepsPerRowStatusesForFailureAndPendingRows() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let cloudURL = URL(fileURLWithPath: "/tmp/iCloudOnly.pdf.icloud")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [
                ImportFolderPreviewRow.loading(
                    fileURL: invoiceURL,
                    rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
                ),
                ImportFolderPreviewRow.loading(
                    fileURL: cloudURL,
                    rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
                ).withStatus(.iCloudPlaceholder(path: cloudURL.path)),
            ],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = S119RecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
        ])
        let importer = S118SequenceBatchImporter(results: [
            .failure(CoreError.PermissionDenied(path: invoiceURL.path)),
        ])
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner
        )

        await model.load(request: s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)))
        let outcome = await model.importReadyFiles()
        let summary = outcome?.progressSnapshot(currentPath: "finance/Invoice_2026Q1.pdf")
            .withItems(model.progressItems())

        XCTAssertEqual(summary, ImportBatchProgressSnapshot(
            completed: 0,
            failed: 1,
            total: 2,
            remaining: 0,
            currentPath: "finance/Invoice_2026Q1.pdf",
            skipped: 0,
            pending: 1,
            items: [
                ImportBatchProgressSnapshot.Item(
                    sourcePath: invoiceURL.path,
                    targetPath: "finance/Invoice_2026Q1.pdf",
                    phase: .failed,
                    errorMessage: "无访问权限"
                ),
                ImportBatchProgressSnapshot.Item(
                    sourcePath: cloudURL.path,
                    targetPath: "iCloudOnly.pdf.icloud",
                    phase: .pending,
                    errorMessage: nil
                ),
            ]
        ))
    }

    @MainActor
    func testS119FolderCopyImportMapsCoreFailureWithoutStaticSuccess() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(
                fileURL: invoiceURL,
                rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
            )],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = S119RecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
        ])
        let importer = S118SequenceBatchImporter(results: [
            .failure(CoreError.PermissionDenied(path: invoiceURL.path)),
        ])
        let errorMapper = S117RecordingErrorMapper()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: errorMapper,
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner
        )

        await model.load(request: s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)))
        let outcome = await model.importReadyFiles()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: invoiceURL.path)])
        XCTAssertEqual(outcome?.succeededEntries, [])
        XCTAssertEqual(outcome?.failedCount, 1)
        XCTAssertEqual(model.rows.first?.status.tag, "ERROR")
        XCTAssertEqual(model.rows.first?.status.detail, "无访问权限")
        XCTAssertEqual(model.lastFailureMapping?.kind, .permissionDenied)
    }

    @MainActor
    func testS119FolderCopyImportHonorsDropDestinationCategory() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(
                fileURL: invoiceURL,
                rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
            )],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = S119RecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
        ])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner
        )
        let request = s119FolderRequest(
            rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true),
            destination: .category("docs")
        )

        await model.load(request: request)
        _ = await model.importReadyFiles()
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .category("docs"),
                suggestedCategory: "docs",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            ),
        ])
    }

    @MainActor
    func testS119FolderIndexOnlyImportCallsC108ImporterForReadyRows() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/reference.pdf")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(
                fileURL: sourceURL,
                rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
            )],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = S119RecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "indexed-reference.pdf",
                reason: .keyword,
                confidence: 0.9
            )),
        ])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner
        )

        await model.load(request: s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)))
        model.selectedStorageMode = .indexOnly
        let outcome = await model.importReadyFiles()
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                storageMode: .indexOnly,
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "indexed-reference.pdf",
                duplicateStrategy: .ask
            ),
        ])
        XCTAssertEqual(outcome?.succeededEntries.first?.storageMode, "Indexed")
        XCTAssertEqual(model.rows.first?.status.detail, "已写入索引")
    }

    @MainActor
    func testS119FolderMoveUsesRealCoreImportMode() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/move-later.pdf")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(
                fileURL: sourceURL,
                rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
            )],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = S119RecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "move-later.pdf",
                reason: .extension,
                confidence: 0.7
            )),
        ])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner
        )

        await model.load(request: s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp", isDirectory: true)))
        model.selectedStorageMode = .move
        XCTAssertNil(model.importDisabledReason)
        let outcome = await model.importReadyFiles()
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                storageMode: .move,
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "move-later.pdf",
                duplicateStrategy: .ask
            ),
        ])
    }

}
