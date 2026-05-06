import XCTest
@testable import AreaMatrix

final class ImportSingleFileIndexImportTests: XCTestCase {
    @MainActor
    func testIndexOnlyImportCallsC108ImporterWithEditedCategoryAndFilename() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let predictor = IndexImportRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "source.pdf",
                reason: .extension,
                confidence: 0.7
            )),
        ])
        let indexedEntry = FileEntrySnapshot.indexImportFixture(
            currentName: "indexed.pdf",
            category: "docs"
        )
        let importer = IndexImportRecordingImporter(results: [.success(indexedEntry)])
        let model = ImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: IndexImportRecordingErrorMapper()
        )
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [sourceURL],
            kind: .singleFile
        )

        await model.load(request: request)
        model.selectedStorageMode = .indexOnly
        model.selectedCategory = " docs "
        model.suggestedName = " indexed.pdf "
        await waitForImportSingleFilePreflightToSettle(model)
        await model.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            IndexImportRequest(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                storageMode: .indexOnly,
                overrideCategory: "docs",
                overrideFilename: "indexed.pdf"
            ),
        ])
        XCTAssertEqual(model.importStatus, .imported(indexedEntry))
    }

    @MainActor
    func testIndexOnlyImportMapsCoreFailureWithoutCreatingStaticSuccess() async {
        let predictor = IndexImportRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "source.pdf",
                reason: .extension,
                confidence: 0.7
            )),
        ])
        let importer = IndexImportRecordingImporter(results: [
            .failure(CoreError.ICloudPlaceholder(path: "/tmp/source.pdf")),
        ])
        let errorMapper = IndexImportRecordingErrorMapper()
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
        model.selectedStorageMode = .indexOnly
        await model.importSelectedFile()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.ICloudPlaceholder(path: "/tmp/source.pdf")])
        XCTAssertEqual(
            model.importStatus,
            .failed(CoreErrorMappingSnapshot.indexImportFixture(kind: .iCloudPlaceholder))
        )
    }

    func testDefaultCoreBridgeImportsIndexedFileWithoutMovingOrCopyingSource() async throws {
        let repoURL = try makeIndexImportTemporaryDirectory(prefix: "repo")
        let sourceRoot = try makeIndexImportTemporaryDirectory(prefix: "source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("indexed.pdf")
        try Data("indexed bytes".utf8).write(to: sourceURL)
        let sourceBefore = try Data(contentsOf: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importIndexedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "indexed-display.pdf"
        )

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertEqual(entry.currentName, "indexed-display.pdf")
        XCTAssertEqual(entry.category, "docs")
        XCTAssertEqual(entry.storageMode, "Indexed")
        XCTAssertEqual(entry.sourcePath, sourceURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(entry.path).path))
    }
}

private struct IndexImportRequest: Equatable, Sendable {
    var repoPath: String
    var sourceURL: URL
    var storageMode: ImportSingleFileStorageMode
    var overrideCategory: String
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy = .ask
}

private actor IndexImportRecordingPredictor: CoreCategoryPredicting {
    private var results: [Result<ClassifyResultSnapshot, Error>]

    init(results: [Result<ClassifyResultSnapshot, Error>]) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
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
}

private actor IndexImportRecordingImporter: CoreFileImporting {
    private var results: [Result<FileEntrySnapshot, Error>]
    private var requests: [IndexImportRequest] = []

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

    func recordedRequests() -> [IndexImportRequest] {
        requests
    }

    private func recordImport(
        repoPath: String,
        sourceURL: URL,
        storageMode: ImportSingleFileStorageMode,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) throws -> FileEntrySnapshot {
        requests.append(IndexImportRequest(
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
}

private actor IndexImportRecordingErrorMapper: CoreErrorMapping {
    private var errors: [CoreError] = []

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return CoreErrorMappingSnapshot.indexImportFixture(kind: kind(for: error))
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
        case .FileNotFound:
            return .fileNotFound
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
    static func indexImportFixture(currentName: String, category: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: 43,
            path: "/tmp/source.pdf",
            originalName: "source.pdf",
            currentName: currentName,
            category: category,
            sizeBytes: 12,
            hashSha256: "hash",
            storageMode: "Indexed",
            origin: "Imported",
            sourcePath: "/tmp/source.pdf",
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func indexImportFixture(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "Import failed",
            severity: .high,
            suggestedAction: "Choose a different file or resolve the conflict.",
            recoverability: .userActionRequired,
            rawContext: "index import"
        )
    }
}

private func makeIndexImportTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixImportIndex-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
