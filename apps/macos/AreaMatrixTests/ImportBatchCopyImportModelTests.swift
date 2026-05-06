import XCTest
@testable import AreaMatrix

final class ImportBatchCopyImportModelTests: XCTestCase {
    func testDefaultCoreBridgeBatchCopyAutoClassifyKeepsSourceAndCreatesRepoCopy() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s118-auto-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "s118-auto-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        let sourceURL = sourceRoot.appendingPathComponent("invoice.pdf")
        try Data("invoice bytes".utf8).write(to: sourceURL)
        let sourceBefore = try Data(contentsOf: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            destination: .autoClassify,
            suggestedCategory: "finance",
            overrideFilename: "invoice-copy.pdf"
        )

        XCTAssertEqual(entry.currentName, "invoice-copy.pdf")
        XCTAssertEqual(entry.category, "finance")
        XCTAssertEqual(entry.storageMode, "Copied")
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(entry.path).path))

        let listed = try await bridge.listFiles(repoPath: repoURL.path, filter: .currentCategory("finance"))
        XCTAssertEqual(listed.map(\.currentName), ["invoice-copy.pdf"])
    }

    func testDefaultCoreBridgeBatchCopyCategoryUsesExplicitCategoryDirectory() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s118-category-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "s118-category-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        let sourceURL = sourceRoot.appendingPathComponent("合同.pdf")
        try Data("contract bytes".utf8).write(to: sourceURL)
        let sourceBefore = try Data(contentsOf: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            destination: .category("docs"),
            suggestedCategory: "finance",
            overrideFilename: "已签署合同.pdf"
        )

        XCTAssertEqual(entry.currentName, "已签署合同.pdf")
        XCTAssertEqual(entry.category, "docs")
        XCTAssertEqual(entry.storageMode, "Copied")
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertEqual(entry.path, "docs/已签署合同.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("docs/已签署合同.pdf").path))

        let listed = try await bridge.listFiles(repoPath: repoURL.path, filter: .currentCategory("docs"))
        XCTAssertEqual(listed.map(\.currentName), ["已签署合同.pdf"])
    }

    @MainActor
    func testBatchCopyImportUsesRealImporterForEachPreviewedFile() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let rows = [
            ImportBatchPreviewRow.ready(
                url: invoiceURL,
                prediction: ClassifyResultSnapshot(
                    category: "finance",
                    suggestedName: "Invoice_2026Q1.pdf",
                    reason: .keyword,
                    confidence: 0.9
                )
            ),
            ImportBatchPreviewRow.ready(
                url: contractURL,
                prediction: ClassifyResultSnapshot(
                    category: "docs",
                    suggestedName: "2026Q1_合同.pdf",
                    reason: .keyword,
                    confidence: 0.82
                )
            ),
        ]
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [invoiceURL, contractURL],
            kind: .multipleItems(2),
            availableCategories: ["inbox", "docs", "finance"]
        )
        let importer = S118RecordingBatchImporter()
        let importModel = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )
        var progressSnapshots: [ImportBatchProgressSnapshot] = []

        importModel.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        let outcome = await importModel.importReadyFiles(selectedDestination: .autoClassify) { progress in
            progressSnapshots.append(progress)
        }
        let recordedRequests = await importer.recordedRequests()

        guard let result = outcome else {
            return XCTFail("Expected successful batch copy import")
        }
        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            ),
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "2026Q1_合同.pdf",
                duplicateStrategy: .ask
            ),
        ])
        XCTAssertEqual(result.succeededEntries.count, 2)
        XCTAssertEqual(result.total, 2)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(importModel.rows.map(\.status.tag), ["IMPORTED", "IMPORTED"])
        XCTAssertEqual(importModel.status.message, "批量导入完成：成功 2，失败 0")
        XCTAssertEqual(progressSnapshots.last, ImportBatchProgressSnapshot(
            completed: 2,
            failed: 0,
            total: 2,
            remaining: 0,
            currentPath: "docs/2026Q1_合同.pdf"
        ))
    }

    @MainActor
    func testBatchCopyImportMapsPermissionDeniedWithoutStaticSuccess() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let importer = S118SequenceBatchImporter(results: [
            .failure(CoreError.PermissionDenied(path: "/tmp/Invoice_2026Q1.pdf")),
            .success(.s117Fixture(currentName: "2026Q1_合同.pdf", category: "docs")),
        ])
        let errorMapper = S117RecordingErrorMapper()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: errorMapper
        )
        let rows = [
            ImportBatchPreviewRow.ready(
                url: invoiceURL,
                prediction: ClassifyResultSnapshot(
                    category: "finance",
                    suggestedName: "Invoice_2026Q1.pdf",
                    reason: .keyword,
                    confidence: 0.9
                )
            ),
            ImportBatchPreviewRow.ready(
                url: contractURL,
                prediction: ClassifyResultSnapshot(
                    category: "docs",
                    suggestedName: "2026Q1_合同.pdf",
                    reason: .keyword,
                    confidence: 0.82
                )
            ),
        ]
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .category("finance"),
            urls: [invoiceURL, contractURL],
            kind: .multipleItems(2),
            availableCategories: ["inbox", "finance", "docs"]
        )
        var progressSnapshots: [ImportBatchProgressSnapshot] = []

        model.applyPreviewRows(rows, request: request, selectedDestination: .category("finance"))
        let outcome = await model.importReadyFiles(selectedDestination: .category("finance")) { progress in
            progressSnapshots.append(progress)
        }
        let recordedRequests = await importer.recordedRequests()
        let mappedErrors = await errorMapper.recordedErrors()

        guard let result = outcome else {
            return XCTFail("Expected batch copy import result")
        }
        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .category("finance"),
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            ),
            S118BatchImportRequest(
                destination: .category("finance"),
                suggestedCategory: "docs",
                overrideFilename: "2026Q1_合同.pdf",
                duplicateStrategy: .ask
            ),
        ])
        XCTAssertEqual(mappedErrors, [
            CoreError.PermissionDenied(path: "/tmp/Invoice_2026Q1.pdf"),
        ])
        XCTAssertEqual(result.succeededEntries.count, 1)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.total, 2)
        XCTAssertEqual(model.rows.map(\.status.tag), ["ERROR", "IMPORTED"])
        XCTAssertEqual(model.rows.first?.status.detail, "无访问权限")
        XCTAssertEqual(model.status.message, "批量导入完成：成功 1，失败 1")
        XCTAssertEqual(progressSnapshots.last, ImportBatchProgressSnapshot(
            completed: 1,
            failed: 1,
            total: 2,
            remaining: 0,
            currentPath: "finance/2026Q1_合同.pdf"
        ))
    }

}
