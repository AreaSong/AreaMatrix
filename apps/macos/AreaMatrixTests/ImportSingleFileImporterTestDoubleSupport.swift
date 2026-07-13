@testable import AreaMatrix
import Foundation
import XCTest

struct ImportSingleFileStaticLocalizedError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

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

actor ImportSingleFileRecordingImporter: CoreFileImporting {
    private var resultQueue: TestResultQueue<FileEntrySnapshot>?
    private var requests: [ImportSingleFileImportRequest] = []
    private var coreRequests: [ImportSingleFileCoreImportRequest] = []

    init(results: [Result<FileEntrySnapshot, Error>]? = nil) {
        if let results {
            resultQueue = TestResultQueue(results: results) {
                .failure(CoreError.Internal(message: "missing import test result"))
            }
        }
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

    func assertCoreImportRequests(
        _ expectedRequests: [ImportSingleFileCoreImportRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(coreRequests, expectedRequests, file: file, line: line)
    }

    func assertImportedFiles(
        _ expectedRequests: [ImportSingleFileImportRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, expectedRequests, file: file, line: line)
    }

    func assertNoImportedFiles(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertImportedFiles([], file: file, line: line)
    }

    func assertLastImportedFile(
        _ expectedRequest: ImportSingleFileImportRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests.last, expectedRequest, file: file, line: line)
    }

    func assertImportedDuplicateStrategies(
        _ expectedStrategies: [DuplicateStrategy],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests.map(\.duplicateStrategy), expectedStrategies, file: file, line: line)
    }

    private func record(_ request: ImportSingleFileCoreImportRequest) throws -> FileEntrySnapshot {
        requests.append(ImportSingleFileImportRequest(
            mode: request.mode,
            overrideCategory: request.overrideCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        ))
        coreRequests.append(request)
        if var resultQueue {
            let result = try resultQueue.next()
            self.resultQueue = resultQueue
            return result
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
