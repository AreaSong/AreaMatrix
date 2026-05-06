import XCTest
@testable import AreaMatrix

final class ImportSingleFilePreviewModelTests: XCTestCase {
    @MainActor
    func testSingleFileSheetCallsCorePredictorAndPrefillsVisibleFields() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "2026Q1_合同_客户A.pdf",
                reason: .keyword,
                confidence: 0.93
            )),
        ])
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [sourceURL],
            kind: .singleFile
        )
        let model = ImportSingleFilePreviewModel(
            predictor: predictor,
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        await model.load(request: request)
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [
            ImportSingleFilePredictRequest(repoPath: "/tmp/repo", filename: "合同.pdf"),
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
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "2026Q1_合同_客户A.pdf",
                reason: .extension,
                confidence: 0.8
            )),
        ])
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .category("finance"),
            urls: [URL(fileURLWithPath: "/tmp/合同.pdf")],
            kind: .singleFile
        )
        let model = ImportSingleFilePreviewModel(
            predictor: predictor,
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: ImportSingleFileRecordingErrorMapper()
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
            .failure(CoreError.Classify(reason: "classifier unavailable")),
        ])
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: "/tmp/source.pdf")],
            kind: .singleFile
        )
        let model = ImportSingleFilePreviewModel(
            predictor: predictor,
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        await model.load(request: request)

        XCTAssertNil(model.prediction)
        XCTAssertEqual(model.selectedCategory, "inbox")
        XCTAssertEqual(model.suggestedName, "source.pdf")
        XCTAssertEqual(model.status, .failed("无法预览分类：classifier unavailable"))
    }

    @MainActor
    func testNonSingleFileRequestSkipsC105Predictor() async {
        let predictor = ImportSingleFileRecordingPredictor(results: [])
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [
                URL(fileURLWithPath: "/tmp/a.pdf"),
                URL(fileURLWithPath: "/tmp/b.pdf"),
            ],
            kind: .multipleItems(2)
        )
        let model = ImportSingleFilePreviewModel(
            predictor: predictor,
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        await model.load(request: request)
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertNil(model.prediction)
        XCTAssertEqual(model.status, .unsupported("此 sheet 只处理单文件导入"))
    }

    @MainActor
    func testCopyImportCallsC106ImporterWithEditedCategoryAndFilename() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "source.pdf",
                reason: .extension,
                confidence: 0.7
            )),
        ])
        let importedEntry = FileEntrySnapshot.importSingleFileFixture(
            currentName: "contract.pdf",
            category: "legal"
        )
        let importer = ImportSingleFileRecordingImporter(results: [.success(importedEntry)])
        let model = ImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [sourceURL],
            kind: .singleFile
        )

        await model.load(request: request)
        model.selectedCategory = " legal "
        model.suggestedName = " contract.pdf "
        await waitForImportSingleFilePreflightToSettle(model)
        await model.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            ImportSingleFileImportRequest(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                storageMode: .copy,
                overrideCategory: "legal",
                overrideFilename: "contract.pdf",
                duplicateStrategy: .ask
            ),
        ])
        XCTAssertEqual(model.importStatus, .imported(importedEntry))
    }

    @MainActor
    func testCopyImportMapsCoreFailureWithoutCreatingStaticSuccess() async {
        let predictor = ImportSingleFileRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "source.pdf",
                reason: .extension,
                confidence: 0.7
            )),
        ])
        let importer = ImportSingleFileRecordingImporter(results: [
            .failure(CoreError.DuplicateFile(existingPath: "docs/source.pdf")),
        ])
        let errorMapper = ImportSingleFileRecordingErrorMapper()
        let model = ImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: errorMapper
        )
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [URL(fileURLWithPath: "/tmp/source.pdf")],
            kind: .singleFile
        )

        await model.load(request: request)
        await model.importSelectedFile()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.DuplicateFile(existingPath: "docs/source.pdf")])
        XCTAssertEqual(
            model.importStatus,
            .failed(CoreErrorMappingSnapshot.importCopyFixture(kind: .duplicateFile))
        )
    }

    @MainActor
    func testImportRequiresCompletedPreview() async {
        let importer = ImportSingleFileRecordingImporter(results: [])
        let model = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(results: []),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        await model.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.importStatus, .blocked("没有可导入的单文件来源"))
    }

    @MainActor
    func testPreflightBlocksImportUntilConflictIsResolved() async {
        let result = ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "duplicate-hash",
            targetRelativePath: "docs/source.pdf",
            conflict: .duplicate(existingPath: "docs/existing.pdf"),
            replaceOptionVisibility: .enabled
        )
        let importer = ImportSingleFileRecordingImporter(results: [
            .success(.importSingleFileFixture(currentName: "source.pdf", category: "docs")),
        ])
        let model = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(results: [.success(.importSingleFileFixture())]),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: result),
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        await model.load(request: .importSingleFileFixture())
        let blocked = await model.importSelectedFile()
        XCTAssertNil(blocked)
        XCTAssertEqual(model.activeConflictPage, .duplicate)
        XCTAssertEqual(model.importDisabledReason, "请先完成 S1-22 conflict-duplicate 处理")

        model.beginReplaceConfirmation()
        guard let context = model.pendingReplaceConfirmation else {
            return XCTFail("Expected S1-24 replace-confirm context")
        }
        model.applyReplaceConfirmation(context.decision(understandsReplace: true))
        let imported = await model.importSelectedFile()
        let requests = await importer.recordedRequests()
        XCTAssertEqual(imported?.currentName, "source.pdf")
        XCTAssertEqual(requests.last?.duplicateStrategy, .overwrite)
    }

    @MainActor
    func testEditingImportFieldsImmediatelyInvalidatesExistingPreflight() async {
        let model = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(results: [.success(.importSingleFileFixture())]),
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        await model.load(request: .importSingleFileFixture())
        XCTAssertNil(model.importDisabledReason)

        model.suggestedName = "renamed.pdf"

        XCTAssertEqual(model.importDisabledReason, "正在检查 preview/hash/conflict precheck")
    }

    @MainActor
    func testICloudPlaceholderRequiresDownloadAndRetryBeforeImport() async {
        let result = ImportSingleFilePreflightResult(
            sourceSizeBytes: nil,
            hashSha256: nil,
            targetRelativePath: "docs/source.pdf",
            conflict: .iCloudPlaceholder(path: "/tmp/source.pdf"),
            replaceOptionVisibility: .hidden
        )
        let importer = ImportSingleFileRecordingImporter(results: [])
        let model = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(results: [.success(.importSingleFileFixture())]),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: result),
            placeholderDownloader: ImportSingleFileStaticICloudDownloader(),
            errorMapper: ImportSingleFileRecordingErrorMapper()
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
        let result = ImportSingleFilePreflightResult(
            sourceSizeBytes: nil,
            hashSha256: nil,
            targetRelativePath: "docs/source.pdf",
            conflict: .iCloudPlaceholder(path: "/tmp/source.pdf"),
            replaceOptionVisibility: .hidden
        )
        let model = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(results: [.success(.importSingleFileFixture())]),
            importer: ImportSingleFileRecordingImporter(results: []),
            preflight: ImportSingleFileStaticPreflight(result: result),
            placeholderDownloader: ImportSingleFileStaticICloudDownloader(
                error: ImportSingleFileStaticLocalizedError(message: "network offline")
            ),
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        await model.load(request: .importSingleFileFixture())
        await model.downloadICloudPlaceholderAndRetry()

        XCTAssertTrue(model.showsICloudActions)
        XCTAssertFalse(model.showsRetryPreviewAction)
        XCTAssertNil(model.activeConflictPage)
        XCTAssertEqual(model.importDisabledReason, "iCloud 下载失败后请重试下载或切换本地资料库")
        guard case .iCloudDownloadFailed(let path, let reason) = model.currentPreflightResult?.conflict else {
            return XCTFail("Expected iCloud download failure to remain in iCloud recovery state")
        }
        XCTAssertEqual(path, "/tmp/source.pdf")
        XCTAssertEqual(reason, "network offline")
    }

    func testDefaultCoreBridgeImportsCopiedFileAndKeepsSourceIntact() async throws {
        let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "repo")
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "source")
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
            overrideCategory: "finance",
            overrideFilename: "invoice-copy.pdf"
        )

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertEqual(entry.currentName, "invoice-copy.pdf")
        XCTAssertEqual(entry.category, "finance")
        XCTAssertEqual(entry.storageMode, "Copied")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(entry.path).path))
    }

}

private struct ImportSingleFilePredictRequest: Equatable, Sendable {
    var repoPath: String
    var filename: String
}

private struct ImportSingleFileImportRequest: Equatable, Sendable {
    var repoPath: String
    var sourceURL: URL
    var storageMode: ImportSingleFileStorageMode
    var overrideCategory: String
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy = .ask
}

private actor ImportSingleFileRecordingPredictor: CoreCategoryPredicting {
    private var results: [Result<ClassifyResultSnapshot, Error>]
    private var requests: [ImportSingleFilePredictRequest] = []

    init(results: [Result<ClassifyResultSnapshot, Error>]) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(ImportSingleFilePredictRequest(repoPath: repoPath, filename: filename))
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

    func recordedRequests() -> [ImportSingleFilePredictRequest] {
        requests
    }
}

private actor ImportSingleFileRecordingImporter: CoreFileImporting {
    private var results: [Result<FileEntrySnapshot, Error>]
    private var requests: [ImportSingleFileImportRequest] = []

    init(results: [Result<FileEntrySnapshot, Error>]) {
        self.results = results
    }

    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try recordImport(
            repoPath: repoPath,
            sourceURL: sourceURL,
            storageMode: .copy,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
    }

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try recordImport(
            repoPath: repoPath,
            sourceURL: sourceURL,
            storageMode: .move,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
    }

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try recordImport(
            repoPath: repoPath,
            sourceURL: sourceURL,
            storageMode: .indexOnly,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
    }

    private func recordImport(
        repoPath: String,
        sourceURL: URL,
        storageMode: ImportSingleFileStorageMode,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) throws -> FileEntrySnapshot {
        requests.append(ImportSingleFileImportRequest(
            repoPath: repoPath,
            sourceURL: sourceURL,
            storageMode: storageMode,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        ))
        guard !results.isEmpty else {
            throw CoreError.Internal(message: "missing import test result")
        }
        switch results.removeFirst() {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [ImportSingleFileImportRequest] {
        requests
    }
}

private actor ImportSingleFileRecordingErrorMapper: CoreErrorMapping {
    private var errors: [CoreError] = []

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return CoreErrorMappingSnapshot.importCopyFixture(kind: kind(for: error))
    }

    func recordedErrors() -> [CoreError] {
        errors
    }

    private func kind(for error: CoreError) -> CoreErrorKindSnapshot {
        switch error {
        case .DuplicateFile:
            return .duplicateFile
        case .InvalidPath:
            return .invalidPath
        case .ICloudPlaceholder:
            return .iCloudPlaceholder
        case .PermissionDenied:
            return .permissionDenied
        case .Io:
            return .io
        case .Db:
            return .db
        default:
            return .internal
        }
    }
}
