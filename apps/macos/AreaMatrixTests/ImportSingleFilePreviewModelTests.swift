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
        await model.importCopy()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            ImportSingleFileImportRequest(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                overrideCategory: "legal",
                overrideFilename: "contract.pdf"
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
        await model.importCopy()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.DuplicateFile(existingPath: "docs/source.pdf")])
        XCTAssertEqual(
            model.importStatus,
            .failed(CoreErrorMappingSnapshot.importCopyFixture(kind: .duplicateFile))
        )
    }

    @MainActor
    func testCopyImportRequiresCompletedPreview() async {
        let importer = ImportSingleFileRecordingImporter(results: [])
        let model = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(results: []),
            importer: importer,
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        await model.importCopy()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.importStatus, .blocked("没有可导入的单文件来源"))
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
    var overrideCategory: String
    var overrideFilename: String
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
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        requests.append(ImportSingleFileImportRequest(
            repoPath: repoPath,
            sourceURL: sourceURL,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename
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

private extension FileEntrySnapshot {
    static func importSingleFileFixture(currentName: String, category: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: 42,
            path: "\(category)/\(currentName)",
            originalName: "source.pdf",
            currentName: currentName,
            category: category,
            sizeBytes: 12,
            hashSha256: "hash",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: "/tmp/source.pdf",
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func importCopyFixture(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "Import failed",
            severity: .high,
            suggestedAction: "Choose a different file or resolve the conflict.",
            recoverability: .userActionRequired,
            rawContext: "copy import"
        )
    }
}

private func makeImportSingleFileTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixImportSingleFile-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
