import AreaMatrixFeatureAI
import Foundation

protocol CoreMetadataRepairing: Sendable {
    func preflightRepairMetadata(repoPath: String) async throws -> RepairMetadataPreflightSnapshot
    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot
}

protocol CoreRepositoryReindexing: Sendable {
    func reindexRepository(repoPath: String) async throws -> ReindexReportSnapshot
}

struct RepairOptionsSnapshot: Equatable {
    var preserveDiagnosticsSnapshot: Bool
    var preflightToken: String
    var repositoryLocalePolicy: String
}

enum RepairMetadataLocaleStateSnapshot: String, Equatable {
    case healthy = "Healthy"
    case metadataAbsent = "MetadataAbsent"
    case databaseMissing = "DatabaseMissing"
    case databaseCorrupt = "DatabaseCorrupt"
    case localeMissing = "LocaleMissing"
    case localeUnsupported = "LocaleUnsupported"
}

struct RepairMetadataPreflightSnapshot: Equatable {
    var localeState: RepairMetadataLocaleStateSnapshot
    var repositoryLocalePolicy: String?
    var unsupportedLocale: String?
    var requiresExplicitLocaleSelection: Bool
    var preflightToken: String
}

struct RepairReportSnapshot: Equatable {
    var diagnosticsSnapshotPath: String?
    var outcome: String
}

extension RepairReportSnapshot {
    init(coreReport: RepairReport) {
        diagnosticsSnapshotPath = coreReport.diagnosticsSnapshotPath
        switch coreReport.outcome {
        case .verified: outcome = "Verified"
        case .initialized: outcome = "Initialized"
        case .rebuilt: outcome = "Rebuilt"
        }
    }

    var summaryText: String {
        switch outcome {
        case "Verified": L10n.string("metadataRepair.outcome.verified")
        case "Initialized": L10n.string("metadataRepair.outcome.initialized")
        case "Rebuilt": L10n.string("metadataRepair.outcome.rebuilt")
        default: L10n.string("metadataRepair.outcome.unknown")
        }
    }
}

extension CoreBridge: CoreMetadataRepairing {
    func preflightRepairMetadata(repoPath: String) async throws -> RepairMetadataPreflightSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try RepairMetadataPreflightSnapshot(
                corePreflight: preflightCoreRepairMetadata(repoPath: repoPath)
            )
        }.value
    }

    func repairMetadata(repoPath: String, options: RepairOptionsSnapshot) async throws -> RepairReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let coreOptions = RepairOptions(
                preserveDiagnosticsSnapshot: options.preserveDiagnosticsSnapshot,
                preflightToken: options.preflightToken,
                repositoryLocalePolicy: options.repositoryLocalePolicy
            )
            return try RepairReportSnapshot(coreReport: repairCoreMetadata(repoPath: repoPath, options: coreOptions))
        }.value
    }
}

extension CoreBridge: CoreRepositoryReindexing {
    func reindexRepository(repoPath: String) async throws -> ReindexReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try ReindexReportSnapshot(coreReport: reindexCoreRepository(repoPath: repoPath))
        }.value
    }
}

private extension RepairMetadataPreflightSnapshot {
    init(corePreflight: RepairMetadataPreflight) {
        localeState = RepairMetadataLocaleStateSnapshot(coreState: corePreflight.localeState)
        repositoryLocalePolicy = corePreflight.repositoryLocalePolicy
        unsupportedLocale = corePreflight.unsupportedLocale
        requiresExplicitLocaleSelection = corePreflight.requiresExplicitLocaleSelection
        preflightToken = corePreflight.preflightToken
    }
}

private extension RepairMetadataLocaleStateSnapshot {
    init(coreState: RepairMetadataLocaleState) {
        switch coreState {
        case .healthy: self = .healthy
        case .metadataAbsent: self = .metadataAbsent
        case .databaseMissing: self = .databaseMissing
        case .databaseCorrupt: self = .databaseCorrupt
        case .localeMissing: self = .localeMissing
        case .localeUnsupported: self = .localeUnsupported
        }
    }
}

extension CoreBridge: CoreLocalModelStatusReading {
    func getLocalModelStatus(
        repoPath: String,
        request: LocalModelStatusRequestState
    ) async throws -> LocalModelStatusState {
        try await Task.detached(priority: .userInitiated) {
            try LocalModelStatusState(coreSnapshot: getCoreLocalModelStatus(
                repoPath: repoPath,
                request: LocalModelStatusRequest(snapshot: request)
            ))
        }.value
    }

    func locateLocalModelFolder(
        repoPath: String,
        request: LocalModelFolderRequestState
    ) async throws -> LocalModelFolderLocationState {
        try await Task.detached(priority: .userInitiated) {
            try LocalModelFolderLocationState(coreLocation: getCoreLocalModelFolder(
                repoPath: repoPath,
                request: LocalModelFolderRequest(snapshot: request)
            ))
        }.value
    }
}

private func repairCoreMetadata(repoPath: String, options: RepairOptions) throws -> RepairReport {
    try repairMetadata(repoPath: repoPath, options: options)
}

private func preflightCoreRepairMetadata(repoPath: String) throws -> RepairMetadataPreflight {
    try preflightRepairMetadata(repoPath: repoPath)
}

private func reindexCoreRepository(repoPath: String) throws -> ReindexReport {
    try reindexFromFilesystem(repoPath: repoPath)
}

private func getCoreLocalModelStatus(
    repoPath: String,
    request: LocalModelStatusRequest
) throws -> LocalModelStatusSnapshot {
    try getLocalModelStatus(repoPath: repoPath, request: request)
}

private func getCoreLocalModelFolder(
    repoPath: String,
    request: LocalModelFolderRequest
) throws -> LocalModelFolderLocation {
    try locateLocalModelFolder(repoPath: repoPath, request: request)
}

extension LocalModelStatusState {
    init(coreSnapshot: LocalModelStatusSnapshot) {
        self.init(
            modelID: coreSnapshot.modelId,
            storageLocation: coreSnapshot.storageLocation,
            availability: LocalModelAvailabilityState(coreAvailability: coreSnapshot.availability),
            version: coreSnapshot.version,
            sizeBytes: coreSnapshot.sizeBytes,
            lastError: coreSnapshot.lastError,
            recommendedAction: LocalModelRecommendedActionState(coreAction: coreSnapshot.recommendedAction),
            lastCheckedAt: coreSnapshot.lastCheckedAt,
            diagnosticsSummary: coreSnapshot.diagnosticsSummary,
            featureStatuses: coreSnapshot.featureStatuses.map(LocalModelFeatureStatusState.init(coreStatus:))
        )
    }
}

extension LocalModelAvailabilityState {
    // swiftlint:disable:next cyclomatic_complexity
    init(coreAvailability: LocalModelAvailability) {
        switch coreAvailability {
        case .unknown: self = .unknown
        case .ready: self = .ready
        case .notInstalled: self = .notInstalled
        case .pathUnreadable: self = .pathUnreadable
        case .versionIncompatible: self = .versionIncompatible
        case .checking: self = .checking
        case .verifying: self = .verifying
        case .loading: self = .loading
        case .corrupted: self = .corrupted
        case .runtimeFailed: self = .runtimeFailed
        case .error: self = .error
        }
    }
}

extension LocalModelRecommendedActionState {
    init(coreAction: LocalModelRecommendedAction) {
        switch coreAction {
        case .none: self = .none
        case .checkStatus: self = .checkStatus
        case .retryStatusCheck: self = .retryStatusCheck
        case .openInstallHelp: self = .openInstallHelp
        case .openModelLocation: self = .openModelLocation
        case .runHealthCheck: self = .runHealthCheck
        case .repairMetadata: self = .repairMetadata
        case .openDiagnostics: self = .openDiagnostics
        case .useNonAiFallback: self = .useNonAiFallback
        }
    }
}

extension LocalModelStatusRequest {
    init(snapshot: LocalModelStatusRequestState) {
        self.init(
            modelId: snapshot.modelID,
            storageLocation: snapshot.storageLocation,
            cachedStatus: snapshot.cachedStatus.map(LocalModelCachedStatus.init(snapshot:))
        )
    }
}

extension LocalModelFolderRequest {
    init(snapshot: LocalModelFolderRequestState) {
        self.init(modelId: snapshot.modelID, storageLocation: snapshot.storageLocation)
    }
}

private extension LocalModelFeatureStatusState {
    init(coreStatus: LocalModelFeatureStatus) {
        self.init(
            feature: AISettingsFeatureKind(coreFeature: coreStatus.feature),
            available: coreStatus.available,
            unavailableReason: coreStatus.unavailableReason
        )
    }
}

private extension LocalModelCachedStatus {
    init(snapshot: LocalModelCachedStatusState) {
        self.init(
            modelId: snapshot.modelID,
            storageLocation: snapshot.storageLocation,
            availability: LocalModelAvailability(snapshotAvailability: snapshot.availability),
            version: snapshot.version,
            sizeBytes: snapshot.sizeBytes,
            lastError: snapshot.lastError,
            recommendedAction: LocalModelRecommendedAction(snapshotAction: snapshot.recommendedAction),
            lastCheckedAt: snapshot.lastCheckedAt,
            diagnosticsSummary: snapshot.diagnosticsSummary
        )
    }
}

private extension LocalModelAvailability {
    // swiftlint:disable:next cyclomatic_complexity
    init(snapshotAvailability: LocalModelAvailabilityState) {
        switch snapshotAvailability {
        case .unknown: self = .unknown
        case .ready: self = .ready
        case .notInstalled: self = .notInstalled
        case .pathUnreadable: self = .pathUnreadable
        case .versionIncompatible: self = .versionIncompatible
        case .checking: self = .checking
        case .verifying: self = .verifying
        case .loading: self = .loading
        case .corrupted: self = .corrupted
        case .runtimeFailed: self = .runtimeFailed
        case .error: self = .error
        }
    }
}

private extension LocalModelRecommendedAction {
    init(snapshotAction: LocalModelRecommendedActionState) {
        switch snapshotAction {
        case .none: self = .none
        case .checkStatus: self = .checkStatus
        case .retryStatusCheck: self = .retryStatusCheck
        case .openInstallHelp: self = .openInstallHelp
        case .openModelLocation: self = .openModelLocation
        case .runHealthCheck: self = .runHealthCheck
        case .repairMetadata: self = .repairMetadata
        case .openDiagnostics: self = .openDiagnostics
        case .useNonAiFallback: self = .useNonAiFallback
        }
    }
}

private extension LocalModelFolderLocationState {
    init(coreLocation: LocalModelFolderLocation) {
        self.init(
            modelID: coreLocation.modelId,
            folderPath: coreLocation.folderPath,
            exists: coreLocation.exists,
            readable: coreLocation.readable,
            openable: coreLocation.openable,
            unavailableReason: coreLocation.unavailableReason
        )
    }
}

extension TagSuggestionApplyReportSnapshot {
    init(coreReport: TagSuggestionApplyReport) {
        self.init(
            fileID: coreReport.fileId,
            requestedCount: coreReport.requestedCount,
            appliedCount: coreReport.appliedCount,
            skippedCount: coreReport.skippedCount,
            failedCount: coreReport.failedCount,
            itemResults: coreReport.itemResults.map(TagSuggestionApplyItemResultSnapshot.init(coreResult:)),
            tagSet: TagSetSnapshot(coreTagSet: coreReport.tagSet),
            undoToken: coreReport.undoToken,
            refreshTargets: coreReport.refreshTargets
        )
    }
}

private extension TagSuggestionApplyItemResultSnapshot {
    init(coreResult: TagSuggestionApplyItemResult) {
        self.init(
            suggestionID: coreResult.suggestionId,
            slug: coreResult.slug,
            status: TagSuggestionApplyStatusSnapshot(coreStatus: coreResult.status),
            error: coreResult.error
        )
    }
}

private extension TagSuggestionApplyStatusSnapshot {
    init(coreStatus: TagSuggestionApplyStatus) {
        switch coreStatus {
        case .applied:
            self = .applied
        case .alreadyAdded:
            self = .alreadyAdded
        case .failed:
            self = .failed
        }
    }
}
