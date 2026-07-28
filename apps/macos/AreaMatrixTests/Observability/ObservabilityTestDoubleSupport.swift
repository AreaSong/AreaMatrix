@testable import AreaMatrix
import Foundation

actor DiagnosticsIncidentManagerSpy: DiagnosticsIncidentManaging {
    enum DeleteFailure: Error {
        case rejected
    }

    private var snapshots: [ObservabilityIncidentSnapshot]
    private let deleteFailure: DeleteFailure?
    private var recordedDeletedIDs: [String] = []

    init(snapshots: [ObservabilityIncidentSnapshot], deleteFailure: DeleteFailure? = nil) {
        self.snapshots = snapshots
        self.deleteFailure = deleteFailure
    }

    func markIncident(note _: String?) -> String {
        "marked"
    }

    func updateIncident(id _: String, status _: String) throws {}

    func deleteIncident(id: String) throws {
        recordedDeletedIDs.append(id)
        if let deleteFailure { throw deleteFailure }
        snapshots.removeAll { $0.id == id }
    }

    func incidentSnapshots() -> [ObservabilityIncidentSnapshot] {
        snapshots
    }

    func deletedIDs() -> [String] {
        recordedDeletedIDs
    }
}

actor DiagnosticsIncidentCoreStub: CoreObservabilityControlling {
    func observabilityBuildContext() async -> ObservabilityBuildContextSnapshot {
        observabilityTestCoreBuildContext()
    }

    func initializeObservability(
        config _: ObservabilityConfig,
        sink _: any CoreObservabilitySink
    ) async throws -> ObservabilityHealth {
        .diagnosticsIncidentTestHealthy
    }

    func updateObservability(config _: ObservabilityConfig) async throws -> ObservabilityHealth {
        .diagnosticsIncidentTestHealthy
    }

    func observabilityHealth() async -> ObservabilityHealth {
        .diagnosticsIncidentTestHealthy
    }

    func flushObservability(deadlineMilliseconds _: UInt64) async throws -> ObservabilityHealth {
        .diagnosticsIncidentTestHealthy
    }
}

actor ImportTraceRecordingBatchImporter: CoreBatchCopyImporting {
    private var requests: [CoreBatchImportRequest] = []

    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        try await importBatchFile(request: request)
    }

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        requests.append(request)
        return FileEntrySnapshot.importSingleFileFixture(
            currentName: request.overrideFilename,
            category: request.suggestedCategory ?? "inbox",
            storageMode: request.storageMode.coreStorageMode
        )
    }

    func traceContexts() -> [CoreImportTraceContext] {
        requests.compactMap(\.traceContext)
    }
}

actor ImportTraceRecordingFileImporter: CoreObservedFileImporting {
    private var contexts: [CoreImportTraceContext] = []

    func importCopiedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy _: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        FileEntrySnapshot.importSingleFileFixture(currentName: overrideFilename, category: overrideCategory)
    }

    func importMovedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy _: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        FileEntrySnapshot.importSingleFileFixture(
            currentName: overrideFilename,
            category: overrideCategory,
            storageMode: "Moved"
        )
    }

    func importIndexedFile(
        repoPath _: String,
        sourceURL _: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy _: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        FileEntrySnapshot.importSingleFileFixture(
            currentName: overrideFilename,
            category: overrideCategory,
            storageMode: "Indexed"
        )
    }

    func importCopiedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot {
        contexts.append(request.traceContext)
        return try await importCopiedFile(
            repoPath: request.repoPath,
            sourceURL: request.sourceURL,
            overrideCategory: request.overrideCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        )
    }

    func importMovedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot {
        contexts.append(request.traceContext)
        return try await importMovedFile(
            repoPath: request.repoPath,
            sourceURL: request.sourceURL,
            overrideCategory: request.overrideCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        )
    }

    func importIndexedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot {
        contexts.append(request.traceContext)
        return try await importIndexedFile(
            repoPath: request.repoPath,
            sourceURL: request.sourceURL,
            overrideCategory: request.overrideCategory,
            overrideFilename: request.overrideFilename,
            duplicateStrategy: request.duplicateStrategy
        )
    }

    func traceContexts() -> [CoreImportTraceContext] {
        contexts
    }
}

struct SignpostCall: Equatable {
    enum Kind: Equatable {
        case begin
        case end
    }

    let kind: Kind
    let registration: ObservabilitySignpostRegistration
    let key: String
}

final class SignpostRecorderSpy: ObservabilitySignpostRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [SignpostCall] = []

    func begin(_ registration: ObservabilitySignpostRegistration, key: String) {
        append(.init(kind: .begin, registration: registration, key: key))
    }

    func end(_ registration: ObservabilitySignpostRegistration, key: String) {
        append(.init(kind: .end, registration: registration, key: key))
    }

    func calls() -> [SignpostCall] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    private func append(_ call: SignpostCall) {
        lock.lock()
        recordedCalls.append(call)
        lock.unlock()
    }
}

final class StubRepositoryMetadataCapture: RepositoryMetadataSnapshotCapturing {
    private(set) var callCount = 0
    private let payloads: [DiagnosticPackageAttachmentPayload]

    init(payloads: [DiagnosticPackageAttachmentPayload]) {
        self.payloads = payloads
    }

    func capture(repositoryURL _: URL) throws -> [DiagnosticPackageAttachmentPayload] {
        callCount += 1
        return payloads
    }
}
