import AreaMatrixCoreBridgeContract
import Foundation

enum ImportProgressDuplicateStrategy: String, Equatable {
    case skip
    case overwrite
    case keepBoth
    case ask

    init(coreStrategy: ImportDuplicateStrategySnapshot) {
        switch coreStrategy {
        case .skip:
            self = .skip
        case .overwrite:
            self = .overwrite
        case .keepBoth:
            self = .keepBoth
        case .ask:
            self = .ask
        }
    }

    var coreStrategy: ImportDuplicateStrategySnapshot {
        switch self {
        case .skip:
            .skip
        case .overwrite:
            .overwrite
        case .keepBoth:
            .keepBoth
        case .ask:
            .ask
        }
    }
}

struct ImportProgressRetryContext: Equatable {
    var repoPath: String
    var sourcePath: String
    var storageMode: ImportSingleFileStorageMode
    var overrideCategory: String
    var overrideFilename: String
    var duplicateStrategy: ImportProgressDuplicateStrategy
    var traceID: String?
    var operationID: String?

    init(
        repoPath: String,
        sourcePath: String,
        storageMode: ImportSingleFileStorageMode,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: ImportProgressDuplicateStrategy,
        traceID: String? = nil,
        operationID: String? = nil
    ) {
        self.repoPath = repoPath
        self.sourcePath = sourcePath
        self.storageMode = storageMode
        self.overrideCategory = overrideCategory
        self.overrideFilename = overrideFilename
        self.duplicateStrategy = duplicateStrategy
        self.traceID = traceID
        self.operationID = operationID
    }

    func replacingTraceContext(_ context: CoreImportTraceContext) -> Self {
        var updated = self
        updated.traceID = context.traceID
        updated.operationID = context.operationID
        return updated
    }
}

enum ImportProgressRecoveryCheckState: Equatable {
    case unavailable
    case checking
    case retryAllowed(RecoveryReportSnapshot?)
    case retryBlocked(String, RecoveryReportSnapshot?)
}

enum ImportProgressDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

enum ImportProgressStopState: Equatable {
    case idle
    case stopping
    case stopped
}

typealias ImportBatchProgressHandler = (ImportBatchProgressSnapshot) -> Void
typealias ImportBatchFailureHandler = (
    ImportBatchProgressSnapshot,
    CoreErrorMappingSnapshot,
    ImportProgressRetryContext?,
    ImportProgressRecoveryCheckState?
) -> Void

@MainActor
protocol ImportProgressQueueContinuing: AnyObject {
    func continueImportProgressQueue(
        afterRetried context: ImportProgressRetryContext,
        entry: FileEntrySnapshot,
        controlState: ImportProgressControlState,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void
    ) async -> ImportBatchImportResult?
}

final class ImportProgressControlState {
    private(set) var isStopAfterCurrentFileRequested = false
    private(set) var didStopAfterCurrentFile = false
    private(set) var queueContinuation: (any ImportProgressQueueContinuing)?

    func reset() {
        isStopAfterCurrentFileRequested = false
        didStopAfterCurrentFile = false
        queueContinuation = nil
    }

    func requestStopAfterCurrentFile() {
        isStopAfterCurrentFileRequested = true
    }

    func markStoppedAfterCurrentFile() {
        didStopAfterCurrentFile = true
        isStopAfterCurrentFileRequested = false
    }

    func registerQueueContinuation(_ continuation: (any ImportProgressQueueContinuing)?) {
        queueContinuation = continuation
    }

    func clearQueueContinuation() {
        queueContinuation = nil
    }
}
