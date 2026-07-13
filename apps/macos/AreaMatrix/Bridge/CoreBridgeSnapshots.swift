import Foundation

enum ClassifyReasonSnapshot: String, Equatable {
    case keyword = "Keyword"
    case `extension` = "Extension"
    case aiPredicted = "AiPredicted"
    case `default` = "Default"

    var displayLabel: String {
        switch self {
        case .keyword:
            "keyword"
        case .extension:
            "extension"
        case .aiPredicted:
            "AI"
        case .default:
            "default"
        }
    }
}

struct ClassifyResultSnapshot: Equatable {
    var category: String
    var suggestedName: String
    var reason: ClassifyReasonSnapshot
    var confidence: Float

    var confidencePercent: Int {
        Int((confidence * 100).rounded())
    }
}

extension ClassifyResultSnapshot {
    init(coreResult: ClassifyResult) {
        category = coreResult.category
        suggestedName = coreResult.suggestedName
        reason = ClassifyReasonSnapshot(coreReason: coreResult.reason)
        confidence = coreResult.confidence
    }
}

private extension ClassifyReasonSnapshot {
    init(coreReason: ClassifyReason) {
        switch coreReason {
        case .keyword:
            self = .keyword
        case .extension:
            self = .extension
        case .aiPredicted:
            self = .aiPredicted
        case .default:
            self = .default
        }
    }
}

struct ReindexReportSnapshot: Equatable {
    var scanSessionId: Int64?
    var inserted: Int64
    var updated: Int64
    var skipped: Int64
    var errors: [String]
}

extension ReindexReportSnapshot {
    init(coreReport: ReindexReport) {
        scanSessionId = coreReport.scanSessionId
        inserted = coreReport.inserted
        updated = coreReport.updated
        skipped = coreReport.skipped
        errors = coreReport.errors
    }
}

extension ScanSessionSnapshot {
    init(coreSession: ScanSession) {
        id = coreSession.id
        kind = ScanSessionKindSnapshot(coreKind: coreSession.kind)
        status = ScanSessionStatusSnapshot(coreStatus: coreSession.status)
        lastPath = coreSession.lastPath
        inserted = coreSession.inserted
        updated = coreSession.updated
        skipped = coreSession.skipped
        startedAt = coreSession.startedAt
        updatedAt = coreSession.updatedAt
        finishedAt = coreSession.finishedAt
        errors = coreSession.errors
    }
}

private extension ScanSessionKindSnapshot {
    init(coreKind: ScanSessionKind) {
        switch coreKind {
        case .adopt:
            self = .adopt
        case .reindex:
            self = .reindex
        }
    }
}

private extension ScanSessionStatusSnapshot {
    init(coreStatus: ScanSessionStatus) {
        switch coreStatus {
        case .running:
            self = .running
        case .completed:
            self = .completed
        case .paused:
            self = .paused
        case .failed:
            self = .failed
        case .interrupted:
            self = .interrupted
        }
    }
}

extension RepoPathValidationSnapshot {
    init(coreValidation: RepoPathValidation) {
        let environment = RepositoryPathEnvironmentSnapshot.inspect(repoPath: coreValidation.repoPath)

        repoPath = coreValidation.repoPath
        exists = coreValidation.exists
        isDirectory = coreValidation.isDirectory
        isReadable = coreValidation.isReadable
        isWritable = coreValidation.isWritable
        isEmpty = coreValidation.isEmpty
        isInitialized = coreValidation.isInitialized
        isInsideAreaMatrix = coreValidation.isInsideAreaMatrix
        isICloudPath = coreValidation.isIcloudPath
        hasUnfinishedScanSession = coreValidation.hasUnfinishedScanSession
        availableCapacityBytes = environment.availableCapacityBytes
        isExternalVolume = environment.isExternalVolume
        recommendedMode = coreValidation.recommendedMode.map(RepoInitModeSnapshot.init(coreMode:))
        issues = coreValidation.issues.map(RepoPathIssueSnapshot.init(coreIssue:))
    }
}

private struct RepositoryPathEnvironmentSnapshot {
    var availableCapacityBytes: Int64?
    var isExternalVolume: Bool?

    static func inspect(repoPath: String) -> RepositoryPathEnvironmentSnapshot {
        do {
            let keys: Set<URLResourceKey> = [
                .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeIsInternalKey
            ]
            let values = try URL(fileURLWithPath: repoPath).resourceValues(forKeys: keys)
            return RepositoryPathEnvironmentSnapshot(
                availableCapacityBytes: values.volumeAvailableCapacityForImportantUsage ??
                    values.volumeAvailableCapacity.map(Int64.init),
                isExternalVolume: values.volumeIsInternal.map { !$0 }
            )
        } catch {
            return RepositoryPathEnvironmentSnapshot(availableCapacityBytes: nil, isExternalVolume: nil)
        }
    }
}

private extension RepoInitModeSnapshot {
    init(coreMode: RepoInitMode) {
        switch coreMode {
        case .createEmpty:
            self = .createEmpty
        case .adoptExisting:
            self = .adoptExisting
        }
    }
}

private extension RepoPathIssueSnapshot {
    // swiftlint:disable:next cyclomatic_complexity
    init(coreIssue: RepoPathIssue) {
        switch coreIssue {
        case .missingPath:
            self = .missingPath
        case .notDirectory:
            self = .notDirectory
        case .notReadable:
            self = .notReadable
        case .notWritable:
            self = .notWritable
        case .nonEmptyDirectory:
            self = .nonEmptyDirectory
        case .alreadyInitialized:
            self = .alreadyInitialized
        case .insideAreaMatrix:
            self = .insideAreaMatrix
        case .iCloudPath:
            self = .iCloudPath
        case .oneDrivePath:
            self = .oneDrivePath
        case .windowsReservedName:
            self = .windowsReservedName
        case .windowsCaseInsensitive:
            self = .windowsCaseInsensitive
        case .unfinishedScanSession:
            self = .unfinishedScanSession
        }
    }
}

protocol CoreLocalModelStatusReading: Sendable {
    func getLocalModelStatus(
        repoPath: String,
        request: LocalModelStatusRequestState
    ) async throws -> LocalModelStatusState
    func locateLocalModelFolder(
        repoPath: String,
        request: LocalModelFolderRequestState
    ) async throws -> LocalModelFolderLocationState
}

enum LocalModelAvailabilityState: String, Equatable {
    case unknown, ready, notInstalled, pathUnreadable, versionIncompatible
    case checking, verifying, loading, corrupted, runtimeFailed, error

    var isBusy: Bool {
        self == .checking || self == .verifying || self == .loading
    }
}

enum LocalModelRecommendedActionState: String, Equatable {
    case none, checkStatus, retryStatusCheck, openInstallHelp, openModelLocation
    case runHealthCheck, repairMetadata, openDiagnostics, useNonAiFallback
}

struct LocalModelFeatureStatusState: Equatable, Identifiable {
    var feature: AISettingsFeatureKind
    var available: Bool
    var unavailableReason: String?

    var id: String {
        feature.rawValue
    }
}

struct LocalModelCachedStatusState: Equatable {
    var modelID: String
    var storageLocation: String
    var availability: LocalModelAvailabilityState
    var version: String?
    var sizeBytes: Int64?
    var lastError: String?
    var recommendedAction: LocalModelRecommendedActionState
    var lastCheckedAt: Int64?
    var diagnosticsSummary: String
}
