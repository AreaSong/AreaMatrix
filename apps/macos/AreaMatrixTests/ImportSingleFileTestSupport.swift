@testable import AreaMatrix
import Foundation

struct ImportSingleFileStaticPreflight: ImportSingleFilePreflighting {
    var result: ImportSingleFilePreflightResult

    static func ready(
        targetRelativePath: String = "docs/source.pdf"
    ) -> ImportSingleFileStaticPreflight {
        ImportSingleFileStaticPreflight(result: ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "hash",
            targetRelativePath: targetRelativePath,
            conflict: .none
        ))
    }

    func preflightSingleFileImport(
        request _: ImportSingleFilePreflightRequest
    ) async -> ImportSingleFilePreflightResult {
        result
    }
}

struct ImportSingleFileStaticICloudDownloader: ICloudPlaceholderDownloading {
    var error: Error?

    func downloadPlaceholder(at _: URL) async throws {
        if let error {
            throw error
        }
    }
}

struct ImportSingleFileStaticLocalizedError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

struct ImportSingleFilePredictRequest: Equatable {
    var repoPath: String
    var filename: String
}

struct ImportSingleFileImportRequest: Equatable {
    var mode: ImportSingleFileStorageMode
    var overrideCategory: String
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy = .ask
}

actor ImportSingleFileRecordingPredictor: CoreCategoryPredicting {
    private let result: ClassifyResultSnapshot
    private var requests: [ImportSingleFilePredictRequest] = []

    init(result: ClassifyResultSnapshot) {
        self.result = result
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(ImportSingleFilePredictRequest(repoPath: repoPath, filename: filename))
        return result
    }

    func recordedRequests() -> [ImportSingleFilePredictRequest] {
        requests
    }
}

actor ImportSingleFileRecordingImporter: CoreFileImporting {
    private var requests: [ImportSingleFileImportRequest] = []

    func importCopiedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        record(
            mode: .copy,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
    }

    func importMovedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        record(
            mode: .move,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
    }

    func importIndexedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        record(
            mode: .indexOnly,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
    }

    func recordedRequests() -> [ImportSingleFileImportRequest] {
        requests
    }

    private func record(
        mode: ImportSingleFileStorageMode,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) -> FileEntrySnapshot {
        requests.append(ImportSingleFileImportRequest(
            mode: mode,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        ))
        return FileEntrySnapshot.importSingleFileFixture(
            currentName: overrideFilename,
            category: overrideCategory,
            storageMode: mode.coreStorageMode
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

actor ImportSingleFileRecordingErrorMapper: CoreErrorMapping {
    private var errors: [CoreError] = []

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return .importSingleFileError(kind: CoreErrorKindTestMapper.kind(for: error))
    }

    func recordedErrors() -> [CoreError] {
        errors
    }
}

actor ImportSingleFileStaticRepositoryOpener: CoreEmptyRepositoryOpening {
    let opening: RepositoryOpeningResult

    init(opening: RepositoryOpeningResult) {
        self.opening = opening
    }

    func openConfiguredRepository(repoPath _: String) async throws -> RepositoryOpeningResult {
        opening
    }

    func openEmptyRepository(repoPath _: String) async throws -> RepositoryOpeningResult {
        opening
    }

    func openAdoptedRepository(repoPath _: String) async throws -> RepositoryOpeningResult {
        opening
    }
}
