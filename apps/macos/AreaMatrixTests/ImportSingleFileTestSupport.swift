@testable import AreaMatrix
import Foundation

struct ImportSingleFileStaticPreflight: ImportSingleFilePreflighting {
    var result: ImportSingleFilePreflightResult

    static func ready(
        targetRelativePath: String = "docs/source.pdf"
    ) -> ImportSingleFileStaticPreflight {
        ImportSingleFileStaticPreflight(result: .importSingleFileReadyFixture(
            targetRelativePath: targetRelativePath
        ))
    }

    func preflightSingleFileImport(
        request _: ImportSingleFilePreflightRequest
    ) async -> ImportSingleFilePreflightResult {
        result
    }
}

typealias ImportSingleFileStaticICloudDownloader = StaticICloudPlaceholderDownloader

struct ImportSingleFileStaticLocalizedError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

typealias ImportSingleFilePredictRequest = CategoryPredictionRequest

struct ImportSingleFileImportRequest: Equatable {
    var mode: ImportSingleFileStorageMode
    var overrideCategory: String
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy = .ask
}

struct ImportSingleFileCoreImportRequest: Equatable {
    var repoPath: String
    var sourceURL: URL
    var mode: ImportSingleFileStorageMode
    var overrideCategory: String
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy = .ask
}

typealias ImportSingleFileRecordingPredictor = RecordingCategoryPredictor

actor ImportSingleFileRecordingImporter: CoreFileImporting {
    private var queuedResults: [Result<FileEntrySnapshot, Error>]?
    private var requests: [ImportSingleFileImportRequest] = []
    private var coreRequests: [ImportSingleFileCoreImportRequest] = []

    init(results: [Result<FileEntrySnapshot, Error>]? = nil) {
        queuedResults = results
    }

    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try record(ImportSingleFileCoreImportRequest(
            repoPath: repoPath,
            sourceURL: sourceURL,
            mode: .copy,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        ))
    }

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try record(ImportSingleFileCoreImportRequest(
            repoPath: repoPath,
            sourceURL: sourceURL,
            mode: .move,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        ))
    }

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try record(ImportSingleFileCoreImportRequest(
            repoPath: repoPath,
            sourceURL: sourceURL,
            mode: .indexOnly,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        ))
    }

    func recordedRequests() -> [ImportSingleFileImportRequest] {
        requests
    }

    func recordedCoreRequests() -> [ImportSingleFileCoreImportRequest] {
        coreRequests
    }

    private func record(_ request: ImportSingleFileCoreImportRequest) throws -> FileEntrySnapshot {
        requests.append(ImportSingleFileImportRequest(
            mode: request.mode,
            overrideCategory: request.overrideCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))
        coreRequests.append(request)
        if var queuedResults {
            guard !queuedResults.isEmpty else {
                throw CoreError.Internal(message: "missing import test result")
            }
            let next = queuedResults.removeFirst()
            self.queuedResults = queuedResults
            return try next.get()
        }

        return FileEntrySnapshot.importSingleFileFixture(
            currentName: request.overrideFilename,
            category: request.overrideCategory,
            storageMode: request.mode.coreStorageMode
        )
    }
}

actor ImportSingleFileSuspendingImporter: CoreFileImporting {
    private let gate: ImportSingleFileImportGate

    init(gate: ImportSingleFileImportGate) {
        self.gate = gate
    }

    func importCopiedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy _: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        await gate.markStarted()
        await gate.waitUntilFinished()
        return FileEntrySnapshot.importSingleFileFixture(currentName: overrideFilename, category: overrideCategory)
    }

    func importMovedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory _: String,
        overrideFilename _: String,
        duplicateStrategy _: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        throw CoreError.Internal(message: "unexpected move import")
    }

    func importIndexedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory _: String,
        overrideFilename _: String,
        duplicateStrategy _: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        throw CoreError.Internal(message: "unexpected indexed import")
    }
}

actor ImportSingleFileImportGate {
    private var isStarted = false
    private var isFinished = false
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuations: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        isStarted = true
        resume(&startContinuations)
    }

    func waitUntilStarted() async {
        if isStarted { return }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func finish() {
        isFinished = true
        resume(&finishContinuations)
    }

    func waitUntilFinished() async {
        if isFinished { return }
        await withCheckedContinuation { continuation in
            finishContinuations.append(continuation)
        }
    }

    private func resume(_ continuations: inout [CheckedContinuation<Void, Never>]) {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

actor ImportSingleFileFailingImporter: CoreFileImporting {
    private let error: CoreError

    init(error: CoreError) {
        self.error = error
    }

    func importCopiedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory _: String,
        overrideFilename _: String,
        duplicateStrategy _: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        throw error
    }

    func importMovedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory _: String,
        overrideFilename _: String,
        duplicateStrategy _: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        throw error
    }

    func importIndexedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory _: String,
        overrideFilename _: String,
        duplicateStrategy _: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        throw error
    }
}

typealias ImportSingleFileStaticRepositoryOpener = RecordingRepositoryOpener

@MainActor
func makeImportSingleFilePreviewModel(
    predictor: any CoreCategoryPredicting = ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
    importer: any CoreFileImporting = ImportSingleFileRecordingImporter(),
    preflight: any ImportSingleFilePreflighting = ImportSingleFileStaticPreflight.ready(),
    placeholderDownloader: any ICloudPlaceholderDownloading = ImportSingleFileStaticICloudDownloader(),
    errorMapper: any CoreErrorMapping = RecordingCoreErrorMapper.importSingleFile()
) -> ImportSingleFilePreviewModel {
    ImportSingleFilePreviewModel(
        predictor: predictor,
        importer: importer,
        preflight: preflight,
        placeholderDownloader: placeholderDownloader,
        errorMapper: errorMapper
    )
}

@MainActor
func makeImportSingleFileNameConflictCoreModel(
    repoURL: URL,
    existingURL: URL,
    incomingURL: URL
) async throws -> ImportSingleFilePreviewModel {
    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    _ = try await bridge.importCopiedFile(
        repoPath: repoURL.path,
        sourceURL: existingURL,
        overrideCategory: "docs",
        overrideFilename: "source.pdf"
    )

    let model = makeImportSingleFilePreviewModel(
        importer: bridge,
        preflight: CoreImportSingleFilePreflight()
    )
    await model.load(request: .importSingleFileImportRequest(
        repoPath: repoURL.path,
        sourcePath: incomingURL.path
    ))
    return model
}
