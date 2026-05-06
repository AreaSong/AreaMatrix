import XCTest
@testable import AreaMatrix

final class ImportSingleFileMoveImportTests: XCTestCase {
    @MainActor
    func testMoveImportCallsC107ImporterWithEditedCategoryAndFilename() async {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let predictor = MoveImportRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "source.pdf",
                reason: .extension,
                confidence: 0.7
            )),
        ])
        let movedEntry = FileEntrySnapshot.moveImportFixture(
            currentName: "moved.pdf",
            category: "docs"
        )
        let importer = MoveImportRecordingImporter(results: [.success(movedEntry)])
        let model = ImportSingleFilePreviewModel(
            predictor: predictor,
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: MoveImportRecordingErrorMapper()
        )
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .filePicker,
            destination: .autoClassify,
            urls: [sourceURL],
            kind: .singleFile
        )

        await model.load(request: request)
        model.selectedStorageMode = .move
        model.selectedCategory = " docs "
        model.suggestedName = " moved.pdf "
        await waitForImportSingleFilePreflightToSettle(model)
        await model.importSelectedFile()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            MoveImportRequest(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                storageMode: .move,
                overrideCategory: "docs",
                overrideFilename: "moved.pdf"
            ),
        ])
        XCTAssertEqual(model.importStatus, .imported(movedEntry))
    }

    @MainActor
    func testMoveImportMapsCoreFailureWithoutCreatingStaticSuccess() async {
        let predictor = MoveImportRecordingPredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "docs",
                suggestedName: "source.pdf",
                reason: .extension,
                confidence: 0.7
            )),
        ])
        let importer = MoveImportRecordingImporter(results: [
            .failure(CoreError.PermissionDenied(path: "/tmp/source.pdf")),
        ])
        let errorMapper = MoveImportRecordingErrorMapper()
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
        model.selectedStorageMode = .move
        await model.importSelectedFile()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: "/tmp/source.pdf")])
        XCTAssertEqual(
            model.importStatus,
            .failed(CoreErrorMappingSnapshot.moveImportFixture(kind: .permissionDenied))
        )
    }

    func testDefaultCoreBridgeImportsMovedFileAndRemovesSource() async throws {
        let repoURL = try makeMoveImportTemporaryDirectory(prefix: "repo")
        let sourceRoot = try makeMoveImportTemporaryDirectory(prefix: "source")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("move.pdf")
        try Data("move bytes".utf8).write(to: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importMovedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "moved.pdf"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(entry.currentName, "moved.pdf")
        XCTAssertEqual(entry.category, "docs")
        XCTAssertEqual(entry.storageMode, "Moved")
        XCTAssertEqual(entry.sourcePath, sourceURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(entry.path).path))
    }
}

private struct MoveImportRequest: Equatable, Sendable {
    var repoPath: String
    var sourceURL: URL
    var storageMode: ImportSingleFileStorageMode
    var overrideCategory: String
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy = .ask
}

private actor MoveImportRecordingPredictor: CoreCategoryPredicting {
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

private actor MoveImportRecordingImporter: CoreFileImporting {
    private var results: [Result<FileEntrySnapshot, Error>]
    private var requests: [MoveImportRequest] = []

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

    func recordedRequests() -> [MoveImportRequest] {
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
        requests.append(MoveImportRequest(
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

private actor MoveImportRecordingErrorMapper: CoreErrorMapping {
    private var errors: [CoreError] = []

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return CoreErrorMappingSnapshot.moveImportFixture(kind: kind(for: error))
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
    static func moveImportFixture(currentName: String, category: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: 42,
            path: "\(category)/\(currentName)",
            originalName: "source.pdf",
            currentName: currentName,
            category: category,
            sizeBytes: 12,
            hashSha256: "hash",
            storageMode: "Moved",
            origin: "Imported",
            sourcePath: "/tmp/source.pdf",
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func moveImportFixture(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "Import failed",
            severity: .high,
            suggestedAction: "Choose a different file or resolve the conflict.",
            recoverability: .userActionRequired,
            rawContext: "move import"
        )
    }
}

private func makeMoveImportTemporaryDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixImportMove-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
