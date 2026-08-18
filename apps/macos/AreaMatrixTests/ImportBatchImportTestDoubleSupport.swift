@testable import AreaMatrix
import AreaMatrixFeatureIngestion
import Foundation
import XCTest

struct ImportBatchBatchImportRequest: Equatable {
    var storageMode: ImportSingleFileStorageMode = .copy
    var destination: ImportEntryDestination
    var suggestedCategory: String?
    var overrideFilename: String
    var duplicateStrategy: ImportDuplicateStrategySnapshot
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
            duplicateStrategy: request.duplicateStrategy,
            traceContext: request.traceContext
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

    func assertImportedBatchFiles(
        _ expectedImports: [ImportBatchBatchImportRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertImportBatchImportedFiles(requests, expectedImports, file: file, line: line)
    }

    func assertNoImportedBatchFiles(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertImportBatchNoImportedFiles(requests, file: file, line: line)
    }

    func assertLastImportedBatchFile(
        _ expectedImport: ImportBatchBatchImportRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertImportBatchLastImportedFile(requests, expectedImport, file: file, line: line)
    }

    func assertImportedOverrideFilenames(
        _ expectedFilenames: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertImportBatchImportedOverrideFilenames(requests, expectedFilenames, file: file, line: line)
    }

    func assertImportedDuplicateStrategies(
        _ expectedStrategies: [ImportDuplicateStrategySnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertImportBatchImportedDuplicateStrategies(requests, expectedStrategies, file: file, line: line)
    }
}

actor ImportBatchSequenceBatchImporter: CoreBatchCopyImporting {
    private var resultQueue: TestResultQueue<FileEntrySnapshot>
    private var requests: [ImportBatchBatchImportRequest] = []

    init(results: [Result<FileEntrySnapshot, Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .failure(CoreError.Internal(message: "missing batch import test result"))
        }
    }

    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        requests.append(ImportBatchBatchImportRequest(
            storageMode: .copy,
            destination: request.destination,
            suggestedCategory: request.suggestedCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))
        return try resultQueue.next()
    }

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        requests.append(ImportBatchBatchImportRequest(
            storageMode: request.storageMode,
            destination: request.destination,
            suggestedCategory: request.suggestedCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))
        return try resultQueue.next()
    }

    func assertImportedBatchFiles(
        _ expectedImports: [ImportBatchBatchImportRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertImportBatchImportedFiles(requests, expectedImports, file: file, line: line)
    }

    func assertNoImportedBatchFiles(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertImportBatchNoImportedFiles(requests, file: file, line: line)
    }

    func assertLastImportedBatchFile(
        _ expectedImport: ImportBatchBatchImportRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertImportBatchLastImportedFile(requests, expectedImport, file: file, line: line)
    }

    func assertImportedOverrideFilenames(
        _ expectedFilenames: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertImportBatchImportedOverrideFilenames(requests, expectedFilenames, file: file, line: line)
    }

    func assertImportedDuplicateStrategies(
        _ expectedStrategies: [ImportDuplicateStrategySnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertImportBatchImportedDuplicateStrategies(requests, expectedStrategies, file: file, line: line)
    }
}

private func assertImportBatchImportedFiles(
    _ requests: [ImportBatchBatchImportRequest],
    _ expectedImports: [ImportBatchBatchImportRequest],
    file: StaticString,
    line: UInt
) {
    XCTAssertEqual(requests, expectedImports, file: file, line: line)
}

private func assertImportBatchNoImportedFiles(
    _ requests: [ImportBatchBatchImportRequest],
    file: StaticString,
    line: UInt
) {
    assertImportBatchImportedFiles(requests, [], file: file, line: line)
}

private func assertImportBatchLastImportedFile(
    _ requests: [ImportBatchBatchImportRequest],
    _ expectedImport: ImportBatchBatchImportRequest,
    file: StaticString,
    line: UInt
) {
    XCTAssertEqual(requests.last, expectedImport, file: file, line: line)
}

private func assertImportBatchImportedOverrideFilenames(
    _ requests: [ImportBatchBatchImportRequest],
    _ expectedFilenames: [String],
    file: StaticString,
    line: UInt
) {
    XCTAssertEqual(requests.map(\.overrideFilename), expectedFilenames, file: file, line: line)
}

private func assertImportBatchImportedDuplicateStrategies(
    _ requests: [ImportBatchBatchImportRequest],
    _ expectedStrategies: [ImportDuplicateStrategySnapshot],
    file: StaticString,
    line: UInt
) {
    XCTAssertEqual(requests.map(\.duplicateStrategy), expectedStrategies, file: file, line: line)
}
