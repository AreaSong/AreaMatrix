@testable import AreaMatrix
import XCTest

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
    func testS120C106CopyProgressItemsComeFromRealCoreImportCallbacks() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s120-progress-repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "s120-progress-source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        let sourceURL = sourceRoot.appendingPathComponent("invoice.pdf")
        try Data("invoice bytes".utf8).write(to: sourceURL)
        let sourceBefore = try Data(contentsOf: sourceURL)
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let request = s118BatchRequest(repoPath: repoURL.path, urls: [sourceURL])
        let model = ImportBatchCopyImportModel(importer: bridge, errorMapper: bridge)

        model.applyPreviewRows(
            [s118ReadyBatchRow(url: sourceURL, suggestedName: "invoice-copy.pdf")],
            request: request,
            selectedDestination: .autoClassify
        )

        XCTAssertEqual(model.progressItems(), [
            ImportBatchProgressSnapshot.Item(
                sourcePath: sourceURL.path,
                targetPath: "finance/invoice-copy.pdf",
                phase: .pending,
                errorMessage: nil
            )
        ])

        var progressSnapshots: [ImportBatchProgressSnapshot] = []
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify) { progress in
            progressSnapshots.append(progress.withItems(model.progressItems()))
        }

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertEqual(outcome?.succeededEntries.first?.storageMode, "Copied")
        XCTAssertEqual(progressSnapshots.first?.items, [s120ProgressItem(sourceURL: sourceURL, phase: .copying)])
        XCTAssertEqual(progressSnapshots.last?.items, [s120ProgressItem(sourceURL: sourceURL, phase: .done)])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("finance/invoice-copy.pdf").path
        ))
    }

    @MainActor
    func testBatchCopyImportUsesRealImporterForEachPreviewedFile() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let rows = s118ReadyBatchRows(invoiceURL: invoiceURL, contractURL: contractURL)
        let request = s118BatchRequest(urls: [invoiceURL, contractURL])
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
            )
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
            .success(.s117Fixture(currentName: "2026Q1_合同.pdf", category: "docs"))
        ])
        let errorMapper = S117RecordingErrorMapper()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: errorMapper
        )
        let rows = s118ReadyBatchRows(invoiceURL: invoiceURL, contractURL: contractURL)
        let request = s118BatchRequest(
            destination: .category("finance"),
            urls: [invoiceURL, contractURL]
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
        XCTAssertEqual(recordedRequests, s118ExpectedCategoryRequests())
        XCTAssertEqual(mappedErrors, [
            CoreError.PermissionDenied(path: "/tmp/Invoice_2026Q1.pdf")
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

    @MainActor
    func testBatchCopyImportPersistsAndClearsUnfinishedSession() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let rows = s118ReadyBatchRows(invoiceURL: invoiceURL, contractURL: contractURL)
        let request = s118BatchRequest(urls: [invoiceURL, contractURL])
        let store = RecordingImportBatchSessionStore()
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            sessionStore: store
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        let savedSessions = await store.savedSessions()
        let clearedRepoPaths = await store.clearedRepoPaths()

        XCTAssertEqual(savedSessions.first?.repoPath, "/tmp/repo")
        XCTAssertEqual(savedSessions.first?.completed, 0)
        XCTAssertEqual(savedSessions.first?.total, 2)
        XCTAssertEqual(savedSessions.last?.completed, 2)
        XCTAssertEqual(savedSessions.last?.items.map(\.phase), [.done, .done])
        XCTAssertEqual(clearedRepoPaths, ["/tmp/repo"])
    }

    @MainActor
    func testBatchCopyImportKeepsUnfinishedSessionAfterFatalStop() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let pendingURL = URL(fileURLWithPath: "/tmp/Pending.pdf")
        let rows = s118ReadyBatchRows(invoiceURL: invoiceURL, contractURL: contractURL)
            + [s118ReadyBatchRow(url: pendingURL, suggestedName: "Pending.pdf")]
        let request = s118BatchRequest(urls: [invoiceURL, contractURL, pendingURL])
        let store = RecordingImportBatchSessionStore()
        let importer = S118SequenceBatchImporter(results: [
            .success(.s117Fixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
            .failure(CoreError.Io(message: "staging write failed"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S120ImportSessionFatalMapper(),
            sessionStore: store
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let savedSessions = await store.savedSessions()
        let clearedRepoPaths = await store.clearedRepoPaths()

        XCTAssertEqual(outcome?.fatalRetryContext?.sourcePath, contractURL.path)
        XCTAssertEqual(savedSessions.last?.completed, 1)
        XCTAssertEqual(savedSessions.last?.failed, 1)
        XCTAssertEqual(savedSessions.last?.total, 3)
        XCTAssertEqual(savedSessions.last?.items.map(\.phase), [.done, .failed, .pending])
        XCTAssertEqual(clearedRepoPaths, [])
    }

    @MainActor
    func testBatchCopyImportClearsSessionWhenFatalFailureConsumesQueue() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let row = s118ReadyBatchRow(url: sourceURL)
        let request = s118BatchRequest(urls: [sourceURL])
        let store = RecordingImportBatchSessionStore()
        let importer = S118SequenceBatchImporter(results: [
            .failure(CoreError.Io(message: "staging write failed"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S120ImportSessionFatalMapper(),
            sessionStore: store
        )

        model.applyPreviewRows([row], request: request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let savedSessions = await store.savedSessions()
        let clearedRepoPaths = await store.clearedRepoPaths()

        XCTAssertEqual(outcome?.fatalRetryContext?.sourcePath, sourceURL.path)
        XCTAssertEqual(savedSessions.last?.completed, 0)
        XCTAssertEqual(savedSessions.last?.failed, 1)
        XCTAssertEqual(savedSessions.last?.items.map(\.phase), [.failed])
        XCTAssertEqual(clearedRepoPaths, ["/tmp/repo"])
    }
}

final class ImportBatchStorageModeTests: XCTestCase {
    @MainActor
    func testBatchMoveAndIndexOnlyUseRealCoreImportModes() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let rows = [s118ReadyBatchRow(url: sourceURL)]
        let request = s118BatchRequest(urls: [sourceURL])
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(importer: importer, errorMapper: S117RecordingErrorMapper())

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        model.selectedStorageMode = .move
        XCTAssertEqual(model.storageModeRiskMessage, "Move 模式会移走源文件；请确认批量队列只包含要移入资料库的文件。")
        XCTAssertNil(model.importDisabledReason)
        let moved = await model.importReadyFiles(selectedDestination: .autoClassify)
        XCTAssertEqual(moved?.succeededEntries.count, 1)
        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        model.selectedStorageMode = .indexOnly
        XCTAssertEqual(model.storageModeRiskMessage, "Index-only 不复制文件，只写入索引；源文件移动或删除后会显示缺失。")
        XCTAssertNil(model.importDisabledReason)
        let indexed = await model.importReadyFiles(selectedDestination: .autoClassify)
        XCTAssertEqual(indexed?.succeededEntries.count, 1)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                storageMode: .move,
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            ),
            S118BatchImportRequest(
                storageMode: .indexOnly,
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            )
        ])
    }

    @MainActor
    func testBatchCopyImportUsesPerRowCategoryOverrideForAutoClassify() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let rows = s118ReadyBatchRows(invoiceURL: invoiceURL, contractURL: contractURL)
        let request = s118BatchRequest(urls: [invoiceURL, contractURL])
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(importer: importer, errorMapper: S117RecordingErrorMapper())

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        model.updateCategoryOverride(for: rows[1].id, category: "media")
        XCTAssertEqual(model.rows[1].displayCategory(for: .autoClassify), "media")
        XCTAssertEqual(model.targetRelativePath(for: model.rows[1], destination: .autoClassify), "media/2026Q1_合同.pdf")

        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            ),
            S118BatchImportRequest(
                destination: .category("media"),
                suggestedCategory: "media",
                overrideFilename: "2026Q1_合同.pdf",
                duplicateStrategy: .ask
            )
        ])
    }

    @MainActor
    func testBatchCopyImportPreservesPerRowCategoryOverrideAcrossPreviewReapply() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let rows = [
            ImportBatchPreviewRow.ready(
                url: invoiceURL,
                prediction: ClassifyResultSnapshot(
                    category: "finance",
                    suggestedName: "Invoice_2026Q1.pdf",
                    reason: .keyword,
                    confidence: 0.9
                )
            )
        ]
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [invoiceURL],
            kind: .multipleItems(1),
            availableCategories: ["inbox", "finance", "docs"]
        )
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(importer: importer, errorMapper: S117RecordingErrorMapper())

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        model.updateCategoryOverride(for: rows[0].id, category: "docs")
        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(model.rows.first?.displayCategory(for: .autoClassify), "docs")
        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .category("docs"),
                suggestedCategory: "docs",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            )
        ])
    }
}

private actor RecordingImportBatchSessionStore: ImportBatchSessionPersisting {
    private var saved: [ImportBatchSessionSnapshot] = []
    private var cleared: [String] = []
    private var sessionsByRepoPath: [String: ImportBatchSessionSnapshot] = [:]

    func saveSession(_ session: ImportBatchSessionSnapshot) async {
        saved.append(session)
        sessionsByRepoPath[session.repoPath] = session
    }

    func loadSession(repoPath: String) async -> ImportBatchSessionSnapshot? {
        sessionsByRepoPath[repoPath]
    }

    func clearSession(repoPath: String) async {
        cleared.append(repoPath)
        sessionsByRepoPath[repoPath] = nil
    }

    func savedSessions() -> [ImportBatchSessionSnapshot] {
        saved
    }

    func clearedRepoPaths() -> [String] {
        cleared
    }
}

private actor S120ImportSessionFatalMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: "文件读写失败",
            severity: .critical,
            suggestedAction: "AreaMatrix 会保留已完成项并允许查看未完成结果。",
            recoverability: .fatal,
            rawContext: "S1-20 import session fatal"
        )
    }
}

private func s120ProgressItem(
    sourceURL: URL,
    phase: ImportBatchProgressSnapshot.Phase
) -> ImportBatchProgressSnapshot.Item {
    ImportBatchProgressSnapshot.Item(
        sourcePath: sourceURL.path,
        targetPath: "finance/invoice-copy.pdf",
        phase: phase,
        errorMessage: nil
    )
}
