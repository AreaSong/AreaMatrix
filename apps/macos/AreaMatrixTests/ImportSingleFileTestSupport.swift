import Foundation
@testable import AreaMatrix

struct ImportSingleFileStaticPreflight: ImportSingleFilePreflighting {
    var result: ImportSingleFilePreflightResult

    static func ready(
        targetRelativePath: String = "docs/source.pdf"
    ) -> ImportSingleFileStaticPreflight {
        ImportSingleFileStaticPreflight(result: ImportSingleFilePreflightResult(
            sourceSizeBytes: 12,
            hashSha256: "hash",
            targetRelativePath: targetRelativePath,
            conflict: .none,
            replaceOptionVisibility: .hidden
        ))
    }

    func preflightSingleFileImport(
        request: ImportSingleFilePreflightRequest
    ) async -> ImportSingleFilePreflightResult {
        result
    }
}

struct ImportSingleFileStaticICloudDownloader: ICloudPlaceholderDownloading {
    var error: Error?

    func downloadPlaceholder(at sourceURL: URL) async throws {
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

struct S117PredictRequest: Equatable, Sendable {
    var repoPath: String
    var filename: String
}

struct S117ImportRequest: Equatable, Sendable {
    var mode: ImportSingleFileStorageMode
    var overrideCategory: String
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy = .ask
}

struct S118BatchImportRequest: Equatable, Sendable {
    var destination: ImportEntryDestination
    var suggestedCategory: String?
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy
}

actor S117RecordingPredictor: CoreCategoryPredicting {
    private let result: ClassifyResultSnapshot
    private var requests: [S117PredictRequest] = []

    init(result: ClassifyResultSnapshot) {
        self.result = result
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(S117PredictRequest(repoPath: repoPath, filename: filename))
        return result
    }

    func recordedRequests() -> [S117PredictRequest] {
        requests
    }
}

actor S117RecordingImporter: CoreFileImporting {
    private var requests: [S117ImportRequest] = []

    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
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
        repoPath: String,
        sourceURL: URL,
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
        repoPath: String,
        sourceURL: URL,
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

    func recordedRequests() -> [S117ImportRequest] {
        requests
    }

    private func record(
        mode: ImportSingleFileStorageMode,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) -> FileEntrySnapshot {
        requests.append(S117ImportRequest(
            mode: mode,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        ))
        return FileEntrySnapshot.s117Fixture(
            currentName: overrideFilename,
            category: overrideCategory,
            storageMode: mode.coreStorageMode
        )
    }
}

actor S117SuspendingImporter: CoreFileImporting {
    private let gate: S117ImportGate

    init(gate: S117ImportGate) {
        self.gate = gate
    }

    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        await gate.markStarted()
        await gate.waitUntilFinished()
        return FileEntrySnapshot.s117Fixture(currentName: overrideFilename, category: overrideCategory)
    }

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        throw CoreError.Internal(message: "unexpected move import")
    }

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        throw CoreError.Internal(message: "unexpected indexed import")
    }
}

actor S117ImportGate {
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

actor S117FailingImporter: CoreFileImporting {
    private let error: CoreError

    init(error: CoreError) {
        self.error = error
    }

    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        throw error
    }

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        throw error
    }

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        throw error
    }
}

actor S118RecordingBatchImporter: CoreBatchCopyImporting {
    private var requests: [S118BatchImportRequest] = []

    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        destination: ImportEntryDestination,
        suggestedCategory: String?,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        requests.append(S118BatchImportRequest(
            destination: destination,
            suggestedCategory: suggestedCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        ))

        let category: String
        switch destination {
        case .autoClassify:
            category = suggestedCategory ?? "inbox"
        case .category(let slug):
            category = slug
        case .repositoryRoot:
            category = "__root__"
        }

        return FileEntrySnapshot.s117Fixture(
            currentName: overrideFilename,
            category: category
        )
    }

    func recordedRequests() -> [S118BatchImportRequest] {
        requests
    }
}

actor S118FailingBatchImporter: CoreBatchCopyImporting {
    private let error: CoreError
    private var requests: [S118BatchImportRequest] = []

    init(error: CoreError) {
        self.error = error
    }

    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        destination: ImportEntryDestination,
        suggestedCategory: String?,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        requests.append(S118BatchImportRequest(
            destination: destination,
            suggestedCategory: suggestedCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        ))
        throw error
    }

    func recordedRequests() -> [S118BatchImportRequest] {
        requests
    }
}

actor S118SequenceBatchImporter: CoreBatchCopyImporting {
    private var results: [Result<FileEntrySnapshot, Error>]
    private var requests: [S118BatchImportRequest] = []

    init(results: [Result<FileEntrySnapshot, Error>]) {
        self.results = results
    }

    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        destination: ImportEntryDestination,
        suggestedCategory: String?,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        requests.append(S118BatchImportRequest(
            destination: destination,
            suggestedCategory: suggestedCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        ))
        guard !results.isEmpty else {
            throw CoreError.Internal(message: "missing batch import test result")
        }
        switch results.removeFirst() {
        case .success(let entry):
            return entry
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [S118BatchImportRequest] {
        requests
    }
}

actor S117RecordingErrorMapper: CoreErrorMapping {
    private var errors: [CoreError] = []

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return .s117Error(kind: kind(for: error))
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
        case .PermissionDenied:
            return .permissionDenied
        case .ICloudPlaceholder:
            return .iCloudPlaceholder
        case .Io:
            return .io
        case .Db:
            return .db
        default:
            return .internal
        }
    }
}

struct S117StaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? {
        repoPath
    }
}

struct S117NoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

@MainActor
final class S117RecordingAccessibilityAnnouncer: AccessibilityAnnouncing {
    private(set) var announcements: [String] = []

    func announce(_ message: String) {
        announcements.append(message)
    }
}

actor S117StaticRepositoryOpener: CoreEmptyRepositoryOpening {
    let opening: RepositoryOpeningResult

    init(opening: RepositoryOpeningResult) {
        self.opening = opening
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        opening
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        opening
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        opening
    }
}
