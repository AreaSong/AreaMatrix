@testable import AreaMatrix
import Foundation

struct ImportBatchBatchImportRequest: Equatable {
    var storageMode: ImportSingleFileStorageMode = .copy
    var destination: ImportEntryDestination
    var suggestedCategory: String?
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy
}

actor ImportBatchRecordingBatchImporter: CoreBatchCopyImporting {
    private var requests: [ImportBatchBatchImportRequest] = []

    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        try await importBatchFile(request: CoreBatchImportRequest(
            repoPath: request.repoPath,
            sourceURL: request.sourceURL,
            storageMode: .copy,
            destination: request.destination,
            suggestedCategory: request.suggestedCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))
    }

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        requests.append(ImportBatchBatchImportRequest(
            storageMode: request.storageMode,
            destination: request.destination,
            suggestedCategory: request.suggestedCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))

        let category = switch request.destination {
        case .autoClassify:
            request.suggestedCategory ?? "inbox"
        case let .category(slug):
            slug
        case .repositoryRoot:
            "__root__"
        }

        return FileEntrySnapshot.importSingleFileFixture(
            currentName: request.overrideFilename,
            category: category,
            storageMode: request.storageMode.coreStorageMode
        )
    }

    func recordedRequests() -> [ImportBatchBatchImportRequest] {
        requests
    }
}

actor ImportBatchSequenceBatchImporter: CoreBatchCopyImporting {
    private var results: [Result<FileEntrySnapshot, Error>]
    private var requests: [ImportBatchBatchImportRequest] = []

    init(results: [Result<FileEntrySnapshot, Error>]) {
        self.results = results
    }

    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        requests.append(ImportBatchBatchImportRequest(
            storageMode: .copy,
            destination: request.destination,
            suggestedCategory: request.suggestedCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))
        guard !results.isEmpty else {
            throw CoreError.Internal(message: "missing batch import test result")
        }
        return try results.removeFirst().get()
    }

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        requests.append(ImportBatchBatchImportRequest(
            storageMode: request.storageMode,
            destination: request.destination,
            suggestedCategory: request.suggestedCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))
        guard !results.isEmpty else {
            throw CoreError.Internal(message: "missing batch import test result")
        }
        return try results.removeFirst().get()
    }

    func recordedRequests() -> [ImportBatchBatchImportRequest] {
        requests
    }
}
